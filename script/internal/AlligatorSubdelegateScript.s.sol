// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {Helpers} from "./utils/Helpers.sol";
import {SubdelegationRules, AllowanceType} from "src/structs/RulesV3.sol";

contract AlligatorSubdelegateScript is Helpers {
    function run() public {
        address manager = vm.rememberKey(vm.envUint("MANAGER_KEY"));
        address voter = vm.rememberKey(vm.envUint("VOTER_KEY"));

        SubdelegationRules memory rules = SubdelegationRules({
            maxRedelegations: 255,
            blocksBeforeVoteCloses: 0,
            notValidBefore: 0,
            notValidAfter: 0,
            customRule: address(0),
            allowanceType: AllowanceType.Absolute,
            allowance: 1e19
        });

        vm.startBroadcast(manager);

        alligatorV5.subdelegate(voter, rules);

        vm.stopBroadcast();
    }
}
