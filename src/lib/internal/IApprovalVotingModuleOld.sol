// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IApprovalVotingModuleOld {
    struct ProposalVotes {
        uint128 forVotes;
        uint128 abstainVotes;
    }

    struct Proposal {
        address governor;
        ProposalVotes votes;
    }

    function _proposals(uint256 proposalId) external view returns (Proposal memory prop);
}
