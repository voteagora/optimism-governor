// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {OptimismGovernorV3} from "../src/OptimismGovernorV3.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeOptimismGovernorToV3Script is Script {
    function run() public {
        address deployer = vm.rememberKey(vm.envUint("DEPLOYER_KEY"));

        vm.startBroadcast(deployer);
        OptimismGovernorV3 implementation = new OptimismGovernorV3();
        vm.stopBroadcast();

        console.log("OptimismGovernorV3 deployed at", address(implementation));
    }
}
