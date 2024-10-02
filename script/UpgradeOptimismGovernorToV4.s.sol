// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {OptimismGovernorV4} from "../src/OptimismGovernorV4.sol";

contract UpgradeOptimismGovernorToV4Script is Script {
    function run() public {
        address deployer = vm.rememberKey(vm.envUint("DEPLOYER_KEY"));

        vm.startBroadcast(deployer);
        OptimismGovernorV4 implementation = new OptimismGovernorV4();
        vm.stopBroadcast();

        console.log("OptimismGovernorV4 deployed at", address(implementation));
    }
}
