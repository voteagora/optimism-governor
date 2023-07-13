// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VotingModule} from "./VotingModule.sol";

abstract contract FractionalVotingModule {
    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight,
        bytes memory params,
        address voter
    ) external virtual;

    function supportsFractionaVoting() external pure returns (bool) {
        return true;
    }
}
