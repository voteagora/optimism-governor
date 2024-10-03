// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ProposalTypesConfigurator} from "src/ProposalTypesConfigurator.sol";
import {IProposalTypesConfigurator} from "src/interfaces/IProposalTypesConfigurator.sol";

contract ProposalTypesConfiguratorTest is Test {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProposalTypeSet(
        uint8 indexed proposalTypeId, uint16 quorum, uint16 approvalThreshold, string name, string description
    );

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address admin = makeAddr("admin");
    address timelock = makeAddr("timelock");
    address manager = makeAddr("manager");
    address deployer = makeAddr("deployer");
    GovernorMock public governor;
    ProposalTypesConfigurator public proposalTypesConfigurator;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        governor = new GovernorMock(admin, timelock);

        vm.startPrank(deployer);
        proposalTypesConfigurator = new ProposalTypesConfigurator();
        proposalTypesConfigurator.initialize(address(governor), new ProposalTypesConfigurator.ProposalType[](0));
        vm.stopPrank();

        vm.startPrank(admin);
        proposalTypesConfigurator.setProposalType(0, 3_000, 5_000, "Default", "Default", address(0));
        proposalTypesConfigurator.setProposalType(1, 5_000, 7_000, "Alt", "Alt", address(0));
        vm.stopPrank();
    }

    function _adminOrTimelock(uint256 _actorSeed) internal view returns (address) {
        if (_actorSeed % 2 == 1) return admin;
        else return governor.timelock();
    }
}

contract Initialize is ProposalTypesConfiguratorTest {
    function test_SetsGovernor(address _actor, address _governor) public {
        ProposalTypesConfigurator proposalTypesConfigurator = new ProposalTypesConfigurator();
        vm.prank(_actor);
        proposalTypesConfigurator.initialize(address(_governor), new ProposalTypesConfigurator.ProposalType[](0));
        assertEq(_governor, address(proposalTypesConfigurator.governor()));
    }

    function test_SetsProposalTypes(address _actor, uint8 _proposalTypes) public {
        ProposalTypesConfigurator proposalTypesConfigurator = new ProposalTypesConfigurator();
        ProposalTypesConfigurator.ProposalType[] memory proposalTypes =
            new ProposalTypesConfigurator.ProposalType[](_proposalTypes);
        vm.prank(_actor);
        proposalTypesConfigurator.initialize(address(governor), proposalTypes);
        for (uint8 i = 0; i < _proposalTypes; i++) {
            IProposalTypesConfigurator.ProposalType memory propType = proposalTypesConfigurator.proposalTypes(i);
            assertEq(propType.quorum, 0);
            assertEq(propType.approvalThreshold, 0);
            assertEq(propType.name, "");
        }
    }

    function test_RevertIf_AlreadyInit() public {
        vm.expectRevert(IProposalTypesConfigurator.AlreadyInit.selector);
        proposalTypesConfigurator.initialize(address(governor), new ProposalTypesConfigurator.ProposalType[](0));
    }
}

contract ProposalTypes is ProposalTypesConfiguratorTest {
    function test_ProposalTypes() public view {
        IProposalTypesConfigurator.ProposalType memory propType = proposalTypesConfigurator.proposalTypes(0);

        assertEq(propType.quorum, 3_000);
        assertEq(propType.approvalThreshold, 5_000);
        assertEq(propType.name, "Default");
    }
}

contract SetProposalType is ProposalTypesConfiguratorTest {
    function testFuzz_SetProposalType(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectEmit();
        emit ProposalTypeSet(0, 4_000, 6_000, "New Default", "New Default");
        proposalTypesConfigurator.setProposalType(0, 4_000, 6_000, "New Default", "New Default", address(0));

        IProposalTypesConfigurator.ProposalType memory propType = proposalTypesConfigurator.proposalTypes(0);

        assertEq(propType.quorum, 4_000);
        assertEq(propType.approvalThreshold, 6_000);
        assertEq(propType.name, "New Default");

        vm.prank(_adminOrTimelock(_actorSeed));
        proposalTypesConfigurator.setProposalType(1, 0, 0, "Optimistic", "Optimistic", address(0));
        propType = proposalTypesConfigurator.proposalTypes(1);
        assertEq(propType.quorum, 0);
        assertEq(propType.approvalThreshold, 0);
        assertEq(propType.name, "Optimistic");
    }

    function test_RevertIf_NotAdminOrTimelock(address _actor) public {
        vm.assume(_actor != admin && _actor != GovernorMock(governor).timelock());
        vm.expectRevert(IProposalTypesConfigurator.NotManagerOrTimelock.selector);
        proposalTypesConfigurator.setProposalType(0, 0, 0, "", "", address(0));
    }

    function test_RevertIf_setProposalType_InvalidQuorum(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectRevert(IProposalTypesConfigurator.InvalidQuorum.selector);
        proposalTypesConfigurator.setProposalType(0, 10_001, 0, "", "", address(0));
    }

    function testRevert_setProposalType_InvalidApprovalThreshold(uint256 _actorSeed) public {
        vm.prank(_adminOrTimelock(_actorSeed));
        vm.expectRevert(IProposalTypesConfigurator.InvalidApprovalThreshold.selector);
        proposalTypesConfigurator.setProposalType(0, 0, 10_001, "", "", address(0));
    }
}

contract GovernorMock {
    address immutable adminAddress;
    address immutable timelockAddress;

    constructor(address admin_, address _timelock) {
        adminAddress = admin_;
        timelockAddress = _timelock;
    }

    function admin() external view returns (address) {
        return adminAddress;
    }

    function timelock() external view returns (address) {
        return timelockAddress;
    }
}
