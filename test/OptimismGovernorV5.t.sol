// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UpgradeScripts} from "upgrade-scripts/UpgradeScripts.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OptimismGovernorV2} from "../src/OptimismGovernorV2.sol";
import {VotingModule} from "../src/modules/VotingModule.sol";
import {
    ApprovalVotingModule,
    ProposalOption,
    ProposalSettings,
    PassingCriteria
} from "../src/modules/ApprovalVotingModule.sol";
import {GovernanceToken as OptimismToken} from "../src/lib/OptimismToken.sol";
import {OptimismGovernorV5Mock} from "./mocks/OptimismGovernorV5Mock.sol";
import {OptimismGovernorV4UpgradeMock} from "./mocks/OptimismGovernorV4UpgradeMock.sol";
import {OptimismGovernorV5UpgradeMock} from "./mocks/OptimismGovernorV5UpgradeMock.sol";
import {OptimismGovernorV3Test} from "./OptimismGovernorV3.t.sol";

enum ProposalState {
    Pending,
    Active,
    Canceled,
    Defeated,
    Succeeded,
    Queued,
    Expired,
    Executed
}

enum VoteType {
    For,
    Abstain
}

contract OptimismGovernorV5Test is Test, UpgradeScripts, OptimismGovernorV3Test {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address votingModule,
        bytes proposalData,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );
    event ProposalCanceled(uint256 proposalId);
    event ProposalExecuted(uint256 proposalId);
    event VoteCastWithParams(
        address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason, bytes params
    );

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    OptimismGovernorV5Mock private governor;
    ApprovalVotingModule private module;
    string description = "a nice description";
    address voter = makeAddr("voter");

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUpUpgradeScripts() internal override {
        UPGRADE_SCRIPTS_BYPASS = true;
        UPGRADE_SCRIPTS_BYPASS_SAFETY = true; // disable to run upgrade checks
    }

    function setUp() public override {
        op = new OptimismToken();
        module = new ApprovalVotingModule();
        OptimismGovernorV5Mock implementation = new OptimismGovernorV5Mock();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            admin,
            abi.encodeCall(OptimismGovernorV2.initialize, (IVotesUpgradeable(address(op)), manager))
        );

        vm.prank(op.owner());
        op.mint(voter, 1e18);
        op.mint(address(this), 1e20);
        vm.prank(voter);
        op.delegate(voter);

        governor = OptimismGovernorV5Mock(payable(proxy));
        _setUp(payable(proxy));
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function testUpgrade() public {
        address implementationV4 = setUpContract("OptimismGovernorV4UpgradeMock");
        address implementationV5 = setUpContract("OptimismGovernorV5UpgradeMock");
        upgradeSafetyChecks("OptimismGovernorV5UpgradeMock", implementationV4, implementationV5);
    }

    function testProposeWithModule() public {
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        bytes memory proposalData = _formatProposalData();
        uint256 proposalId =
            governor.hashProposalWithModule(address(module), proposalData, keccak256(bytes(description)));

        vm.expectEmit(false, false, false, true);
        emit ProposalCreated(proposalId, manager, address(module), proposalData, snapshot, deadline, description);
        vm.prank(manager);
        governor.proposeWithModule(VotingModule(module), proposalData, description);

        assertEq(governor.proposalSnapshot(proposalId), snapshot);
        assertEq(governor.proposalDeadline(proposalId), deadline);
        assertEq(uint8(governor.state(proposalId)), uint8(ProposalState.Pending));
    }

    function testCancelWithModule() public {
        bytes memory proposalData = _formatProposalData();

        vm.startPrank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description);

        vm.expectEmit(false, false, false, true);
        emit ProposalCanceled(proposalId);
        governor.cancelWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        vm.stopPrank();

        assertEq(uint8(governor.state(proposalId)), uint8(ProposalState.Canceled));
    }

    function testCastVoteWithModule() public {
        bytes memory proposalData = _formatProposalData();
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 weight = op.getVotes(voter);
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description);

        vm.roll(snapshot + 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(voter);
        vm.expectEmit(true, false, false, true);
        emit VoteCastWithParams(voter, proposalId, uint8(VoteType.For), weight, reason, params);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);
    }

    function testExecuteWithModule() public {
        bytes memory proposalData = _formatProposalData();
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description);

        vm.roll(snapshot + 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        vm.roll(deadline + 1);

        vm.prank(manager);
        vm.expectEmit(false, false, false, true);
        emit ProposalExecuted(proposalId);
        governor.executeWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        assertEq(uint8(governor.state(proposalId)), uint8(ProposalState.Executed));
    }

    function testHasVoted() public {
        bytes memory proposalData = _formatProposalData();
        uint256 snapshot = block.number + governor.votingDelay();
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description);

        vm.roll(snapshot + 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        assertTrue(governor.hasVoted(proposalId, voter));
        assertFalse(governor.hasVoted(proposalId, address(1)));
    }

    function testQuorumReachedAndVoteSucceeded() public {
        bytes memory proposalData = _formatProposalData();
        uint256 snapshot = block.number + governor.votingDelay();
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description);

        vm.roll(snapshot + 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        assertTrue(governor.quorum(snapshot) != 0);
        assertTrue(governor.quorumReached(proposalId));
        assertTrue(governor.voteSucceeded(proposalId));
    }

    /*//////////////////////////////////////////////////////////////
                                REVERTS
    //////////////////////////////////////////////////////////////*/

    function testRevert_proposeWithModule_onlyManager() public {
        bytes memory proposalData = _formatProposalData();

        vm.expectRevert("Only the manager can call this function");
        governor.proposeWithModule(VotingModule(module), proposalData, "");
    }

    function testRevert_proposeWithModule_proposalAlreadyCreated() public {
        bytes memory proposalData = _formatProposalData();

        vm.startPrank(manager);
        governor.proposeWithModule(VotingModule(module), proposalData, description);

        vm.expectRevert("Governor: proposal already exists");
        governor.proposeWithModule(VotingModule(module), proposalData, description);
        vm.stopPrank();
    }

    function testRevert_cancelWithModule_proposalNotActive() public {
        bytes memory proposalData = _formatProposalData();

        vm.startPrank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description);
        governor.cancelWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));

        vm.expectRevert("Governor: proposal not active");
        governor.cancelWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        vm.stopPrank();

        assertEq(uint8(governor.state(proposalId)), uint8(ProposalState.Canceled));
    }

    function testRevert_castVoteWithModule_voteNotActive() public {
        bytes memory proposalData = _formatProposalData();
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(voter);
        vm.expectRevert("Governor: vote not currently active");
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);
    }

    function testRevert_executeWithModule_proposalNotSuccessful() public {
        bytes memory proposalData = _formatProposalData();
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description);

        vm.roll(deadline + 1);

        assertEq(uint8(governor.state(proposalId)), uint8(ProposalState.Defeated));

        vm.prank(manager);
        vm.expectRevert("Governor: proposal not successful");
        governor.executeWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _formatProposalData() public returns (bytes memory proposalData) {
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
        options[0] = ProposalOption(targets1, values1, calldatas1, "option 1");
        options[1] = ProposalOption(targets2, values2, calldatas2, "option 2");
        ProposalSettings memory settings = ProposalSettings({
            maxApprovals: 1,
            criteria: uint8(PassingCriteria.TopChoices),
            criteriaValue: 1,
            budgetToken: address(0),
            budgetAmount: 1 ether
        });

        return abi.encode(options, settings);
    }
}
