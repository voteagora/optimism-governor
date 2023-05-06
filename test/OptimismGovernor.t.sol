// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {OptimismGovernorV1} from "../src/OptimismGovernorV1.sol";
import {OptimismGovernorV3} from "../src/OptimismGovernorV3.sol";
import {GovernanceToken as OptimismToken} from "../src/lib/OptimismToken.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IGovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";

contract OptimismGovernorV1Test is Test {
    OptimismGovernorV3 internal governor;

    OptimismToken internal constant op = OptimismToken(0x4200000000000000000000000000000000000042);
    address internal constant admin = 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa;
    address internal constant manager = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;

    function setUp() public {
        // Block number 60351051 is ~ 2023-01-04 20:33:00 PT
        vm.createSelectFork("https://mainnet.optimism.io", 60351051);

        OptimismGovernorV3 implementation = new OptimismGovernorV3();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            admin,
            abi.encodeWithSelector(OptimismGovernorV1.initialize.selector, op, manager)
        );

        governor = OptimismGovernorV3(payable(address(proxy)));
    }

    function testUpdateSettings() public {
        vm.startPrank(manager);
        governor.setVotingDelay(7);
        governor.setVotingPeriod(14);
        governor.setProposalThreshold(2);
        vm.stopPrank();

        assertEq(governor.votingDelay(), 7);
        assertEq(governor.votingPeriod(), 14);
        assertEq(governor.proposalThreshold(), 2);

        vm.expectRevert("Only the manager can call this function");
        governor.setVotingDelay(70);
        vm.expectRevert("Only the manager can call this function");
        governor.setVotingPeriod(140);
        vm.expectRevert("Only the manager can call this function");
        governor.setProposalThreshold(20);
    }

    function testPropose() public {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        uint256 deadline = governor.proposalDeadline(proposalId);
        vm.prank(manager);
        governor.setProposalDeadline(proposalId, uint64(deadline + 1 days));

        assertEq(governor.proposalDeadline(proposalId), deadline + 1 days);

        vm.expectRevert("Only the manager can call this function");
        governor.propose(targets, values, calldatas, "From someone else");
    }

    function testExecute() public {
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
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);
        governor.updateQuorumNumerator(0);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        vm.stopPrank();

        vm.roll(block.number + 1);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + 14);

        vm.expectRevert("Only the manager can call this function");
        governor.execute(targets, values, calldatas, keccak256("Test"));

        vm.prank(manager);
        governor.execute(targets, values, calldatas, keccak256("Test"));

        IGovernorUpgradeable.ProposalState state = governor.state(proposalId);
        assertEq(uint256(state), uint256(IGovernorUpgradeable.ProposalState.Executed));
    }

    function testCancel() public {
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
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);
        governor.updateQuorumNumerator(0);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        vm.stopPrank();

        vm.expectRevert("Only the manager can call this function");
        governor.cancel(targets, values, calldatas, keccak256("Test"));

        vm.prank(manager);
        governor.cancel(targets, values, calldatas, keccak256("Test"));

        IGovernorUpgradeable.ProposalState state = governor.state(proposalId);
        assertEq(uint256(state), uint256(IGovernorUpgradeable.ProposalState.Canceled));
    }

    function executeCallback() public payable {
        revert("Executor shouldn't have called this function");
    }
}
