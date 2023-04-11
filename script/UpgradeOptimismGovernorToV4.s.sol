// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {OptimismGovernorV4} from "../src/OptimismGovernorV4.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeOptimismGovernorToV4Script is Script {
    TransparentUpgradeableProxy internal constant proxy =
        TransparentUpgradeableProxy(payable(0xcDF27F107725988f2261Ce2256bDfCdE8B382B10));

    function run() public {
        address deployer = vm.rememberKey(vm.envUint("DEPLOYER_KEY"));

        vm.startBroadcast(deployer);
        
        OptimismGovernorV4 implementation = new OptimismGovernorV4();

        console.log("OptimismGovernorV4 deployed at", address(implementation));

        proxy.upgradeToAndCall(address(implementation), abi.encodeWithSignature("_correctQuorumForBlock83241938()"));
        
        console.log("OptimismGovernor upgraded to V4");
        
        vm.stopBroadcast();
    }
}
