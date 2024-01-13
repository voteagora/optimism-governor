// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {IOptimismGovernor} from "src/interfaces/IOptimismGovernor.sol";
import {ProposalTypesConfigurator} from "src/ProposalTypesConfigurator.sol";
import {IProposalTypesConfigurator} from "src/interfaces/IProposalTypesConfigurator.sol";

contract ProposalTypesConfiguratorTest is Test {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProposalTypeSet(uint256 indexed proposalTypeId, uint16 quorum, uint16 approvalThreshold, string name);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address manager = makeAddr("manager");
    address deployer = makeAddr("deployer");
    ProposalTypesConfigurator private proposalTypesConfigurator;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        address governor = address(new GovernorMock(manager));

        vm.startPrank(deployer);
        proposalTypesConfigurator = new ProposalTypesConfigurator(IOptimismGovernor(address(governor)));
        vm.stopPrank();

        vm.startPrank(manager);
        proposalTypesConfigurator.setProposalType(0, 3_000, 5_000, "Default");
        proposalTypesConfigurator.setProposalType(1, 5_000, 7_000, "Alt");
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function testProposalTypes() public {
        IProposalTypesConfigurator.ProposalType memory propType = proposalTypesConfigurator.proposalTypes(0);

        assertEq(propType.quorum, 3_000);
        assertEq(propType.approvalThreshold, 5_000);
        assertEq(propType.name, "Default");
    }

    function testSetProposalType() public {
        vm.prank(manager);
        vm.expectEmit();
        emit ProposalTypeSet(0, 4_000, 6_000, "New Default");
        proposalTypesConfigurator.setProposalType(0, 4_000, 6_000, "New Default");

        IProposalTypesConfigurator.ProposalType memory propType = proposalTypesConfigurator.proposalTypes(0);

        assertEq(propType.quorum, 4_000);
        assertEq(propType.approvalThreshold, 6_000);
        assertEq(propType.name, "New Default");

        vm.prank(manager);
        proposalTypesConfigurator.setProposalType(1, 0, 0, "Optimistic");
        propType = proposalTypesConfigurator.proposalTypes(1);
        assertEq(propType.quorum, 0);
        assertEq(propType.approvalThreshold, 0);
        assertEq(propType.name, "Optimistic");
    }

    /*//////////////////////////////////////////////////////////////
                                REVERTS
    //////////////////////////////////////////////////////////////*/

    function testRevert_onlyManager() public {
        vm.expectRevert(IProposalTypesConfigurator.NotManager.selector);
        proposalTypesConfigurator.setProposalType(0, 0, 0, "");
    }

    function testRevert_setProposalType_InvalidQuorum() public {
        vm.prank(manager);
        vm.expectRevert(IProposalTypesConfigurator.InvalidQuorum.selector);
        proposalTypesConfigurator.setProposalType(0, 10_001, 0, "");
    }

    function testRevert_setProposalType_InvalidApprovalThreshold() public {
        vm.prank(manager);
        vm.expectRevert(IProposalTypesConfigurator.InvalidApprovalThreshold.selector);
        proposalTypesConfigurator.setProposalType(0, 0, 10_001, "");
    }
}

contract GovernorMock {
    address immutable managerAddress;

    constructor(address manager_) {
        managerAddress = manager_;
    }

    function manager() external view returns (address) {
        return managerAddress;
    }
}
