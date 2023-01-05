// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {GovernorCountingSimpleUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorCountingSimpleUpgradeable.sol";
import {GovernorVotesQuorumFractionUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import {GovernorVotesUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {TimersUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/TimersUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract OptimismGovernorV1 is
    Initializable,
    GovernorCountingSimpleUpgradeable,
    GovernorVotesUpgradeable,
    GovernorVotesQuorumFractionUpgradeable
{
    using TimersUpgradeable for TimersUpgradeable.BlockNumber;

    event ProposalDeadlineUpdated(uint256 proposalId, uint64 deadline);

    address public manager;

    function initialize(IVotesUpgradeable _votingToken, address _manager) public initializer {
        __Governor_init("Optimism");
        __GovernorCountingSimple_init();
        __GovernorVotes_init(_votingToken);
        __GovernorVotesQuorumFraction_init(10); // TODO: Quorum value

        manager = _manager;
    }

    function votingDelay() public pure override returns (uint256) {
        // TODO: Voting delay value
        return 6575; // 1 day, in blocks
    }

    function votingPeriod() public pure override returns (uint256) {
        // TODO: Voting period value
        return 46027; // 1 week, in blocks
    }

    function _execute(
        uint256, /* proposalId */
        address[] memory, /* targets */
        uint256[] memory, /* values */
        bytes[] memory, /* calldatas */
        bytes32 /*descriptionHash*/
    ) internal view override {
        require(msg.sender == manager, "Only the manager can execute");

        // Execution is skipped
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override returns (uint256) {
        require(msg.sender == manager, "Only the manager can propose");

        return super.propose(targets, values, calldatas, description);
    }

    function updateProposalDeadline(uint256 proposalId, uint64 deadline) public {
        require(msg.sender == manager, "Only the manager can update the proposal deadline");

        // TODO: Limit when this can be updated
        _proposals[proposalId].voteEnd.setDeadline(deadline);
        emit ProposalDeadlineUpdated(proposalId, deadline);
    }
}
