// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {OptimismGovernorV5} from "../src/OptimismGovernorV5.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract OptimismGovernorV5UpgradeTest is Test {
    address internal constant admin = 0x2501c477D0A35545a387Aa4A3EEe4292A9a8B3F0;
    address internal constant manager = 0xE4553b743E74dA3424Ac51f8C1E586fd43aE226F;
    address internal constant op = 0x4200000000000000000000000000000000000042;
    TransparentUpgradeableProxy internal constant proxy =
        TransparentUpgradeableProxy(payable(0xcDF27F107725988f2261Ce2256bDfCdE8B382B10));
    OptimismGovernorV5 internal governor = OptimismGovernorV5(payable(proxy));
    OptimismGovernorV5 internal implementation;

    function setUp() public {
        // Block number 88792077 is ~ Apr-11-2023 01:30:52 AM UTC
        vm.createSelectFork(vm.envString("OPTIMISM_RPC_URL"), 88792077);

        implementation = new OptimismGovernorV5();
    }

    function testUpgrade() public {
        vm.prank(admin);
        proxy.upgradeTo(address(implementation));
    }
}
