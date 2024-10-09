// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UpgradeScripts} from "upgrade-scripts/UpgradeScripts.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VotingModule} from "../src/modules/VotingModule.sol";
import {
    ApprovalVotingModule,
    ProposalOption,
    ProposalSettings,
    PassingCriteria
} from "../src/modules/ApprovalVotingModule.sol";
import {GovernanceToken as OptimismToken} from "../src/lib/OptimismToken.sol";
import {OptimismGovernorV5Mock} from "./mocks/OptimismGovernorV5Mock.sol";
import {OptimismGovernorV5UpgradeMock} from "./mocks/OptimismGovernorV5UpgradeMock.sol";
import {ApprovalVotingModuleMock} from "./mocks/ApprovalVotingModuleMock.sol";
import {IGovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";

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
    Against,
    For,
    Abstain
}

contract OptimismGovernorV5Test is Test, UpgradeScripts {
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

    address internal admin = makeAddr("admin");
    address internal manager = makeAddr("manager");
    string description = "a nice description";
    address voter = makeAddr("voter");
    address altVoter = makeAddr("altVoter");
    address altVoter2 = makeAddr("altVoter2");

    OptimismToken internal op = OptimismToken(0x4200000000000000000000000000000000000042);
    address internal governor;
    ApprovalVotingModuleMock internal module;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUpUpgradeScripts() internal override {
        UPGRADE_SCRIPTS_BYPASS = true;
        UPGRADE_SCRIPTS_BYPASS_SAFETY = true; // disable to run upgrade checks
    }

    function _preSetUp(address impl) public virtual {
        vm.etch(address(op), address(new OptimismToken()).code);

        address proxy = address(
            new TransparentUpgradeableProxy(
                impl,
                admin,
                abi.encodeCall(OptimismGovernorV5Mock.initialize, (IVotesUpgradeable(address(op)), manager))
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

        vm.prank(manager);
        _governorV5().setModuleApproval(address(module), true);
    }

    function setUp() public virtual {
        address implementation = address(new OptimismGovernorV5Mock());
        _preSetUp(implementation);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function testUpdateSettings() public virtual {
        vm.startPrank(manager);
        _governorV5().setVotingDelay(7);
        _governorV5().setVotingPeriod(14);
        _governorV5().setProposalThreshold(2);
        vm.stopPrank();

        assertEq(_governorV5().votingDelay(), 7);
        assertEq(_governorV5().votingPeriod(), 14);
        assertEq(_governorV5().proposalThreshold(), 2);

        vm.expectRevert("Only the manager can call this function");
        _governorV5().setVotingDelay(70);
        vm.expectRevert("Only the manager can call this function");
        _governorV5().setVotingPeriod(140);
        vm.expectRevert("Only the manager can call this function");
        _governorV5().setProposalThreshold(20);
    }

    function testPropose() public virtual {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(manager);
        uint256 proposalId = _governorV5().propose(targets, values, calldatas, "Test");

        uint256 deadline = _governorV5().proposalDeadline(proposalId);
        vm.prank(manager);
        _governorV5().setProposalDeadline(proposalId, uint64(deadline + 1 days));

        assertEq(_governorV5().proposalDeadline(proposalId), deadline + 1 days);

        vm.expectRevert("Only the manager can call this function");
        _governorV5().propose(targets, values, calldatas, "From someone else");
    }

    function testExecute() public virtual {
        vm.prank(op.owner());
        op.mint(address(this), 1e30);
        op.delegate(address(this));
        // vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.startPrank(manager);
        _governorV5().setVotingDelay(0);
        _governorV5().setVotingPeriod(14);
        _governorV5().updateQuorumNumerator(0);
        uint256 proposalId = _governorV5().propose(targets, values, calldatas, "Test");
        vm.stopPrank();

        vm.roll(block.number + 1);
        _governorV5().castVote(proposalId, 1);

        vm.roll(block.number + 14);

        vm.expectRevert("Only the manager can call this function");
        _governorV5().execute(targets, values, calldatas, keccak256("Test"));

        vm.prank(manager);
        _governorV5().execute(targets, values, calldatas, keccak256("Test"));

        assertEq(uint256(_governorV5().state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Executed));
    }

    function testCancel() public virtual {
        vm.prank(op.owner());
        op.mint(address(this), 1000);
        op.delegate(address(this));
        // vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.startPrank(manager);
        _governorV5().setVotingDelay(0);
        _governorV5().setVotingPeriod(14);
        _governorV5().updateQuorumNumerator(0);
        uint256 proposalId = _governorV5().propose(targets, values, calldatas, "Test");
        vm.stopPrank();

        vm.expectRevert("Only the manager can call this function");
        _governorV5().cancel(targets, values, calldatas, keccak256("Test"));

        vm.prank(manager);
        _governorV5().cancel(targets, values, calldatas, keccak256("Test"));

        assertEq(uint256(_governorV5().state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
    }

    function executeCallback() public payable virtual {
        revert("Executor shouldn't have called this function");
    }

    function testSetModuleApproval() public virtual {
        address module_ = makeAddr("module");

        assertEq(_governorV5().approvedModules(address(module_)), false);

        vm.startPrank(manager);
        _governorV5().setModuleApproval(address(module_), true);
        assertEq(_governorV5().approvedModules(address(module_)), true);

        _governorV5().setModuleApproval(address(module_), false);
        assertEq(_governorV5().approvedModules(address(module_)), false);
        vm.stopPrank();
    }

    function testProposeWithModule() public virtual {
        uint256 snapshot = block.number + _governorV5().votingDelay();
        uint256 deadline = snapshot + _governorV5().votingPeriod();
        bytes memory proposalData = _formatProposalData();
        uint256 proposalId =
            _governorV5().hashProposalWithModule(address(module), proposalData, keccak256(bytes(description)));

        vm.expectEmit();
        emit ProposalCreated(proposalId, manager, address(module), proposalData, snapshot, deadline, description);
        vm.prank(manager);
        _governorV5().proposeWithModule(VotingModule(module), proposalData, description);

        assertEq(_governorV5().proposalSnapshot(proposalId), snapshot);
        assertEq(_governorV5().proposalDeadline(proposalId), deadline);
        assertEq(uint8(_governorV5().state(proposalId)), uint8(ProposalState.Pending));
    }

    function testCancelWithModule() public virtual {
        bytes memory proposalData = _formatProposalData();

        vm.startPrank(manager);
        uint256 proposalId = _governorV5().proposeWithModule(VotingModule(module), proposalData, description);

        vm.expectEmit(false, false, false, true);
        emit ProposalCanceled(proposalId);
        _governorV5().cancelWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        vm.stopPrank();

        assertEq(uint8(_governorV5().state(proposalId)), uint8(ProposalState.Canceled));
    }

    function testCastVoteWithModule() public virtual {
        bytes memory proposalData = _formatProposalData();
        uint256 snapshot = block.number + _governorV5().votingDelay();
        uint256 weight = op.getVotes(voter);
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = _governorV5().proposeWithModule(VotingModule(module), proposalData, description);

        vm.roll(snapshot + 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(voter);
        vm.expectEmit(true, false, false, true);
        emit VoteCastWithParams(voter, proposalId, uint8(VoteType.For), weight, reason, params);
        _governorV5().castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        weight = op.getVotes(altVoter);
        vm.prank(altVoter);
        vm.expectEmit(true, false, false, true);
        emit VoteCastWithParams(altVoter, proposalId, uint8(VoteType.Against), weight, reason, params);
        _governorV5().castVoteWithReasonAndParams(proposalId, uint8(VoteType.Against), reason, params);

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = _governorV5().proposalVotes(proposalId);

        assertEq(againstVotes, 1e20);
        assertEq(forVotes, 1e18);
        assertEq(abstainVotes, 0);
        assertFalse(_governorV5().voteSucceeded(proposalId));
        assertEq(module._proposals(proposalId).optionVotes[0], 1e18);
        assertEq(module._proposals(proposalId).optionVotes[1], 0);
        assertTrue(_governorV5().hasVoted(proposalId, voter));
        assertEq(module.getAccountTotalVotes(proposalId, voter), optionVotes.length);
        assertTrue(_governorV5().hasVoted(proposalId, altVoter));
        assertEq(module.getAccountTotalVotes(proposalId, altVoter), 0);
    }

    function testExecuteWithModule() public virtual {
        bytes memory proposalData = _formatProposalData();
        uint256 snapshot = block.number + _governorV5().votingDelay();
        uint256 deadline = snapshot + _governorV5().votingPeriod();
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = _governorV5().proposeWithModule(VotingModule(module), proposalData, description);

        vm.roll(snapshot + 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(altVoter);
        _governorV5().castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        vm.roll(deadline + 1);

        vm.prank(manager);
        vm.expectEmit(false, false, false, true);
        emit ProposalExecuted(proposalId);
        _governorV5().executeWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        assertEq(uint8(_governorV5().state(proposalId)), uint8(ProposalState.Executed));
    }

    function testHasVoted() public virtual {
        bytes memory proposalData = _formatProposalData();
        uint256 snapshot = block.number + _governorV5().votingDelay();
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = _governorV5().proposeWithModule(VotingModule(module), proposalData, description);

        vm.roll(snapshot + 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(voter);
        _governorV5().castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        assertTrue(_governorV5().hasVoted(proposalId, voter));
        assertFalse(_governorV5().hasVoted(proposalId, address(1)));
    }

    function testQuorumReachedAndVoteSucceeded() public virtual {
        bytes memory proposalData = _formatProposalData();
        uint256 snapshot = block.number + _governorV5().votingDelay();
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = _governorV5().proposeWithModule(VotingModule(module), proposalData, description);

        vm.roll(snapshot + 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(altVoter);
        _governorV5().castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        assertTrue(_quorum(snapshot, proposalId) != 0);
        assertTrue(_governorV5().quorumReached(proposalId));
        assertTrue(_governorV5().voteSucceeded(proposalId));
    }

    function testVoteNotSucceeded() public virtual {
        bytes memory proposalData = _formatProposalData();
        uint256 snapshot = block.number + _governorV5().votingDelay();
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = _governorV5().proposeWithModule(VotingModule(module), proposalData, description);

        vm.roll(snapshot + 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(voter);
        _governorV5().castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        vm.prank(altVoter);
        _governorV5().castVoteWithReasonAndParams(proposalId, uint8(VoteType.Against), reason, "");

        assertTrue(_quorum(snapshot, proposalId) != 0);
        assertFalse(_governorV5().voteSucceeded(proposalId));
    }

    /*//////////////////////////////////////////////////////////////
                                REVERTS
    //////////////////////////////////////////////////////////////*/

    function testRevert_proposeWithModule_onlyManager() public virtual {
        bytes memory proposalData = _formatProposalData();

        vm.expectRevert("Only the manager can call this function");
        _governorV5().proposeWithModule(VotingModule(module), proposalData, "");
    }

    function testRevert_proposeWithModule_proposalAlreadyCreated() public virtual {
        bytes memory proposalData = _formatProposalData();

        vm.startPrank(manager);
        _governorV5().proposeWithModule(VotingModule(module), proposalData, description);

        vm.expectRevert("Governor: proposal already exists");
        _governorV5().proposeWithModule(VotingModule(module), proposalData, description);
        vm.stopPrank();
    }

    function testRevert_proposeWithModule_moduleNotApproved() public virtual {
        bytes memory proposalData = _formatProposalData();
        address module_ = makeAddr("module");

        vm.prank(manager);
        vm.expectRevert("Governor: module not approved");
        _governorV5().proposeWithModule(VotingModule(module_), proposalData, description);
    }

    function testRevert_cancelWithModule_proposalNotActive() public virtual {
        bytes memory proposalData = _formatProposalData();

        vm.startPrank(manager);
        uint256 proposalId = _governorV5().proposeWithModule(VotingModule(module), proposalData, description);
        _governorV5().cancelWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));

        vm.expectRevert("Governor: proposal not active");
        _governorV5().cancelWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        vm.stopPrank();

        assertEq(uint8(_governorV5().state(proposalId)), uint8(ProposalState.Canceled));
    }

    function testRevert_castVoteWithModule_voteNotActive() public virtual {
        bytes memory proposalData = _formatProposalData();
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = _governorV5().proposeWithModule(VotingModule(module), proposalData, description);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(voter);
        vm.expectRevert("Governor: vote not currently active");
        _governorV5().castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);
    }

    function testRevert_executeWithModule_proposalNotSuccessful() public virtual {
        bytes memory proposalData = _formatProposalData();
        uint256 snapshot = block.number + _governorV5().votingDelay();
        uint256 deadline = snapshot + _governorV5().votingPeriod();

        vm.prank(manager);
        uint256 proposalId = _governorV5().proposeWithModule(VotingModule(module), proposalData, description);

        vm.roll(deadline + 1);

        assertEq(uint8(_governorV5().state(proposalId)), uint8(ProposalState.Defeated));

        vm.prank(manager);
        vm.expectRevert("Governor: proposal not successful");
        _governorV5().executeWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
    }

    function testRevert_setModuleApproval_onlyManager() public virtual {
        address module_ = makeAddr("module");

        vm.expectRevert("Only the manager can call this function");
        _governorV5().setModuleApproval(module_, true);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

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

    function _governorV5() private view returns (OptimismGovernorV5Mock) {
        return OptimismGovernorV5Mock(payable(governor));
    }

    function _quorum(uint256 snapshot, uint256) internal view virtual returns (uint256) {
        return _governorV5().quorum(snapshot);
    }
}
