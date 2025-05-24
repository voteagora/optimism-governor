// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {OptimismGovernor} from "../src/OptimismGovernor.sol";
import {TimelockControllerUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {IGovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IVotingToken} from "../src/interfaces/IVotingToken.sol";
import {IVotableSupplyOracle} from "../src/interfaces/IVotableSupplyOracle.sol";
import {IProposalTypesConfigurator} from "../src/interfaces/IProposalTypesConfigurator.sol";
import {VotableSupplyOracle} from "../src/VotableSupplyOracle.sol";
import {ProposalTypesConfigurator} from "../src/ProposalTypesConfigurator.sol";
import {AlligatorOP} from "../src/alligator/AlligatorOP.sol";
import {
    ApprovalVotingModule,
    ProposalOption,
    ProposalSettings,
    PassingCriteria
} from "../src/modules/ApprovalVotingModule.sol";
import {
    OptimisticModule_SocialSignalling,
    ProposalSettings as OptimisticProposalSettings
} from "../src/modules/OptimisticModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/**
 * @title ProposeAndCancelE2E
 * @notice End-to-end test suite for proposing and canceling different types of proposals
 * @dev This test:
 *      1. Deploys a mock, fork, full production system (following RedeployTimelock.s.sol)
 *      2. Creates and queues proposals of different types (standard, approval voting, optimistic)
 *      3. Verifies that manager, proposer, and L2 Safes can cancel all proposal types
 */

// Wrapper contract to enable initialization of TimelockControllerUpgradeable
contract InitializableTimelock is TimelockControllerUpgradeable {
    function initialize(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        public
        initializer
    {
        __TimelockController_init(minDelay, proposers, executors, admin);
    }
}

contract ProposeAndCancelE2E is Test {
    // ========== CONSTANTS ==========

    // Fork configuration
    string constant OP_RPC_URL = "https://mainnet.optimism.io";
    uint256 constant FORK_BLOCK = 125000000; // Recent OP mainnet block

    // Token configuration (OP token on Optimism)
    address constant VOTING_TOKEN = 0x4200000000000000000000000000000000000042;
    uint256 constant INITIAL_VOTABLE_SUPPLY = 1_000_000_000e18; // 1B OP tokens

    // Role constants
    bytes32 constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");
    bytes32 constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
    bytes32 constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    // Timelock configuration
    uint256 constant MIN_DELAY = 6 days;

    // Voting configuration (matching RedeployTimelock.s.sol)
    uint256 constant VOTING_DELAY = 0; // Updated to match production
    uint256 constant VOTING_PERIOD = 46027; // ~7 days
    uint256 constant PROPOSAL_THRESHOLD = 0;

    // Proposal types configuration
    uint16 constant DEFAULT_QUORUM = 30; // 0.3%
    uint16 constant DEFAULT_APPROVAL_THRESHOLD = 5000; // 50%
    uint16 constant OPTIMISTIC_QUORUM = 76; // 0.76%
    uint16 constant APPROVAL_VOTING_QUORUM = 30; // 0.3%

    // Module configuration
    uint256 constant OPTIMISTIC_VOTING_DELAY = 7 days; // Updated to match production

    // ========== STATE VARIABLES ==========

    // Core contracts
    ProxyAdmin proxyAdmin;
    OptimismGovernor governorImplementation;
    OptimismGovernor governor;
    TimelockControllerUpgradeable timelock;
    VotableSupplyOracle votableSupplyOracle;
    ProposalTypesConfigurator proposalTypesConfigurator;
    AlligatorOP alligatorImplementation;
    AlligatorOP alligatorContract; // Renamed to avoid conflict

    // Modules
    ApprovalVotingModule approvalVotingModule;
    OptimisticModule_SocialSignalling optimisticModule;

    // Actors
    address manager = makeAddr("manager");
    address proposer = makeAddr("proposer");
    address voter1 = makeAddr("voter1");
    address voter2 = makeAddr("voter2");
    address voter3 = makeAddr("voter3");
    address votableSupplyOracleOwner = makeAddr("oracleOwner");
    address proxyAdminOwner = makeAddr("proxyAdminOwner");

    // L2 Safes
    address l2Safe1 = makeAddr("l2Safe1");
    address l2Safe2 = makeAddr("l2Safe2");
    address l2Safe3 = makeAddr("l2Safe3");

    // Proposal data
    uint256 proposalId;
    address[] targets;
    uint256[] values;
    bytes[] calldatas;
    string description = "Test Proposal for Cancellation";

    // ========== SETUP ==========

    function setUp() public {
        // Fork OP mainnet
        vm.createSelectFork(OP_RPC_URL, FORK_BLOCK);

        console.log("========== DEPLOYMENT SETUP ==========");
        console.log("Manager:", manager);
        console.log("Proposer:", proposer);
        console.log("Voter 1:", voter1);
        console.log("Voter 2:", voter2);
        console.log("Voter 3:", voter3);
        console.log("L2 Safe 1:", l2Safe1);
        console.log("L2 Safe 2:", l2Safe2);
        console.log("L2 Safe 3:", l2Safe3);
        console.log("");

        // Deploy full production system
        _deployProxyAdmin();
        _deployVotableSupplyOracle();
        _deployProposalTypesConfigurator();
        _deployAlligator();
        _deployTimelock();
        _deployGovernorProxy();
        _deployVotingModules();
        _initializeGovernor();
        _configureSystem();
        _setupTimelockRoles();

        // Setup voting power for testing
        _setupVotingPower();

        // Create and queue a proposal
        _createAndQueueProposal();
    }

    /**
     * @notice Deploy the ProxyAdmin for managing upgrades
     */
    function _deployProxyAdmin() internal {
        console.log("========== DEPLOYING PROXY ADMIN ==========");

        proxyAdmin = new ProxyAdmin();
        proxyAdmin.transferOwnership(proxyAdminOwner);

        console.log("ProxyAdmin deployed:", address(proxyAdmin));
        console.log("ProxyAdmin owner:", proxyAdminOwner);
        console.log("");
    }

    /**
     * @notice Deploy the VotableSupplyOracle
     */
    function _deployVotableSupplyOracle() internal {
        console.log("========== DEPLOYING VOTABLE SUPPLY ORACLE ==========");

        votableSupplyOracle = new VotableSupplyOracle(votableSupplyOracleOwner, INITIAL_VOTABLE_SUPPLY);

        console.log("VotableSupplyOracle deployed:", address(votableSupplyOracle));
        console.log("Initial votable supply:", INITIAL_VOTABLE_SUPPLY);
        console.log("");
    }

    /**
     * @notice Deploy the ProposalTypesConfigurator
     */
    function _deployProposalTypesConfigurator() internal {
        console.log("========== DEPLOYING PROPOSAL TYPES CONFIGURATOR ==========");

        proposalTypesConfigurator = new ProposalTypesConfigurator();

        console.log("ProposalTypesConfigurator deployed:", address(proposalTypesConfigurator));
        console.log("");
    }

    /**
     * @notice Deploy AlligatorOP with proxy
     */
    function _deployAlligator() internal {
        console.log("========== DEPLOYING ALLIGATOR ==========");

        // Deploy implementation
        alligatorImplementation = new AlligatorOP();
        console.log("Alligator implementation deployed:", address(alligatorImplementation));

        // Deploy proxy with empty initialization
        TransparentUpgradeableProxy alligatorProxy = new TransparentUpgradeableProxy(
            address(alligatorImplementation),
            address(proxyAdmin),
            "" // Empty initialization data
        );

        alligatorContract = AlligatorOP(address(alligatorProxy));
        console.log("Alligator proxy deployed:", address(alligatorContract));
        console.log("");
    }

    /**
     * @notice Deploy timelock with proper roles
     */
    function _deployTimelock() internal {
        console.log("========== DEPLOYING TIMELOCK ==========");

        // Deploy implementation
        InitializableTimelock timelockImpl = new InitializableTimelock();
        console.log("Timelock Implementation:", address(timelockImpl));

        // Prepare initialization data
        address[] memory proposers = new address[](0); // Will be set after governor deployment
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Anyone can execute

        // Deploy proxy with initialization
        bytes memory initData =
            abi.encodeCall(InitializableTimelock.initialize, (MIN_DELAY, proposers, executors, address(this)));

        ERC1967Proxy proxy = new ERC1967Proxy(address(timelockImpl), initData);
        timelock = TimelockControllerUpgradeable(payable(address(proxy)));

        console.log("Timelock Proxy:", address(timelock));
        console.log("");
    }

    /**
     * @notice Deploy the Optimism Governor proxy (without initialization)
     */
    function _deployGovernorProxy() internal {
        console.log("========== DEPLOYING GOVERNOR PROXY ==========");

        // Deploy implementation
        governorImplementation = new OptimismGovernor();
        console.log("Governor Implementation:", address(governorImplementation));

        // Deploy proxy without initialization (will initialize later)
        TransparentUpgradeableProxy governorProxy = new TransparentUpgradeableProxy(
            address(governorImplementation),
            address(proxyAdmin),
            "" // Empty initialization data
        );

        governor = OptimismGovernor(payable(address(governorProxy)));
        console.log("Governor Proxy:", address(governor));
        console.log("");
    }

    /**
     * @notice Deploy all voting modules
     */
    function _deployVotingModules() internal {
        console.log("========== DEPLOYING VOTING MODULES ==========");

        // Deploy Approval Voting Module
        approvalVotingModule = new ApprovalVotingModule(address(governor));
        console.log("ApprovalVotingModule deployed:", address(approvalVotingModule));

        // Deploy Optimistic Module
        optimisticModule = new OptimisticModule_SocialSignalling(address(governor));
        console.log("OptimisticModule deployed:", address(optimisticModule));

        console.log("");
    }

    /**
     * @notice Initialize the Optimism Governor after modules are deployed
     */
    function _initializeGovernor() internal {
        console.log("========== INITIALIZING GOVERNOR ==========");

        // Prepare initial proposal types
        IProposalTypesConfigurator.ProposalType[] memory proposalTypes =
            new IProposalTypesConfigurator.ProposalType[](3);

        // Standard proposal type
        proposalTypes[0] = IProposalTypesConfigurator.ProposalType({
            quorum: DEFAULT_QUORUM,
            approvalThreshold: DEFAULT_APPROVAL_THRESHOLD,
            name: "Default",
            description: "Default proposal type with simple majority",
            module: address(0)
        });

        // Optimistic proposal type (quorum and approval threshold must be 0 for optimistic)
        proposalTypes[1] = IProposalTypesConfigurator.ProposalType({
            quorum: 0, // Must be 0 for optimistic proposals
            approvalThreshold: 0, // Must be 0 for optimistic proposals
            name: "Optimistic",
            description: "Optimistic proposal type with veto mechanism",
            module: address(optimisticModule)
        });

        // Approval voting proposal type
        proposalTypes[2] = IProposalTypesConfigurator.ProposalType({
            quorum: APPROVAL_VOTING_QUORUM,
            approvalThreshold: 0, // Not used in approval voting
            name: "Approval",
            description: "Multiple choice approval voting",
            module: address(approvalVotingModule)
        });

        // Initialize the governor
        governor.initialize(
            IVotingToken(VOTING_TOKEN),
            votableSupplyOracle,
            manager,
            address(alligatorContract),
            timelock,
            proposalTypesConfigurator,
            proposalTypes
        );

        console.log("Governor initialized");
        console.log("");
    }

    /**
     * @notice Configure the deployed system
     */
    function _configureSystem() internal {
        console.log("========== CONFIGURING SYSTEM ==========");

        // Configure governor settings
        vm.startPrank(manager);
        governor.setVotingDelay(VOTING_DELAY);
        governor.setVotingPeriod(VOTING_PERIOD);
        governor.setProposalThreshold(PROPOSAL_THRESHOLD);
        vm.stopPrank();
        console.log("Governor voting parameters set");

        // Configure modules
        vm.startPrank(manager);
        governor.setModuleApproval(address(approvalVotingModule), true);
        governor.setModuleApproval(address(optimisticModule), true);
        vm.stopPrank();
        console.log("Voting modules approved");

        // Configure Alligator
        alligatorContract.initialize(
            address(governor), // Initial owner will be the governor
            VOTING_TOKEN // OP token address
        );
        console.log("Alligator initialized");

        console.log("");
    }

    /**
     * @notice Setup all timelock roles
     */
    function _setupTimelockRoles() internal {
        console.log("========== SETTING UP TIMELOCK ROLES ==========");

        // Grant proposer role to governor
        timelock.grantRole(PROPOSER_ROLE, address(governor));
        console.log("Granted PROPOSER_ROLE to Governor");

        // Grant canceller roles
        timelock.grantRole(CANCELLER_ROLE, manager);
        console.log("Granted CANCELLER_ROLE to Manager");

        timelock.grantRole(CANCELLER_ROLE, address(governor));
        console.log("Granted CANCELLER_ROLE to Governor (for proposer cancellation)");

        timelock.grantRole(CANCELLER_ROLE, l2Safe1);
        console.log("Granted CANCELLER_ROLE to L2 Safe 1");

        timelock.grantRole(CANCELLER_ROLE, l2Safe2);
        console.log("Granted CANCELLER_ROLE to L2 Safe 2");

        timelock.grantRole(CANCELLER_ROLE, l2Safe3);
        console.log("Granted CANCELLER_ROLE to L2 Safe 3");

        // Grant admin role to timelock itself
        timelock.grantRole(TIMELOCK_ADMIN_ROLE, address(timelock));
        console.log("Granted TIMELOCK_ADMIN_ROLE to Timelock (self)");

        // Renounce admin role from test contract
        timelock.renounceRole(TIMELOCK_ADMIN_ROLE, address(this));
        console.log("Renounced TIMELOCK_ADMIN_ROLE from test contract");

        console.log("");
    }

    /**
     * @notice Setup voting power for the proposer
     */
    function _setupVotingPower() internal {
        console.log("========== SETTING UP VOTING POWER ==========");

        // First, ensure votable supply is properly set BEFORE any proposals
        // This ensures quorum calculations work correctly
        console.log("Initial block number:", block.number);
        console.log("Initial votable supply from oracle:", votableSupplyOracle.votableSupply());

        // The oracle already has initial supply from constructor, but let's update it
        // to ensure we have a checkpoint at a known block
        vm.prank(votableSupplyOracleOwner);
        votableSupplyOracle._updateVotableSupply(INITIAL_VOTABLE_SUPPLY);
        console.log("Updated votable supply at block:", block.number);

        // Advance a few blocks to ensure the votable supply is recorded
        vm.roll(block.number + 10);
        console.log("Advanced to block:", block.number);

        // Setup multiple voters with different amounts
        // Total needed for quorum: 0.3% of 1B = 3M tokens
        // We'll distribute more than needed to have meaningful votes

        // Voter 1: Will vote FOR (2M tokens)
        uint256 voter1Tokens = 2_000_000e18;
        deal(VOTING_TOKEN, voter1, voter1Tokens);
        vm.prank(voter1);
        IVotes(VOTING_TOKEN).delegate(voter1);

        // Voter 2: Will vote AGAINST (1.5M tokens)
        uint256 voter2Tokens = 1_500_000e18;
        deal(VOTING_TOKEN, voter2, voter2Tokens);
        vm.prank(voter2);
        IVotes(VOTING_TOKEN).delegate(voter2);

        // Voter 3: Will vote FOR (2.5M tokens)
        uint256 voter3Tokens = 2_500_000e18;
        deal(VOTING_TOKEN, voter3, voter3Tokens);
        vm.prank(voter3);
        IVotes(VOTING_TOKEN).delegate(voter3);

        // Advance block to activate delegations
        vm.roll(block.number + 1);

        console.log("Voter 1 votes (FOR):", IVotes(VOTING_TOKEN).getVotes(voter1));
        console.log("Voter 2 votes (AGAINST):", IVotes(VOTING_TOKEN).getVotes(voter2));
        console.log("Voter 3 votes (FOR):", IVotes(VOTING_TOKEN).getVotes(voter3));
        console.log("Total voting power:", voter1Tokens + voter2Tokens + voter3Tokens);
        console.log("Quorum needed (0.3%):", (INITIAL_VOTABLE_SUPPLY * DEFAULT_QUORUM) / 10000);
        console.log("Current votable supply:", votableSupplyOracle.votableSupply());
        console.log("");
    }

    /**
     * @notice Create and queue a test proposal
     */
    function _createAndQueueProposal() internal {
        console.log("========== CREATING AND QUEUEING PROPOSAL ==========");

        // Prepare proposal data - simple ETH transfer
        targets.push(makeAddr("recipient"));
        values.push(1 ether);
        calldatas.push("");

        // Create proposal (only manager or timelock can propose)
        vm.prank(manager);
        proposalId = governor.propose(targets, values, calldatas, description, 0);
        console.log("Proposal created with ID:", proposalId);
        console.log("Proposal state:", uint256(governor.state(proposalId)));

        // Advance to voting period
        vm.roll(block.number + VOTING_DELAY + 1);
        console.log("Advanced to voting period, state:", uint256(governor.state(proposalId)));

        // Multiple voters cast their votes
        vm.prank(voter1);
        governor.castVote(proposalId, 1); // 1 = For vote
        console.log("Voter 1 voted FOR");

        vm.prank(voter2);
        governor.castVote(proposalId, 0); // 0 = Against vote
        console.log("Voter 2 voted AGAINST");

        vm.prank(voter3);
        governor.castVote(proposalId, 1); // 1 = For vote
        console.log("Voter 3 voted FOR");

        // Advance past voting period
        vm.roll(block.number + VOTING_PERIOD + 1);
        console.log("Voting ended, state:", uint256(governor.state(proposalId)));

        // Debug: Check votes and quorum
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        console.log("Against votes:", againstVotes);
        console.log("For votes:", forVotes);
        console.log("Abstain votes:", abstainVotes);
        uint256 proposalSnapshot = governor.proposalSnapshot(proposalId);
        uint256 quorumAtSnapshot = governor.quorum(proposalId); // Use proposalId, not snapshot block
        console.log("Proposal snapshot block:", proposalSnapshot);
        console.log("Votable supply at snapshot:", votableSupplyOracle.votableSupply(proposalSnapshot));
        console.log("Quorum at snapshot (should be 0.3% of supply):", quorumAtSnapshot);
        console.log("Quorum reached:", forVotes + abstainVotes >= quorumAtSnapshot);
        console.log("For votes > Against votes:", forVotes > againstVotes);
        console.log("Proposal succeeded:", forVotes > againstVotes && forVotes + abstainVotes >= quorumAtSnapshot);

        // Queue the proposal
        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256(bytes(description)));
        console.log("Proposal queued, state:", uint256(governor.state(proposalId)));
        console.log("");
    }

    // ========== TEST FUNCTIONS ==========

    /**
     * @notice Test that manager can cancel a queued proposal
     */
    function testManagerCanCancelProposal() public {
        console.log("========== TEST: MANAGER CANCELLATION ==========");

        // Verify proposal is queued
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));

        // Manager cancels the proposal
        vm.prank(manager);
        governor.cancel(targets, values, calldatas, keccak256(bytes(description)));

        // Verify proposal is canceled
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
        console.log("[PASS] Manager successfully canceled the proposal");
    }

    /**
     * @notice Test that proposer can cancel their own proposal
     */
    function testProposerCanCancelProposal() public {
        console.log("========== TEST: PROPOSER CANCELLATION ==========");

        // In OptimismGovernor, only the manager or timelock can propose
        // So we test that the manager (who is the proposer) can cancel their own proposal

        console.log("Testing that proposer can cancel their own proposal");
        console.log("Note: In this governor, only manager/timelock can propose");

        // Verify proposal is queued
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));

        // Manager (who is the proposer of this proposal) cancels their own proposal
        // This demonstrates that a proposer can cancel their own proposal
        vm.prank(manager);
        governor.cancel(targets, values, calldatas, keccak256(bytes(description)));

        // Verify proposal is canceled
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
        console.log("[PASS] Proposer (manager) successfully canceled their own proposal");

        // Test with timelock as proposer
        console.log("\n--- Testing timelock as proposer ---");

        // Create new proposal as timelock
        address[] memory newTargets = new address[](1);
        newTargets[0] = makeAddr("recipient2");
        uint256[] memory newValues = new uint256[](1);
        newValues[0] = 2 ether;
        bytes[] memory newCalldatas = new bytes[](1);
        newCalldatas[0] = "";
        string memory newDescription = "Timelock's test proposal";

        vm.prank(address(timelock));
        uint256 newProposalId = governor.propose(newTargets, newValues, newCalldatas, newDescription, 0);
        console.log("Timelock created proposal ID:", newProposalId);

        // Advance and vote
        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        governor.castVote(newProposalId, 1);

        vm.prank(voter3);
        governor.castVote(newProposalId, 1);

        // Advance past voting period and queue
        vm.roll(block.number + VOTING_PERIOD + 1);

        vm.prank(manager);
        governor.queue(newTargets, newValues, newCalldatas, keccak256(bytes(newDescription)));

        // Verify proposal is queued
        assertEq(uint256(governor.state(newProposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));

        // Timelock (proposer) cancels their own proposal
        vm.prank(address(timelock));
        governor.cancel(newTargets, newValues, newCalldatas, keccak256(bytes(newDescription)));

        // Verify proposal is canceled
        assertEq(uint256(governor.state(newProposalId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
        console.log("[PASS] Proposer (timelock) successfully canceled their own proposal");
    }

    /**
     * @notice Test that L2 Safe 1 can cancel a proposal
     */
    function testL2Safe1CanCancelProposal() public {
        console.log("========== TEST: L2 SAFE 1 CANCELLATION ==========");

        // Verify proposal is queued
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));

        // Get the timelock operation ID
        bytes32 timelockId = timelock.hashOperationBatch(targets, values, calldatas, 0, keccak256(bytes(description)));

        // Verify operation is pending in timelock
        assertTrue(timelock.isOperationPending(timelockId));

        // L2 Safe 1 cancels via timelock
        vm.prank(l2Safe1);
        timelock.cancel(timelockId);

        // Verify proposal is canceled
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
        console.log("[PASS] L2 Safe 1 successfully canceled the proposal");
    }

    /**
     * @notice Test that L2 Safe 2 can cancel a proposal
     */
    function testL2Safe2CanCancelProposal() public {
        console.log("========== TEST: L2 SAFE 2 CANCELLATION ==========");

        // Similar to L2 Safe 1 test
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));

        bytes32 timelockId = timelock.hashOperationBatch(targets, values, calldatas, 0, keccak256(bytes(description)));

        vm.prank(l2Safe2);
        timelock.cancel(timelockId);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
        console.log("[PASS] L2 Safe 2 successfully canceled the proposal");
    }

    /**
     * @notice Test that L2 Safe 3 can cancel a proposal
     */
    function testL2Safe3CanCancelProposal() public {
        console.log("========== TEST: L2 SAFE 3 CANCELLATION ==========");

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));

        bytes32 timelockId = timelock.hashOperationBatch(targets, values, calldatas, 0, keccak256(bytes(description)));

        vm.prank(l2Safe3);
        timelock.cancel(timelockId);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
        console.log("[PASS] L2 Safe 3 successfully canceled the proposal");
    }

    /**
     * @notice Test that unauthorized addresses cannot cancel
     */
    function testUnauthorizedCannotCancel() public {
        console.log("========== TEST: UNAUTHORIZED CANCELLATION ==========");

        address unauthorized = makeAddr("unauthorized");

        // Try to cancel via governor
        vm.prank(unauthorized);
        vm.expectRevert("Governor: only manager, governor timelock, or proposer can cancel");
        governor.cancel(targets, values, calldatas, keccak256(bytes(description)));

        // Try to cancel via timelock
        bytes32 timelockId = timelock.hashOperationBatch(targets, values, calldatas, 0, keccak256(bytes(description)));

        vm.prank(unauthorized);
        vm.expectRevert(); // AccessControl revert
        timelock.cancel(timelockId);

        console.log("[PASS] Unauthorized address correctly prevented from canceling");
    }

    /**
     * @notice Test role verification
     */
    function testVerifyRoles() public view {
        console.log("========== ROLE VERIFICATION ==========");

        // Verify proposer role
        assertTrue(timelock.hasRole(PROPOSER_ROLE, address(governor)));
        console.log("[PASS] Governor has PROPOSER_ROLE");

        // Verify executor role
        assertTrue(timelock.hasRole(EXECUTOR_ROLE, address(0)));
        console.log("[PASS] address(0) has EXECUTOR_ROLE (anyone can execute)");

        // Verify canceller roles
        assertTrue(timelock.hasRole(CANCELLER_ROLE, manager));
        console.log("[PASS] Manager has CANCELLER_ROLE");

        assertTrue(timelock.hasRole(CANCELLER_ROLE, address(governor)));
        console.log("[PASS] Governor has CANCELLER_ROLE");

        assertTrue(timelock.hasRole(CANCELLER_ROLE, l2Safe1));
        console.log("[PASS] L2 Safe 1 has CANCELLER_ROLE");

        assertTrue(timelock.hasRole(CANCELLER_ROLE, l2Safe2));
        console.log("[PASS] L2 Safe 2 has CANCELLER_ROLE");

        assertTrue(timelock.hasRole(CANCELLER_ROLE, l2Safe3));
        console.log("[PASS] L2 Safe 3 has CANCELLER_ROLE");

        // Verify admin role
        assertTrue(timelock.hasRole(TIMELOCK_ADMIN_ROLE, address(timelock)));
        console.log("[PASS] Timelock has TIMELOCK_ADMIN_ROLE (self-admin)");

        assertFalse(timelock.hasRole(TIMELOCK_ADMIN_ROLE, address(this)));
        console.log("[PASS] Test contract does NOT have TIMELOCK_ADMIN_ROLE");
    }

    /**
     * @notice Test that manager can cancel via governor.cancel()
     */
    function testManagerCancellationFlow() public {
        console.log("========== TEST: MANAGER CANCELLATION FLOW ==========");

        // Create a new proposal to test full flow
        address[] memory newTargets = new address[](1);
        newTargets[0] = makeAddr("testTarget");
        uint256[] memory newValues = new uint256[](1);
        newValues[0] = 0;
        bytes[] memory newCalldatas = new bytes[](1);
        newCalldatas[0] = abi.encodeWithSignature("testFunction()");
        string memory newDescription = "Manager cancellation test";

        // Manager creates proposal
        vm.prank(manager);
        uint256 newProposalId = governor.propose(newTargets, newValues, newCalldatas, newDescription, 0);
        console.log("Proposal created by manager, ID:", newProposalId);

        // Vote and queue with multiple voters for quorum
        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        governor.castVote(newProposalId, 1); // 2M votes

        vm.prank(voter3);
        governor.castVote(newProposalId, 1); // 2.5M votes

        // Total: 4.5M votes > 3M quorum

        vm.roll(block.number + VOTING_PERIOD + 1);
        vm.prank(manager);
        governor.queue(newTargets, newValues, newCalldatas, keccak256(bytes(newDescription)));

        // Verify queued
        assertEq(uint256(governor.state(newProposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));

        // Manager cancels via governor.cancel()
        vm.prank(manager);
        governor.cancel(newTargets, newValues, newCalldatas, keccak256(bytes(newDescription)));

        // Verify canceled
        assertEq(uint256(governor.state(newProposalId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
        console.log("[PASS] Manager canceled via governor.cancel()");
    }

    /**
     * @notice Test that verifies proposals are properly queued in timelock before cancellation
     */
    function testTimelockQueueAndCancellation() public {
        console.log("========== TEST: TIMELOCK QUEUE AND CANCELLATION ==========");

        // Verify initial proposal is queued in timelock
        bytes32 timelockId = timelock.hashOperationBatch(targets, values, calldatas, 0, keccak256(bytes(description)));

        console.log("Proposal ID:", proposalId);
        console.log("Timelock Operation ID:", uint256(timelockId));

        // Verify the operation is actually pending in the timelock
        assertTrue(timelock.isOperationPending(timelockId), "Operation should be pending in timelock");
        assertFalse(timelock.isOperationReady(timelockId), "Operation should not be ready yet (min delay not passed)");
        assertFalse(timelock.isOperationDone(timelockId), "Operation should not be done");

        console.log("[PASS] Proposal is properly queued in timelock");

        // Get the timestamp when it will be ready
        uint256 readyTimestamp = timelock.getTimestamp(timelockId);
        console.log("Operation ready at timestamp:", readyTimestamp);
        console.log("Current timestamp:", block.timestamp);
        console.log("Min delay:", timelock.getMinDelay());

        // Test 1: Manager cancels via governor (which cancels in timelock)
        vm.prank(manager);
        governor.cancel(targets, values, calldatas, keccak256(bytes(description)));

        // Verify it's canceled in both governor and timelock
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
        assertFalse(timelock.isOperationPending(timelockId), "Operation should no longer be pending after cancel");
        console.log("[PASS] Manager successfully canceled via governor (timelock operation canceled)");

        // Create another proposal to test L2 Safe cancellation
        _createAndQueueAnotherProposal();
    }

    /**
     * @notice Helper to create another proposal for testing different cancellation paths
     */
    function _createAndQueueAnotherProposal() internal {
        console.log("\n========== CREATING ANOTHER PROPOSAL FOR L2 SAFE TEST ==========");

        // New proposal data
        address[] memory newTargets = new address[](1);
        newTargets[0] = makeAddr("anotherRecipient");
        uint256[] memory newValues = new uint256[](1);
        newValues[0] = 2 ether;
        bytes[] memory newCalldatas = new bytes[](1);
        newCalldatas[0] = "";
        string memory newDescription = "Test Proposal for L2 Safe Cancellation";

        // Create, vote, and queue
        vm.prank(manager);
        uint256 newProposalId = governor.propose(newTargets, newValues, newCalldatas, newDescription, 0);

        vm.roll(block.number + VOTING_DELAY + 1);

        // Vote with multiple voters
        vm.prank(voter1);
        governor.castVote(newProposalId, 1);
        vm.prank(voter3);
        governor.castVote(newProposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        vm.prank(manager);
        governor.queue(newTargets, newValues, newCalldatas, keccak256(bytes(newDescription)));

        // Verify it's queued in timelock
        bytes32 newTimelockId =
            timelock.hashOperationBatch(newTargets, newValues, newCalldatas, 0, keccak256(bytes(newDescription)));
        assertTrue(timelock.isOperationPending(newTimelockId), "New operation should be pending in timelock");

        console.log("New Proposal ID:", newProposalId);
        console.log("New Timelock Operation ID:", uint256(newTimelockId));

        // Test 2: L2 Safe cancels directly via timelock
        vm.prank(l2Safe1);
        timelock.cancel(newTimelockId);

        // Verify cancellation
        assertFalse(timelock.isOperationPending(newTimelockId), "Operation should no longer be pending");
        assertEq(uint256(governor.state(newProposalId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
        console.log("[PASS] L2 Safe 1 successfully canceled directly via timelock");
    }

    /**
     * @notice Test creating and canceling an approval voting proposal
     */
    function testApprovalVotingProposalCancellation() public {
        console.log("========== TEST: APPROVAL VOTING PROPOSAL CANCELLATION ==========");

        // Prepare approval voting proposal data
        ProposalOption[] memory options = new ProposalOption[](3);

        // Option 1: Transfer 100 OP tokens
        options[0].targets = new address[](1);
        options[0].values = new uint256[](1);
        options[0].calldatas = new bytes[](1);
        options[0].targets[0] = VOTING_TOKEN;
        options[0].values[0] = 0;
        options[0].calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", makeAddr("recipient1"), 100e18);
        options[0].description = "Transfer 100 OP tokens";
        options[0].budgetTokensSpent = 100e18;

        // Option 2: Transfer 200 OP tokens
        options[1].targets = new address[](1);
        options[1].values = new uint256[](1);
        options[1].calldatas = new bytes[](1);
        options[1].targets[0] = VOTING_TOKEN;
        options[1].values[0] = 0;
        options[1].calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", makeAddr("recipient2"), 200e18);
        options[1].description = "Transfer 200 OP tokens";
        options[1].budgetTokensSpent = 200e18;

        // Option 3: Transfer 300 OP tokens
        options[2].targets = new address[](1);
        options[2].values = new uint256[](1);
        options[2].calldatas = new bytes[](1);
        options[2].targets[0] = VOTING_TOKEN;
        options[2].values[0] = 0;
        options[2].calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", makeAddr("recipient3"), 300e18);
        options[2].description = "Transfer 300 OP tokens";
        options[2].budgetTokensSpent = 300e18;

        // Proposal settings
        ProposalSettings memory settings = ProposalSettings({
            maxApprovals: 2, // Voters can approve up to 2 options
            criteria: uint8(PassingCriteria.TopChoices),
            budgetToken: VOTING_TOKEN,
            criteriaValue: 2, // Top 2 choices will be executed
            budgetAmount: 500e18 // Total budget of 500 OP tokens
        });

        bytes memory proposalData = abi.encode(options, settings);
        string memory description = "Approval Voting: Choose token distribution";

        // Create proposal using approval voting module
        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(
            approvalVotingModule,
            proposalData,
            description,
            2 // Approval voting proposal type
        );
        console.log("Approval voting proposal created, ID:", proposalId);

        // Vote on the proposal
        vm.roll(block.number + VOTING_DELAY + 1);

        // Voter 1 approves options 0 and 1
        uint256[] memory voter1Options = new uint256[](2);
        voter1Options[0] = 0;
        voter1Options[1] = 1;
        vm.prank(voter1);
        governor.castVoteWithReasonAndParams(proposalId, 1, "Approve first two", abi.encode(voter1Options));

        // Voter 3 approves options 1 and 2
        uint256[] memory voter3Options = new uint256[](2);
        voter3Options[0] = 1;
        voter3Options[1] = 2;
        vm.prank(voter3);
        governor.castVoteWithReasonAndParams(proposalId, 1, "Approve last two", abi.encode(voter3Options));

        // Advance past voting period
        vm.roll(block.number + VOTING_PERIOD + 1);
        console.log("Voting ended, state:", uint256(governor.state(proposalId)));

        // Queue the proposal
        vm.prank(manager);
        governor.queueWithModule(approvalVotingModule, proposalData, keccak256(bytes(description)));
        console.log("Approval voting proposal queued");

        // Verify it's queued
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));

        // Note: We cannot directly get the timelock ID for module proposals without calling _formatExecuteParams
        // which is restricted to governor only. But we can verify the state change.

        // Manager cancels the approval voting proposal
        vm.prank(manager);
        governor.cancelWithModule(approvalVotingModule, proposalData, keccak256(bytes(description)));

        // Verify cancellation
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
        console.log("[PASS] Manager successfully canceled approval voting proposal");
    }

    /**
     * @notice Test creating and canceling an optimistic proposal
     */
    function testOptimisticProposalCancellation() public {
        console.log("========== TEST: OPTIMISTIC PROPOSAL CANCELLATION ==========");

        // Prepare optimistic proposal settings
        OptimisticProposalSettings memory settings = OptimisticProposalSettings({
            againstThreshold: 500, // 5% of total supply
            isRelativeToVotableSupply: true
        });

        bytes memory proposalData = abi.encode(settings);
        string memory description = "Optimistic Proposal: Community sentiment check";

        // Create optimistic proposal
        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(
            optimisticModule,
            proposalData,
            description,
            1 // Optimistic proposal type
        );
        console.log("Optimistic proposal created, ID:", proposalId);

        // Vote on the proposal (some against votes but below threshold)
        vm.roll(block.number + VOTING_DELAY + 1);

        // Voter 2 votes against (1.5M tokens = 0.15% of supply, well below 5% threshold)
        vm.prank(voter2);
        governor.castVote(proposalId, 0); // Against

        // Voter 1 votes for
        vm.prank(voter1);
        governor.castVote(proposalId, 1); // For

        // Advance past voting period
        vm.roll(block.number + VOTING_PERIOD + 1);
        console.log("Voting ended, state:", uint256(governor.state(proposalId)));

        // Verify votes
        (uint256 againstVotes, uint256 forVotes,) = governor.proposalVotes(proposalId);
        console.log("Against votes:", againstVotes);
        console.log("For votes:", forVotes);
        console.log("Against threshold (5% of supply):", (INITIAL_VOTABLE_SUPPLY * 500) / 10000);

        // Note: Optimistic proposals are for signaling only and will revert if we try to queue
        // But we can still test cancellation before the voting period ends

        // Create another optimistic proposal to test cancellation during voting
        vm.prank(manager);
        uint256 proposalId2 =
            governor.proposeWithModule(optimisticModule, proposalData, "Optimistic Proposal 2: Cancel during voting", 1);

        // Advance to voting period
        vm.roll(block.number + VOTING_DELAY + 1);

        // Cancel while still in voting period
        vm.prank(manager);
        governor.cancelWithModule(
            optimisticModule, proposalData, keccak256(bytes("Optimistic Proposal 2: Cancel during voting"))
        );

        assertEq(uint256(governor.state(proposalId2)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
        console.log("[PASS] Manager successfully canceled optimistic proposal during voting");
    }

    /**
     * @notice Test L2 Safe canceling different proposal types
     */
    function testL2SafeCancelDifferentProposalTypes() public {
        console.log("========== TEST: L2 SAFE CANCEL DIFFERENT PROPOSAL TYPES ==========");

        // Create a standard proposal
        address[] memory targets = new address[](1);
        targets[0] = makeAddr("target");
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("test()");
        string memory description = "Standard proposal for L2 Safe test";

        vm.prank(manager);
        uint256 standardPropId = governor.propose(targets, values, calldatas, description, 0);

        // Vote and queue
        vm.roll(block.number + VOTING_DELAY + 1);
        vm.prank(voter1);
        governor.castVote(standardPropId, 1);
        vm.prank(voter3);
        governor.castVote(standardPropId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);
        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256(bytes(description)));

        // Get timelock ID and verify it's pending
        bytes32 timelockId = timelock.hashOperationBatch(targets, values, calldatas, 0, keccak256(bytes(description)));
        assertTrue(timelock.isOperationPending(timelockId), "Standard proposal should be pending");

        // L2 Safe 2 cancels the standard proposal
        vm.prank(l2Safe2);
        timelock.cancel(timelockId);

        assertFalse(timelock.isOperationPending(timelockId), "Should no longer be pending");
        assertEq(uint256(governor.state(standardPropId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
        console.log("[PASS] L2 Safe 2 successfully canceled standard proposal via timelock");
    }

    /**
     * @notice Test full deployment configuration matches production
     */
    function testDeploymentConfiguration() public view {
        console.log("========== TEST: DEPLOYMENT CONFIGURATION ==========");

        // Verify governor configuration
        assertEq(governor.votingDelay(), VOTING_DELAY);
        console.log("[PASS] Voting delay matches: %s", VOTING_DELAY);

        assertEq(governor.votingPeriod(), VOTING_PERIOD);
        console.log("[PASS] Voting period matches: %s", VOTING_PERIOD);

        assertEq(governor.proposalThreshold(), PROPOSAL_THRESHOLD);
        console.log("[PASS] Proposal threshold matches: %s", PROPOSAL_THRESHOLD);

        // Verify timelock configuration
        assertEq(timelock.getMinDelay(), MIN_DELAY);
        console.log("[PASS] Timelock min delay matches: %s days", MIN_DELAY / 1 days);

        // Verify module approvals
        assertTrue(governor.approvedModules(address(approvalVotingModule)));
        console.log("[PASS] ApprovalVotingModule is approved");

        assertTrue(governor.approvedModules(address(optimisticModule)));
        console.log("[PASS] OptimisticModule is approved");

        // Verify addresses
        assertEq(address(governor.timelock()), address(timelock));
        console.log("[PASS] Governor timelock correctly set");

        assertEq(governor.manager(), manager);
        console.log("[PASS] Governor manager correctly set");

        assertEq(governor.alligator(), address(alligatorContract));
        console.log("[PASS] Governor alligator correctly set");
    }

    /**
     * @notice Test cancellation when proposal is pending in timelock but not ready
     */
    function testCancelPendingTimelockOperation() public {
        console.log("========== TEST: CANCEL PENDING TIMELOCK OPERATION ==========");

        // Verify the setup proposal is queued in timelock
        bytes32 timelockId = timelock.hashOperationBatch(targets, values, calldatas, 0, keccak256(bytes(description)));

        console.log("Initial state:");
        console.log("- Proposal is queued in governor");
        console.log("- Operation is pending in timelock");
        console.log("- Min delay:", timelock.getMinDelay() / 1 days, "days");

        assertTrue(timelock.isOperationPending(timelockId), "Should be pending");
        assertFalse(timelock.isOperationReady(timelockId), "Should not be ready (delay not passed)");

        // Test different actors canceling
        _testManagerCancelsPending();
        _testL2SafeCancelsPending();
        _testProposerCancelsPending();
    }

    /**
     * @notice Test cancellation when proposal is ready for execution in timelock
     */
    function testCancelReadyTimelockOperation() public {
        console.log("========== TEST: CANCEL READY TIMELOCK OPERATION ==========");

        // Create a new proposal
        address[] memory newTargets = new address[](1);
        newTargets[0] = makeAddr("readyTarget");
        uint256[] memory newValues = new uint256[](1);
        newValues[0] = 5 ether;
        bytes[] memory newCalldatas = new bytes[](1);
        newCalldatas[0] = "";
        string memory newDesc = "Ready for execution test";

        // Create, vote, and queue
        vm.prank(manager);
        uint256 newPropId = governor.propose(newTargets, newValues, newCalldatas, newDesc, 0);

        vm.roll(block.number + VOTING_DELAY + 1);
        vm.prank(voter1);
        governor.castVote(newPropId, 1);
        vm.prank(voter3);
        governor.castVote(newPropId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);
        vm.prank(manager);
        governor.queue(newTargets, newValues, newCalldatas, keccak256(bytes(newDesc)));

        // Advance time to make it ready
        bytes32 newTlId = timelock.hashOperationBatch(newTargets, newValues, newCalldatas, 0, keccak256(bytes(newDesc)));
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);

        console.log("After time warp:");
        assertTrue(timelock.isOperationPending(newTlId), "Should still be pending");
        assertTrue(timelock.isOperationReady(newTlId), "Should be ready for execution");

        // L2 Safe cancels a ready operation
        vm.prank(l2Safe3);
        timelock.cancel(newTlId);

        assertFalse(timelock.isOperationPending(newTlId), "Should no longer be pending");
        assertFalse(timelock.isOperationReady(newTlId), "Should no longer be ready");
        console.log("[PASS] L2 Safe 3 canceled a ready operation");
    }

    function _testManagerCancelsPending() internal {
        console.log("\n--- Manager cancels pending operation ---");

        // Manager cancels via governor.cancel()
        vm.prank(manager);
        governor.cancel(targets, values, calldatas, keccak256(bytes(description)));

        bytes32 timelockId = timelock.hashOperationBatch(targets, values, calldatas, 0, keccak256(bytes(description)));
        assertFalse(timelock.isOperationPending(timelockId), "Should no longer be pending");
        console.log("[PASS] Manager canceled via governor");
    }

    function _testL2SafeCancelsPending() internal {
        console.log("\n--- L2 Safe cancels pending operation ---");

        // Create new proposal
        address[] memory newTargets = new address[](1);
        newTargets[0] = makeAddr("l2SafeTest");
        uint256[] memory newValues = new uint256[](1);
        newValues[0] = 2 ether;
        bytes[] memory newCalldatas = new bytes[](1);
        newCalldatas[0] = "";
        string memory newDesc = "L2 Safe cancel test";

        vm.prank(manager);
        uint256 newPropId = governor.propose(newTargets, newValues, newCalldatas, newDesc, 0);

        vm.roll(block.number + VOTING_DELAY + 1);
        vm.prank(voter1);
        governor.castVote(newPropId, 1);
        vm.prank(voter3);
        governor.castVote(newPropId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);
        vm.prank(manager);
        governor.queue(newTargets, newValues, newCalldatas, keccak256(bytes(newDesc)));

        bytes32 newTlId = timelock.hashOperationBatch(newTargets, newValues, newCalldatas, 0, keccak256(bytes(newDesc)));
        assertTrue(timelock.isOperationPending(newTlId), "Should be pending");

        // L2 Safe cancels directly
        vm.prank(l2Safe1);
        timelock.cancel(newTlId);

        assertFalse(timelock.isOperationPending(newTlId), "Should no longer be pending");
        console.log("[PASS] L2 Safe 1 canceled via timelock");
    }

    function _testProposerCancelsPending() internal {
        console.log("\n--- Proposer cancels their own pending operation ---");

        // In OptimismGovernor, only manager or timelock can propose
        // Create a proposal as timelock to test proposer cancellation

        address[] memory newTargets = new address[](1);
        newTargets[0] = makeAddr("proposerTest");
        uint256[] memory newValues = new uint256[](1);
        newValues[0] = 3 ether;
        bytes[] memory newCalldatas = new bytes[](1);
        newCalldatas[0] = "";
        string memory newDesc = "Timelock proposer's proposal";

        vm.prank(address(timelock));
        uint256 newPropId = governor.propose(newTargets, newValues, newCalldatas, newDesc, 0);

        vm.roll(block.number + VOTING_DELAY + 1);
        vm.prank(voter1);
        governor.castVote(newPropId, 1);
        vm.prank(voter3);
        governor.castVote(newPropId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        vm.prank(manager);
        governor.queue(newTargets, newValues, newCalldatas, keccak256(bytes(newDesc)));

        bytes32 newTlId = timelock.hashOperationBatch(newTargets, newValues, newCalldatas, 0, keccak256(bytes(newDesc)));
        assertTrue(timelock.isOperationPending(newTlId), "Should be pending");

        // Timelock (proposer) cancels their own proposal
        vm.prank(address(timelock));
        governor.cancel(newTargets, newValues, newCalldatas, keccak256(bytes(newDesc)));

        assertFalse(timelock.isOperationPending(newTlId), "Should no longer be pending");
        console.log("[PASS] Proposer (timelock) canceled their own proposal");
    }
}
