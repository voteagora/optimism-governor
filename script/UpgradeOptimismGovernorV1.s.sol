// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {OptimismGovernorV1} from "../src/OptimismGovernorV1.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeOptimismGovernorV1Script is Script {
    function run() public {
        address deployer = vm.rememberKey(vm.envUint("DEPLOYER_KEY"));

        vm.startBroadcast(deployer);

        OptimismGovernorV1 implementation = new OptimismGovernorV1();
        TransparentUpgradeableProxy proxy =
            TransparentUpgradeableProxy(payable(0x4200DFA134Da52D9c96F523af1fCB507199b1042));
        proxy.upgradeTo(address(implementation));

        vm.stopBroadcast();
    }
}
