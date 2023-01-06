// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {OptimismGovernorV1} from "../src/OptimismGovernorV1.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployOptimismGovernorV1Script is Script {
    function run() public {
        address deployer = vm.rememberKey(vm.envUint("DEPLOYER_KEY"));
        address manager = vm.rememberKey(vm.envUint("MANAGER_KEY"));
        address admin = deployer;
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

        vm.startBroadcast(manager);
        OptimismGovernorV1 governor = OptimismGovernorV1(payable(address(proxy)));
        governor.setVotingDelay(0);
        governor.setVotingPeriod(2 hours / 15);
        governor.updateQuorumNumerator(0);
        vm.stopBroadcast();
    }
}
