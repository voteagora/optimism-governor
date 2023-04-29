// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {OptimismGovernorV2} from "../src/OptimismGovernorV2.sol";
import {OptimismGovernorV5} from "../src/OptimismGovernorV5.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployOptimismGovernorV5Script is Script {
    function run() public returns (OptimismGovernorV5 implementation, TransparentUpgradeableProxy proxy) {
        address deployer = vm.rememberKey(vm.envUint("DEPLOYER_KEY"));
        address op = 0x4200000000000000000000000000000000000042;

        vm.startBroadcast(deployer);

        implementation = new OptimismGovernorV5(); // 0x851875b5eB70031c7eD5Aa16912C7A49344c889c - op_goerli
        proxy = new TransparentUpgradeableProxy(
            address(implementation),
            deployer,
            abi.encodeWithSelector(OptimismGovernorV2.initialize.selector, op, deployer)
        );

        vm.stopBroadcast();
    }
}
