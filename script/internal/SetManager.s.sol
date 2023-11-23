// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {Helpers} from "./utils/Helpers.sol";

contract SetManagerScript is Helpers {
    function run() public {
        address manager = vm.rememberKey(vm.envUint("MANAGER_KEY"));
        address newManager = manager;

        vm.startBroadcast(manager);

        governor._setManager(newManager);

        vm.stopBroadcast();
    }
}
