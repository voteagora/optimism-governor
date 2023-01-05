// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {OptimismGovernorV1} from "../src/OptimismGovernorV1.sol";
import {GovernanceToken as OptimismToken} from "../src/OptimismToken.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract OptimismGovernorV1Test is Test {
    OptimismGovernorV1 internal governor;

    OptimismToken internal constant op = OptimismToken(0x4200000000000000000000000000000000000042);
    address internal constant admin = 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa;
    address internal constant manager = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;

    function setUp() public {
        // Block number 60351051 is ~ 2023-01-04 20:33:00 PT
        vm.createSelectFork("https://mainnet.optimism.io", 60351051);

        OptimismGovernorV1 implementation = new OptimismGovernorV1();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            admin,
            abi.encodeWithSelector(OptimismGovernorV1.initialize.selector, op, manager)
        );

        governor = OptimismGovernorV1(payable(address(proxy)));
    }

    function testIncrement() public {
        console.log(">>>: %s", address(0x1E79b045Dc29eAe9fdc69673c9DCd7C53E5E159D).balance);
        console.log(">>>: %s", block.chainid);
        vm.prank(op.owner());
        op.mint(address(this), 1000);
    }
}
