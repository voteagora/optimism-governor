// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {VotableSupplyOracle} from "../src/VotableSupplyOracle.sol";

contract VotableSupplyOracleTest is Test {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event VotableSupplyUpdated(uint256 blockNumber, uint256 oldVotableSupply, uint256 newVotableSupply);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address manager = makeAddr("manager");
    VotableSupplyOracle private votableSupplyOracle;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        vm.roll(100);

        votableSupplyOracle = new VotableSupplyOracle(address(this), 100);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function testDeploy() public {
        assertEq(votableSupplyOracle.owner(), address(this));
        assertEq(votableSupplyOracle.votableSupply(), 100);
    }

    function testUpdateVotableSupply() public {
        vm.roll(block.number + 10);

        vm.expectEmit();
        emit VotableSupplyUpdated(block.number, 100, 200);
        votableSupplyOracle._updateVotableSupply(200);

        assertEq(votableSupplyOracle.votableSupply(), 200);
        assertEq(votableSupplyOracle.nextIndex(), 2);
    }

    function testUpdateVotableSupplyAt() public {
        votableSupplyOracle._updateVotableSupplyAt(0, 200);
        assertEq(votableSupplyOracle.votableSupply(), 200);
        assertEq(votableSupplyOracle.nextIndex(), 1);
    }

    function testVotableSupply() public {
        assertEq(votableSupplyOracle.votableSupply(1), 0);
        assertEq(votableSupplyOracle.votableSupply(99), 0);
        assertEq(votableSupplyOracle.votableSupply(100), 100);
    }

    function testGetIndexBeforeBlock() public {
        vm.roll(200);
        votableSupplyOracle._updateVotableSupply(200);
        vm.roll(300);
        votableSupplyOracle._updateVotableSupply(300);

        vm.expectRevert();
        votableSupplyOracle.getIndexBeforeBlock(uint32(99));

        assertEq(votableSupplyOracle.getIndexBeforeBlock(uint32(100)), 0);
        assertEq(votableSupplyOracle.getIndexBeforeBlock(uint32(101)), 0);
        assertEq(votableSupplyOracle.getIndexBeforeBlock(uint32(201)), 1);
        assertEq(votableSupplyOracle.getIndexBeforeBlock(uint32(301)), 2);
    }

    /*//////////////////////////////////////////////////////////////
                                REVERTS
    //////////////////////////////////////////////////////////////*/

    function testRevert_updateVotableSupplyAt_outOfBounds() public {
        vm.expectRevert();
        votableSupplyOracle._updateVotableSupplyAt(6, 200);
    }

    function testRevert_onlyOwner() public {
        vm.startPrank(address(1));

        vm.expectRevert("Ownable: caller is not the owner");
        votableSupplyOracle._updateVotableSupply(200);
        vm.expectRevert("Ownable: caller is not the owner");
        votableSupplyOracle._updateVotableSupplyAt(0, 200);

        vm.stopPrank();
    }
}
