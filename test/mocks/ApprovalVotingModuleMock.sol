// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ApprovalVotingModule} from "../../src/modules/ApprovalVotingModule.sol";
import {Proposal, ProposalOption, ProposalSettings} from "../../src/modules/ApprovalVotingModule.sol";

// Expose internal functions for testing
contract ApprovalVotingModuleMock is ApprovalVotingModule {
    function _proposals(uint256 proposalId) public view returns (Proposal memory) {
        return proposals[proposalId];
    }

    function sortOptions(uint128[] memory optionVotes, ProposalOption[] memory options)
        public
        pure
        returns (uint128[] memory, ProposalOption[] memory)
    {
        return _sortOptions(optionVotes, options);
    }

    function countOptions(
        ProposalOption[] memory options,
        uint128[] memory optionVotes,
        ProposalSettings memory settings
    ) public pure returns (uint256 executeParamsLength, uint256 succeededOptionsLength) {
        return _countOptions(options, optionVotes, settings);
    }
}
