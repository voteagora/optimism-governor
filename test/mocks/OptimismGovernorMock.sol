// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {OptimismGovernor} from "../../src/OptimismGovernor.sol";

// Expose internal functions for testing
contract OptimismGovernorMock is OptimismGovernor {
    function initialize(IVotesUpgradeable _votingToken, address _manager) public initializer {
        __Governor_init("Optimism");
        __GovernorCountingSimple_init();
        __GovernorVotes_init(_votingToken);
        __GovernorVotesQuorumFraction_init({quorumNumeratorValue: 30});
        __GovernorSettings_init({initialVotingDelay: 0, initialVotingPeriod: 46027, initialProposalThreshold: 0});

        manager = _manager;
        _setVotingPeriod(200);
    }

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
