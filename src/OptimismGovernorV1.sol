// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {IGovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";
import {GovernorCountingSimpleUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorCountingSimpleUpgradeable.sol";
import {GovernorVotesQuorumFractionUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import {GovernorVotesUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import {GovernorSettingsUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {TimersUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/TimersUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract OptimismGovernorV1 is
    Initializable,
    GovernorUpgradeable,
    GovernorCountingSimpleUpgradeable,
    GovernorVotesUpgradeable,
    GovernorVotesQuorumFractionUpgradeable,
    GovernorSettingsUpgradeable
{
    using TimersUpgradeable for TimersUpgradeable.BlockNumber;

    event ProposalDeadlineUpdated(uint256 proposalId, uint64 deadline);

    address public manager;

    modifier onlyManager() {
        require(msg.sender == manager, "Only the manager can call this function");
        _;
    }

    function initialize(IVotesUpgradeable _votingToken, address _manager) public initializer {
        __Governor_init("Optimism");
        __GovernorCountingSimple_init();
        __GovernorVotes_init(_votingToken);
        __GovernorVotesQuorumFraction_init({quorumNumeratorValue: 30});
        __GovernorSettings_init({initialVotingDelay: 6575, initialVotingPeriod: 46027, initialProposalThreshold: 0});

        manager = _manager;
    }

    function _execute(
        uint256, /* proposalId */
        address[] memory, /* targets */
        uint256[] memory, /* values */
        bytes[] memory, /* calldatas */
        bytes32 /*descriptionHash*/
    ) internal view override onlyManager {
        // Execution is skipped
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override onlyManager returns (uint256) {
        return super.propose(targets, values, calldatas, description);
    }

    function proposalThreshold()
        public
        view
        override (GovernorSettingsUpgradeable, GovernorUpgradeable)
        returns (uint256)
    {
        return GovernorSettingsUpgradeable.proposalThreshold();
    }

    function COUNTING_MODE()
        public
        pure
        virtual
        override (GovernorCountingSimpleUpgradeable, IGovernorUpgradeable)
        returns (string memory)
    {
        return "support=bravo&quorum=against,for,abstain";
    }

    function _quorumReached(uint256 proposalId)
        internal
        view
        virtual
        override (GovernorCountingSimpleUpgradeable, GovernorUpgradeable)
        returns (bool)
    {
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = proposalVotes(proposalId);

        return quorum(proposalSnapshot(proposalId)) <= againstVotes + forVotes + abstainVotes;
    }

    function setProposalDeadline(uint256 proposalId, uint64 deadline) public onlyManager {
        _proposals[proposalId].voteEnd.setDeadline(deadline);
        emit ProposalDeadlineUpdated(proposalId, deadline);
    }

    function setVotingDelay(uint256 newVotingDelay) public override onlyManager {
        _setVotingDelay(newVotingDelay);
    }

    function setVotingPeriod(uint256 newVotingPeriod) public override onlyManager {
        _setVotingPeriod(newVotingPeriod);
    }

    function setProposalThreshold(uint256 newProposalThreshold) public override onlyManager {
        _setProposalThreshold(newProposalThreshold);
    }

    function updateQuorumNumerator(uint256 newQuorumNumerator) external override onlyManager {
        _updateQuorumNumerator(newQuorumNumerator);
    }
}
