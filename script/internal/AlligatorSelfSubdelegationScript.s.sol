// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {Helpers} from "./utils/Helpers.sol";
import {SubdelegationRules, AllowanceType} from "src/structs/RulesV3.sol";

contract AlligatorSelfSubdelegateScript is Helpers {
    function run() public {
        address delegator = vm.rememberKey(vm.envUint("DELEGATOR_KEY"));

        // Set allowance to 0 to remove subdelegation
        SubdelegationRules memory rules = SubdelegationRules({
            maxRedelegations: 255,
            blocksBeforeVoteCloses: 0,
            notValidBefore: 0,
            notValidAfter: 0,
            customRule: address(0),
            allowanceType: AllowanceType.Absolute,
            allowance: 1e18
        });

        vm.startBroadcast(delegator);

        alligatorV5.subdelegate(delegator, rules);

        vm.stopBroadcast();
    }
}
