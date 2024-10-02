// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {Helpers} from "./utils/Helpers.sol";
import {SubdelegationRules, AllowanceType} from "src/structs/RulesV3.sol";

// Using relative allowance
contract AlligatorSubdelegateChainScript is Helpers {
    function run() public {
        address delegator0 = vm.rememberKey(vm.envUint("DELEGATOR_KEY"));
        address delegator1 = vm.rememberKey(vm.envUint("VOTER1_KEY"));
        address delegator2 = vm.rememberKey(vm.envUint("VOTER2_KEY"));
        address delegator3 = vm.rememberKey(vm.envUint("VOTER3_KEY"));
        address delegator4 = vm.rememberKey(vm.envUint("VOTER4_KEY"));

        address[] memory delegators = new address[](5);
        delegators[0] = delegator0;
        delegators[1] = delegator1;
        delegators[2] = delegator2;
        delegators[3] = delegator3;
        delegators[4] = delegator4;

        SubdelegationRules memory rules = SubdelegationRules({
            maxRedelegations: 255,
            blocksBeforeVoteCloses: 0,
            notValidBefore: 0,
            notValidAfter: 0,
            customRule: address(0),
            allowanceType: AllowanceType.Relative,
            allowance: 50
        });

        for (uint256 i = 0; i < delegators.length - 1; i++) {
            vm.startBroadcast(delegators[i]);
            alligatorV5.subdelegate(delegators[i + 1], rules);
            vm.stopBroadcast();
        }
    }
}
