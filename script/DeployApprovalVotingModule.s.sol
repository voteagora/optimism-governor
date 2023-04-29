// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {ApprovalVotingModule} from "../src/modules/ApprovalVotingModule.sol";

contract DeployApprovalVotingModuleScript is Script {
    function run() public returns (ApprovalVotingModule module) {
        address deployer = vm.rememberKey(vm.envUint("DEPLOYER_KEY"));

        vm.startBroadcast(deployer);

        module = new ApprovalVotingModule();

        vm.stopBroadcast();
    }
}
