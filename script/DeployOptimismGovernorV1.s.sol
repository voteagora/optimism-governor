// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {OptimismGovernorV1} from "../src/OptimismGovernorV1.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployOptimismGovernorV1Script is Script {
    function run() public {
        address deployer = vm.rememberKey(vm.envUint("DEPLOYER_KEY"));
        address manager = 0xE4553b743E74dA3424Ac51f8C1E586fd43aE226F;
        address admin = 0x2501c477D0A35545a387Aa4A3EEe4292A9a8B3F0;
        address op = 0x4200000000000000000000000000000000000042;

        vm.startBroadcast(deployer);

        OptimismGovernorV1 implementation = new OptimismGovernorV1();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            admin,
            abi.encodeWithSelector(OptimismGovernorV1.initialize.selector, op, manager)
        );

        vm.stopBroadcast();

        console.log("OptimismGovernorV1 deployed at", address(proxy));
    }
}
