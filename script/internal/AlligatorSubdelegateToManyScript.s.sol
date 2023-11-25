// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {Helpers} from "./utils/Helpers.sol";
import {SubdelegationRules, AllowanceType} from "src/structs/RulesV3.sol";


contract AlligatorSubdelegateToManyScript is Helpers {
    function run() public {
        address delegator = vm.rememberKey(vm.envUint("DELEGATOR_KEY"));
        address voter1 = vm.rememberKey(vm.envUint("VOTER1_KEY"));
        address voter2 = vm.rememberKey(vm.envUint("VOTER2_KEY"));
        address[] memory voters = new address[](2);
        voters[0] = voter1;
        voters[1] = voter2;

        SubdelegationRules memory rules1 = SubdelegationRules({
            maxRedelegations: 255,
            blocksBeforeVoteCloses: 0,
            notValidBefore: 0,
            notValidAfter: 0,
            customRule: address(0),
            allowanceType: AllowanceType.Relative,
            allowance: 50
        });

        // Limited to 1 redelegation
        SubdelegationRules memory rules2 = SubdelegationRules({
            maxRedelegations: 2,
            blocksBeforeVoteCloses: 0,
            notValidBefore: 0,
            notValidAfter: 0,
            customRule: address(0),
            allowanceType: AllowanceType.Relative,
            allowance: 50
        });

        SubdelegationRules[] memory rules = new SubdelegationRules[](2);
        rules[0] = rules1;
        rules[1] = rules2;

        vm.startBroadcast(delegator);

        alligatorV5.subdelegateBatched(voters, rules);

        vm.stopBroadcast();
    }
}
