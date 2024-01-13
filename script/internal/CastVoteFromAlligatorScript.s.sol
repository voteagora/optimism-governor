// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {Helpers} from "./utils/Helpers.sol";

enum VoteType {
    Against,
    For,
    Abstain
}

contract CastVoteFromAlligatorScript is Helpers {
    // uint256 proposalId = 25179435040570377559441930496770743316573474586898720459641117522244453534855; // standard
    uint256 proposalId = 111564573816138384357920124066409997513056198423172703120337982376524727591617; // approval voting

    function run() public {
        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        address voter = vm.rememberKey(vm.envUint("VOTER_KEY"));
        address delegator = vm.rememberKey(vm.envUint("MANAGER_KEY"));

        address[] memory authority = new address[](2);
        authority[0] = delegator;
        authority[1] = voter;

        vm.startBroadcast(voter);

        alligatorV5.castVoteWithReasonAndParams(authority, proposalId, uint8(VoteType.For), "my reason", params);

        vm.stopBroadcast();
    }
}
