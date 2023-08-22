// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VotingModule} from "./VotingModule.sol";

abstract contract PartialVotingModule {
    function supportsPartialVoting() external pure returns (bool) {
        return true;
    }
}
