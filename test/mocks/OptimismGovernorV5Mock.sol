// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {OptimismGovernorV5} from "../../src/OptimismGovernorV5.sol";

// Expose internal functions for testing
contract OptimismGovernorV5Mock is OptimismGovernorV5 {
    function quorumReached(uint256 proposalId) public view returns (bool) {
        return _quorumReached(proposalId);
    }

    function voteSucceeded(uint256 proposalId) public view returns (bool) {
        return _voteSucceeded(proposalId);
    }
}
