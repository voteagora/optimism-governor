// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {Helpers} from "./utils/Helpers.sol";
import {SubdelegationRules, AllowanceType} from "src/structs/RulesV3.sol";

contract AlligatorSubdelegateWithExpiryScript is Helpers {
    function run() public {
        address voter3 = vm.rememberKey(vm.envUint("VOTER3_KEY"));
        address voter1 = vm.rememberKey(vm.envUint("VOTER1_KEY"));

        // Set allowance to 0 to remove subdelegation
        SubdelegationRules memory rules = SubdelegationRules({
            maxRedelegations: 255,
            blocksBeforeVoteCloses: 0,
            notValidBefore: 0,
            notValidAfter: 1701018000,
            customRule: address(0),
            allowanceType: AllowanceType.Absolute,
            allowance: 1e19
        });

        vm.startBroadcast(voter3);

        alligatorV5.subdelegate(voter1, rules);

        vm.stopBroadcast();
    }
}
