// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {Helpers} from "./utils/Helpers.sol";

contract CreateStandardProposalScript is Helpers {
    function run() public returns (uint256 proposalId) {
        address manager = vm.rememberKey(vm.envUint("MANAGER_KEY"));

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = manager;

        vm.startBroadcast(manager);

        proposalId = governor.propose(targets, values, calldatas, "# Test standard proposal");

        vm.stopBroadcast();
    }
}
