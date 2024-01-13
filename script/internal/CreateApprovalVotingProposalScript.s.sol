// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {Helpers} from "./utils/Helpers.sol";

contract CreateApprovalVotingProposalScript is Helpers {
    function run() public returns (uint256 proposalId) {
        address manager = vm.rememberKey(vm.envUint("MANAGER_KEY"));

        vm.startBroadcast(manager);

        bytes memory proposalData = _formatProposalData();
        proposalId = governor.proposeWithModule(module, proposalData, "# test proposal 3");

        vm.stopBroadcast();
    }
}
