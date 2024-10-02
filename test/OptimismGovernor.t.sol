// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOptimismGovernor} from "../src/interfaces/IOptimismGovernor.sol";
import {VotingModule} from "../src/modules/VotingModule.sol";
import {
    OptimisticModule_SocialSignalling as OptimisticModule,
    ProposalSettings as OptimisticProposalSettings,
    VoteType
} from "../src/modules/OptimisticModule.sol";
import {GovernanceToken as OptimismToken} from "../src/lib/OptimismToken.sol";
import {OptimismGovernorMock} from "./mocks/OptimismGovernorMock.sol";
import {ApprovalVotingModuleMock} from "./mocks/ApprovalVotingModuleMock.sol";
import {VotableSupplyOracle} from "../src/VotableSupplyOracle.sol";
import {ProposalTypesConfigurator} from "../src/ProposalTypesConfigurator.sol";
import {IGovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";
import {
    ApprovalVotingModule,
    ProposalOption,
    ProposalSettings,
    PassingCriteria
} from "../src/modules/ApprovalVotingModule.sol";

contract OptimismGovernorTest is Test {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description,
        uint8 proposalType
    );
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address indexed votingModule,
        bytes proposalData,
        uint256 startBlock,
        uint256 endBlock,
        string description,
        uint8 proposalType
    );
    event ProposalTypeUpdated(uint256 indexed proposalId, uint8 proposalType);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidProposalType(uint8 proposalType);
    error InvalidProposalId();

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address internal admin = makeAddr("admin");
    address internal manager = makeAddr("manager");
    string description = "a nice description";
    address voter = makeAddr("voter");
    address altVoter = makeAddr("altVoter");
    address altVoter2 = makeAddr("altVoter2");

    OptimismToken internal op = OptimismToken(0x4200000000000000000000000000000000000042);
    address internal governor;
    ApprovalVotingModuleMock internal module;

    address internal alligator = 0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9;
    address deployer = makeAddr("deployer");
    VotableSupplyOracle private votableSupplyOracle;
    ProposalTypesConfigurator private proposalTypesConfigurator;
    address optimisticModule = address(new OptimisticModule());

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function _preSetUp(address impl) public virtual {
        vm.etch(address(op), address(new OptimismToken()).code);

        address proxy = address(
            new TransparentUpgradeableProxy(
                impl, admin, abi.encodeCall(OptimismGovernorMock.initialize, (IVotesUpgradeable(address(op)), manager))
            )
        );

        module = new ApprovalVotingModuleMock();

        vm.startPrank(op.owner());
        op.mint(voter, 1e18);
        op.mint(altVoter, 1e20);
        op.mint(altVoter2, 1e18);
        vm.stopPrank();

        vm.prank(voter);
        op.delegate(voter);
        vm.prank(altVoter);
        op.delegate(altVoter);
        vm.prank(altVoter2);
        op.delegate(altVoter2);

        governor = proxy;

        vm.startPrank(deployer);
        votableSupplyOracle = new VotableSupplyOracle(address(this), op.totalSupply() * 30 / 100);
        proposalTypesConfigurator = new ProposalTypesConfigurator(IOptimismGovernor(address(governor)));
        vm.stopPrank();

        vm.startPrank(manager);
        proposalTypesConfigurator.setProposalType(0, 3_000, 5_000, "Default", "Default", address(0));
        proposalTypesConfigurator.setProposalType(1, 5_000, 7_000, "Alt", "Alt", address(0));
        vm.stopPrank();
    }

    function setUp() public virtual {
        address implementation = address(new OptimismGovernorMock());
        _preSetUp(implementation);

        vm.startPrank(manager);
        proposalTypesConfigurator.setProposalType(1, 0, 0, "Optimistic", "Optimistic", optimisticModule);
        _governorV6().setModuleApproval(optimisticModule, true);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function testPropose_withType() public virtual {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(manager);
        uint256 proposalId = _governorV6().propose(targets, values, calldatas, "Test", 1);

        assertEq(_governorV6().proposals(proposalId).proposalType, 1);
    }

    function testProposeWithModule_withType() public virtual {
        uint256 snapshot = block.number + _governorV6().votingDelay();
        uint256 deadline = snapshot + _governorV6().votingPeriod();
        bytes memory proposalData = _formatProposalData();
        uint256 proposalId =
            _governorV6().hashProposalWithModule(address(module), proposalData, keccak256(bytes(description)));

        vm.expectEmit();
        emit ProposalCreated(proposalId, manager, address(module), proposalData, snapshot, deadline, description, 1);
        vm.prank(manager);
        _governorV6().proposeWithModule(VotingModule(module), proposalData, description, 1);

        assertEq(_governorV6().proposals(proposalId).proposalType, 1);
        assertEq(_governorV6().proposalSnapshot(proposalId), snapshot);
        assertEq(_governorV6().proposalDeadline(proposalId), deadline);
        assertEq(uint8(_governorV6().state(proposalId)), uint8(IGovernorUpgradeable.ProposalState.Pending));
    }

    function testIncreaseWeightCast() public virtual {
        uint256 proposalId = 1;
        address account = address(444);
        uint256 votes = 10;
        uint256 accountVotes = 100;

        vm.startPrank(alligator);
        _governorV6().increaseWeightCast(proposalId, account, votes, accountVotes);
        assertEq(_governorV6().weightCast(proposalId, account), votes);

        _governorV6().increaseWeightCast(proposalId, account, votes, accountVotes);
        assertEq(_governorV6().weightCast(proposalId, account), votes * 2);

        vm.stopPrank();
    }

    function testHasVoted_fromAlligator() public virtual {
        uint256 proposalId = 1;
        address account = address(444);
        uint256 votes = 10;
        uint256 accountVotes = 100;

        vm.prank(alligator);
        _governorV6().increaseWeightCast(proposalId, account, votes, accountVotes);

        assertTrue(_governorV6().hasVoted(proposalId, account));
    }

    function testCastVoteFromAlligator() public virtual {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(manager);
        uint256 proposalId = _governorV6().propose(targets, values, calldatas, "Test", 1);

        uint256 snapshot = block.number + _governorV6().votingDelay();
        vm.roll(snapshot + 1);

        vm.startPrank(alligator);
        _governorV6().castVoteFromAlligator(proposalId, voter, 0, "test", 10, "");

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = _governorV6().proposalVotes(proposalId);
        // standard votes are added only the first time voter casts the vote
        assertEq(againstVotes, 10 + op.getVotes(voter));
        assertEq(forVotes, 0);
        assertEq(abstainVotes, 0);

        _governorV6().castVoteFromAlligator(proposalId, voter, 1, "test", 10, "");

        (againstVotes, forVotes, abstainVotes) = _governorV6().proposalVotes(proposalId);
        assertEq(againstVotes, 10 + op.getVotes(voter));
        assertEq(forVotes, 10);
        assertEq(abstainVotes, 0);

        _governorV6().castVoteFromAlligator(proposalId, voter, 2, "test", 10, "");

        (againstVotes, forVotes, abstainVotes) = _governorV6().proposalVotes(proposalId);
        assertEq(againstVotes, 10 + op.getVotes(voter));
        assertEq(forVotes, 10);
        assertEq(abstainVotes, 10);

        vm.stopPrank();
    }

    function testVotableSupply() public virtual {
        uint256 supply = _governorV6().votableSupply();
        assertEq(supply, op.totalSupply() * 30 / 100);
    }

    function testQuorum() public virtual {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(manager);
        uint256 proposalId = _governorV6().propose(targets, values, calldatas, "Test");

        uint256 supply = _governorV6().votableSupply();
        uint256 quorum = _governorV6().quorum(proposalId);
        assertEq(quorum, supply * 3 / 10);

        // Reset votable supply
        votableSupplyOracle._updateVotableSupplyAt(0, 0);

        vm.prank(manager);
        proposalId = _governorV6().propose(targets, values, calldatas, "Test2");

        vm.roll(block.number + 1);

        // Assert it fallbacks to generic supply
        quorum = _governorV6().quorum(proposalId);
        assertEq(quorum, op.totalSupply() * _governorV6().quorumNumerator() / _governorV6().quorumDenominator());
    }

    function testQuorumReached() public virtual {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(manager);
        uint256 proposalId = _governorV6().propose(targets, values, calldatas, "Test");

        uint256 snapshot = block.number + _governorV6().votingDelay();
        vm.roll(snapshot + 1);

        assertFalse(_governorV6().quorumReached(proposalId));

        vm.prank(voter);
        _governorV6().castVote(proposalId, 1);

        assertFalse(_governorV6().quorumReached(proposalId));

        vm.prank(altVoter);
        _governorV6().castVote(proposalId, 1);

        assertTrue(_governorV6().quorumReached(proposalId));
    }

    function testVoteSucceeded() public virtual {
        vm.prank(manager);
        proposalTypesConfigurator.setProposalType(0, 3_000, 9_910, "Default", "Default", address(0));

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(manager);
        uint256 proposalId = _governorV6().propose(targets, values, calldatas, "Test");

        uint256 snapshot = block.number + _governorV6().votingDelay();
        vm.roll(snapshot + 1);

        vm.prank(altVoter);
        _governorV6().castVote(proposalId, 1);
        vm.prank(voter);
        _governorV6().castVote(proposalId, 0);

        assertFalse(_governorV6().voteSucceeded(proposalId));

        vm.prank(manager);
        proposalId = _governorV6().propose(targets, values, calldatas, "Test2");

        snapshot = block.number + _governorV6().votingDelay();
        vm.roll(snapshot + 1);

        vm.prank(altVoter);
        _governorV6().castVote(proposalId, 1);

        assertTrue(_governorV6().voteSucceeded(proposalId));
    }

    function testEditProposalType() public virtual {
        vm.startPrank(manager);
        proposalTypesConfigurator.setProposalType(0, 3_000, 9_910, "Default", "Default", address(0));

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        uint256 proposalId = _governorV6().propose(targets, values, calldatas, "Test");
        assertEq(_governorV6().proposals(proposalId).proposalType, 0);

        vm.expectEmit();
        emit ProposalTypeUpdated(proposalId, 1);
        _governorV6().editProposalType(proposalId, 1);

        assertEq(_governorV6().proposals(proposalId).proposalType, 1);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                               OPTIMISTIC
    //////////////////////////////////////////////////////////////*/

    function _optimisticAssertions(uint256 proposalId, uint256 snapshot, uint256 deadline) public virtual {
        assertEq(_governorV6().proposals(proposalId).proposalType, 1);
        assertEq(_governorV6().proposalSnapshot(proposalId), snapshot);
        assertEq(_governorV6().proposalDeadline(proposalId), deadline);
        assertEq(uint8(_governorV6().state(proposalId)), uint8(IGovernorUpgradeable.ProposalState.Pending));
    }

    function testOptimisticModuleVote_absolute_noVotes() public virtual {
        uint256 snapshot = block.number + _governorV6().votingDelay();
        uint256 deadline = snapshot + _governorV6().votingPeriod();
        bytes memory proposalData = abi.encode(OptimisticProposalSettings(1e18, false));
        uint256 proposalId =
            _governorV6().hashProposalWithModule(optimisticModule, proposalData, keccak256(bytes(description)));

        vm.expectEmit();
        emit ProposalCreated(proposalId, manager, optimisticModule, proposalData, snapshot, deadline, description, 1);
        vm.prank(manager);
        _governorV6().proposeWithModule(VotingModule(optimisticModule), proposalData, description, 1);

        _optimisticAssertions(proposalId, snapshot, deadline);

        vm.roll(deadline + 1);
        assertTrue(_governorV6().voteSucceeded(proposalId));
    }

    function testOptimisticModuleVote_relative_noVotes() public virtual {
        uint256 snapshot = block.number + _governorV6().votingDelay();
        uint256 deadline = snapshot + _governorV6().votingPeriod();
        bytes memory proposalData = abi.encode(OptimisticProposalSettings(1_000, true));
        uint256 proposalId =
            _governorV6().hashProposalWithModule(optimisticModule, proposalData, keccak256(bytes(description)));

        vm.prank(manager);
        _governorV6().proposeWithModule(VotingModule(optimisticModule), proposalData, description, 1);

        _optimisticAssertions(proposalId, snapshot, deadline);

        vm.roll(deadline + 1);
        assertTrue(_governorV6().voteSucceeded(proposalId));
    }

    function testOptimisticModuleVote_absolute_withVotes_fails() public virtual {
        uint256 snapshot = block.number + _governorV6().votingDelay();
        uint256 deadline = snapshot + _governorV6().votingPeriod();
        bytes memory proposalData = abi.encode(OptimisticProposalSettings(1e18, false));
        uint256 proposalId =
            _governorV6().hashProposalWithModule(optimisticModule, proposalData, keccak256(bytes(description)));

        vm.prank(manager);
        _governorV6().proposeWithModule(VotingModule(optimisticModule), proposalData, description, 1);

        _optimisticAssertions(proposalId, snapshot, deadline);

        vm.roll(snapshot + 1);

        vm.prank(voter); // 1e18 votes AGAINST
        _governorV6().castVote(proposalId, uint8(VoteType.Against));

        vm.prank(altVoter); // 1e20 votes FOR
        _governorV6().castVote(proposalId, uint8(VoteType.For));

        vm.roll(deadline + 1);
        assertFalse(_governorV6().voteSucceeded(proposalId));
    }

    function testOptimisticModuleVote_absolute_withVotes_succeeds() public virtual {
        uint256 snapshot = block.number + _governorV6().votingDelay();
        uint256 deadline = snapshot + _governorV6().votingPeriod();
        bytes memory proposalData = abi.encode(OptimisticProposalSettings(1e18 + 1, false));
        uint256 proposalId =
            _governorV6().hashProposalWithModule(optimisticModule, proposalData, keccak256(bytes(description)));

        vm.prank(manager);
        _governorV6().proposeWithModule(VotingModule(optimisticModule), proposalData, description, 1);

        _optimisticAssertions(proposalId, snapshot, deadline);

        vm.roll(snapshot + 1);

        vm.prank(voter); // 1e18 votes AGAINST
        _governorV6().castVote(proposalId, uint8(VoteType.Against));

        vm.roll(deadline + 1);
        assertTrue(_governorV6().voteSucceeded(proposalId));
    }

    function testOptimisticModuleVote_relative_withVotes_fails() public virtual {
        uint256 snapshot = block.number + _governorV6().votingDelay();
        uint256 deadline = snapshot + _governorV6().votingPeriod();
        bytes memory proposalData = abi.encode(OptimisticProposalSettings(100, /* 1% of supply - 102e18 */ true));
        uint256 proposalId =
            _governorV6().hashProposalWithModule(optimisticModule, proposalData, keccak256(bytes(description)));

        vm.prank(manager);
        _governorV6().proposeWithModule(VotingModule(optimisticModule), proposalData, description, 1);

        _optimisticAssertions(proposalId, snapshot, deadline);

        vm.roll(snapshot + 1);

        vm.prank(voter); // 1e18 votes AGAINST
        _governorV6().castVote(proposalId, uint8(VoteType.Against));

        vm.prank(altVoter2); // 1e18 votes AGAINST
        _governorV6().castVote(proposalId, uint8(VoteType.Against));

        vm.prank(altVoter); // 1e20 votes FOR
        _governorV6().castVote(proposalId, uint8(VoteType.For));

        vm.roll(deadline + 1);
        assertFalse(_governorV6().voteSucceeded(proposalId));
    }

    function testOptimisticModuleVote_relative_withVotes_succeeds() public virtual {
        uint256 snapshot = block.number + _governorV6().votingDelay();
        uint256 deadline = snapshot + _governorV6().votingPeriod();
        bytes memory proposalData =
            abi.encode(OptimisticProposalSettings(327, /* 3.27% of votable supply ~ 1e18 */ true));
        uint256 proposalId =
            _governorV6().hashProposalWithModule(optimisticModule, proposalData, keccak256(bytes(description)));

        vm.prank(manager);
        _governorV6().proposeWithModule(VotingModule(optimisticModule), proposalData, description, 1);

        _optimisticAssertions(proposalId, snapshot, deadline);

        vm.roll(snapshot + 1);

        vm.prank(voter); // 1e18 votes AGAINST
        _governorV6().castVote(proposalId, uint8(VoteType.Against));

        vm.roll(deadline + 1);
        assertTrue(_governorV6().voteSucceeded(proposalId));
    }

    function testExecuteWithOptimisticModule() public virtual {
        uint256 snapshot = block.number + _governorV6().votingDelay();
        uint256 deadline = snapshot + _governorV6().votingPeriod();
        bytes memory proposalData = abi.encode(OptimisticProposalSettings(1e18, false));
        uint256 proposalId =
            _governorV6().hashProposalWithModule(optimisticModule, proposalData, keccak256(bytes(description)));

        vm.prank(manager);
        _governorV6().proposeWithModule(VotingModule(optimisticModule), proposalData, description, 1);

        vm.roll(deadline + 1);

        vm.prank(manager);
        _governorV6().executeWithModule(VotingModule(optimisticModule), proposalData, keccak256(bytes(description)));

        assertEq(uint8(_governorV6().state(proposalId)), uint8(IGovernorUpgradeable.ProposalState.Executed));
    }

    /*//////////////////////////////////////////////////////////////
                                REVERTS
    //////////////////////////////////////////////////////////////*/

    function testRevert_Propose_withType_InvalidProposalType() public virtual {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);
        uint8 invalidPropType = 2;

        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(InvalidProposalType.selector, invalidPropType));
        _governorV6().propose(targets, values, calldatas, "Test", invalidPropType);
    }

    function testRevert_ProposeWithModule_withType_InvalidProposalType() public virtual {
        bytes memory proposalData = _formatProposalData();
        uint8 invalidPropType = 2;

        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(InvalidProposalType.selector, invalidPropType));
        _governorV6().proposeWithModule(VotingModule(module), proposalData, description, invalidPropType);
    }

    function testRevert_increaseWeightCast() public virtual {
        uint256 proposalId = 1;
        address account = address(444);
        uint256 accountVotes = 100;

        vm.startPrank(alligator);
        vm.expectRevert("Governor: total weight exceeded");
        _governorV6().increaseWeightCast(proposalId, account, 101, accountVotes);

        _governorV6().increaseWeightCast(proposalId, account, 10, accountVotes);
        vm.expectRevert("Governor: total weight exceeded");
        _governorV6().increaseWeightCast(proposalId, account, 91, accountVotes);

        vm.stopPrank();
    }

    function testRevert_editProposalType_onlyManager() public virtual {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(manager);
        uint256 proposalId = _governorV6().propose(targets, values, calldatas, "Test");

        vm.expectRevert("Only the manager can call this function");
        _governorV6().editProposalType(proposalId, 1);
    }

    function testRevert_editProposalType_InvalidProposalId() public virtual {
        bytes memory proposalData = _formatProposalData();
        uint256 proposalId =
            _governorV6().hashProposalWithModule(address(module), proposalData, keccak256(bytes(description)));

        vm.prank(manager);
        vm.expectRevert(InvalidProposalId.selector);
        _governorV6().editProposalType(proposalId, 1);
    }

    function testRevert_editProposalType_InvalidProposalType() public virtual {
        vm.startPrank(manager);

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        uint256 proposalId = _governorV6().propose(targets, values, calldatas, "Test");
        assertEq(_governorV6().proposals(proposalId).proposalType, 0);

        vm.expectRevert(abi.encodeWithSelector(InvalidProposalType.selector, 2));
        _governorV6().editProposalType(proposalId, 2);

        vm.stopPrank();
    }

    function testRevert_ProposeWithOptimisticModule_notOptimisticProposalType() public virtual {
        bytes memory proposalData = abi.encode(OptimisticProposalSettings(0, false));

        vm.prank(manager);
        vm.expectRevert(OptimisticModule.NotOptimisticProposalType.selector);
        _governorV6().proposeWithModule(VotingModule(optimisticModule), proposalData, description, 0);
    }

    function testRevert_ProposeWithOptimisticModule_zeroThreshold() public virtual {
        bytes memory proposalData = abi.encode(OptimisticProposalSettings(0, false));

        vm.prank(manager);
        vm.expectRevert(VotingModule.InvalidParams.selector);
        _governorV6().proposeWithModule(VotingModule(optimisticModule), proposalData, description, 1);
    }

    function testRevert_ProposeWithOptimisticModule_thresholdTooHigh() public virtual {
        bytes memory proposalData = abi.encode(OptimisticProposalSettings(10_001, true));

        vm.prank(manager);
        vm.expectRevert(VotingModule.InvalidParams.selector);
        _governorV6().proposeWithModule(VotingModule(optimisticModule), proposalData, description, 1);
    }

    /*//////////////////////////////////////////////////////////////
                                OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function testProposeWithModule() public virtual {
        uint256 snapshot = block.number + _governorV6().votingDelay();
        uint256 deadline = snapshot + _governorV6().votingPeriod();
        bytes memory proposalData = _formatProposalData();
        uint256 proposalId =
            _governorV6().hashProposalWithModule(address(module), proposalData, keccak256(bytes(description)));

        vm.expectEmit();
        emit ProposalCreated(proposalId, manager, address(module), proposalData, snapshot, deadline, description, 0);
        vm.prank(manager);
        _governorV6().proposeWithModule(VotingModule(module), proposalData, description);

        assertEq(_governorV6().proposals(proposalId).proposalType, 0);
        assertEq(_governorV6().proposalSnapshot(proposalId), snapshot);
        assertEq(_governorV6().proposalDeadline(proposalId), deadline);
        assertEq(uint8(_governorV6().state(proposalId)), uint8(IGovernorUpgradeable.ProposalState.Pending));
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function executeCallback() public payable virtual {
        revert("Executor shouldn't have called this function");
    }

    function _formatProposalData() public virtual returns (bytes memory proposalData) {
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");

        address[] memory targets1 = new address[](1);
        uint256[] memory values1 = new uint256[](1);
        bytes[] memory calldatas1 = new bytes[](1);
        // Call executeCallback and send 0.01 ether to receiver1
        targets1[0] = receiver1;
        values1[0] = 0.01 ether;
        calldatas1[0] = abi.encodeWithSelector(this.executeCallback.selector);

        address[] memory targets2 = new address[](2);
        uint256[] memory values2 = new uint256[](2);
        bytes[] memory calldatas2 = new bytes[](2);
        // Send 0.01 ether to receiver2
        targets2[0] = receiver2;
        values2[0] = 0.01 ether;
        // Transfer 100 OP tokens to receiver2
        targets2[1] = address(op);
        calldatas2[1] = abi.encodeCall(IERC20.transfer, (receiver2, 100));

        ProposalOption[] memory options = new ProposalOption[](2);
        options[0] = ProposalOption(0, targets1, values1, calldatas1, "option 1");
        options[1] = ProposalOption(100, targets2, values2, calldatas2, "option 2");
        ProposalSettings memory settings = ProposalSettings({
            maxApprovals: 1,
            criteria: uint8(PassingCriteria.TopChoices),
            criteriaValue: 1,
            budgetToken: address(0),
            budgetAmount: 1 ether
        });

        return abi.encode(options, settings);
    }

    function _governorV6() private view returns (OptimismGovernorMock) {
        return OptimismGovernorMock(payable(governor));
    }

    function _quorum(uint256, uint256 proposalId) internal view returns (uint256) {
        return _governorV6().quorum(proposalId);
    }
}
