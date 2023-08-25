// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IVotesUpgradeable} from "../../src/OptimismGovernorV5.sol";
import {OptimismGovernorV6} from "../../src/OptimismGovernorV6.sol";

// Expose internal functions for testing
contract OptimismGovernorV6Mock is OptimismGovernorV6 {
    function initialize(IVotesUpgradeable _votingToken, address _manager) public initializer {
        __Governor_init("Optimism");
        __GovernorCountingSimple_init();
        __GovernorVotes_init(_votingToken);
        __GovernorVotesQuorumFraction_init({quorumNumeratorValue: 30});
        __GovernorSettings_init({initialVotingDelay: 0, initialVotingPeriod: 100, initialProposalThreshold: 0});

        manager = _manager;
    }

    function quorumReached(uint256 proposalId) public view returns (bool) {
        return _quorumReached(proposalId);
    }

    function voteSucceeded(uint256 proposalId) public view returns (bool) {
        return _voteSucceeded(proposalId);
    }
}
