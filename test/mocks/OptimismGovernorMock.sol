// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OptimismGovernor} from "src/OptimismGovernor.sol";

// Expose internal functions for testing
contract OptimismGovernorMock is OptimismGovernor {
    function quorumReached(uint256 proposalId) public view returns (bool) {
        return _quorumReached(proposalId);
    }

    function voteSucceeded(uint256 proposalId) public view returns (bool) {
        return _voteSucceeded(proposalId);
    }

    function proposals(uint256 proposalId) public view returns (ProposalCore memory) {
        return _proposals[proposalId];
    }
}
