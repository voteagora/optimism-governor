// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {Helpers} from "./utils/Helpers.sol";
import {SubdelegationRules, AllowanceType} from "src/structs/RulesV3.sol";
import {GovernanceToken as OptimismToken} from "src/lib/OptimismToken.sol";

contract TokenDelegateScript is Helpers {
    function run() public {
        address voter = vm.rememberKey(vm.envUint("MANAGER_KEY"));

        vm.startBroadcast(voter);
        OptimismToken(op).delegate(alligatorV5.proxyAddress(voter));

        vm.stopBroadcast();
    }
}
