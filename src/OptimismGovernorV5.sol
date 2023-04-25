// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {GovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {IGovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";
import {GovernorCountingSimpleUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorCountingSimpleUpgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {TimersUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/TimersUpgradeable.sol";
import {OptimismGovernorV3} from "./OptimismGovernorV3.sol";
import {VotingModule} from "./modules/VotingModule.sol";

/**
 * @notice Introduces delegation to custom voting modules.
 *
 * @dev Requires adding an `address votingModule` to{GovernorUpgradeable-ProposalCore} struct.
 */
contract OptimismGovernorV5 is OptimismGovernorV3 {
    /*//////////////////////////////////////////////////////////////
                               LIBRARIES
    //////////////////////////////////////////////////////////////*/

    using SafeCastUpgradeable for uint256;
    using TimersUpgradeable for TimersUpgradeable.BlockNumber;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a proposal with module is created.
     */
    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address votingModule,
        bytes proposalData,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create a new proposal with a custom voting module. See {IGovernor-propose}.
     */
    function proposeWithModule(VotingModule module, bytes memory proposalData, string memory description)
        public
        onlyManager
        returns (uint256)
    {
        require(
            getVotes(_msgSender(), block.number - 1) >= proposalThreshold(),
            "Governor: proposer votes below proposal threshold"
        );

        uint256 proposalId = hashProposalWithData(address(module), proposalData, keccak256(bytes(description)));

        ProposalCore storage proposal = _proposals[proposalId];
        require(proposal.voteStart.isUnset(), "Governor: proposal already exists");

        uint64 snapshot = block.number.toUint64() + votingDelay().toUint64();
        uint64 deadline = snapshot + votingPeriod().toUint64();

        proposal.voteStart.setDeadline(snapshot);
        proposal.voteEnd.setDeadline(deadline);
        proposal.votingModule = address(module);

        emit ProposalCreated(proposalId, _msgSender(), address(module), proposalData, snapshot, deadline, description);

        module.propose(proposalId, proposalData);

        return proposalId;
    }

    /**
     * @notice Executes a proposal via a custom voting module. See {IGovernor-execute}.
     */
    function executeWithModule(VotingModule module, bytes memory proposalData, bytes32 descriptionHash)
        public
        payable
        onlyManager
        returns (uint256)
    {
        uint256 proposalId = hashProposalWithData(address(module), proposalData, descriptionHash);

        ProposalState status = state(proposalId);
        require(
            status == ProposalState.Succeeded || status == ProposalState.Queued, "Governor: proposal not successful"
        );
        _proposals[proposalId].executed = true;

        emit ProposalExecuted(proposalId);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            module._formatExecuteParams(proposalId, proposalData);

        _beforeExecute(proposalId, targets, values, calldatas, descriptionHash);
        _execute(proposalId, targets, values, calldatas, descriptionHash);
        _afterExecute(proposalId, targets, values, calldatas, descriptionHash);

        return proposalId;
    }

    /**
     * @notice Cancel a proposal with a custom voting module. See {IGovernor-_cancel}.
     */
    function cancelWithModule(address module, bytes memory proposalData, bytes32 descriptionHash)
        public
        onlyManager
        returns (uint256)
    {
        uint256 proposalId = hashProposalWithData(module, proposalData, descriptionHash);
        ProposalState status = state(proposalId);

        require(
            status != ProposalState.Canceled && status != ProposalState.Expired && status != ProposalState.Executed,
            "Governor: proposal not active"
        );
        _proposals[proposalId].canceled = true;

        emit ProposalCanceled(proposalId);

        return proposalId;
    }

    /**
     * @dev Updated internal vote casting mechanism which allows delegating logic to custom voting module. See {IGovernor-_castVote}.
     */
    function _castVote(uint256 proposalId, address account, uint8 support, string memory reason, bytes memory params)
        internal
        override
        returns (uint256)
    {
        ProposalCore memory proposal = _proposals[proposalId];
        require(state(proposalId) == ProposalState.Active, "Governor: vote not currently active");

        uint256 weight = _getVotes(account, proposal.voteStart.getDeadline(), params);

        if (proposal.votingModule != address(0)) {
            VotingModule(proposal.votingModule)._countVote(proposalId, account, support, reason, params, weight);
        } else {
            _countVote(proposalId, account, support, weight, params);
        }

        if (params.length == 0) {
            emit VoteCast(account, proposalId, support, weight, reason);
        } else {
            emit VoteCastWithParams(account, proposalId, support, weight, reason, params);
        }

        return weight;
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice COUNTING_MODE with added `params=modules` options to indicate support for external voting modules. See {IGovernor-COUNTING_MODE}.
     */
    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "support=bravo&quorum=against,for,abstain&params=modules";
    }

    /**
     * @dev Updated `hasVoted` which allows delegating logic to custom voting module. See {IGovernor-hasVoted}.
     */
    function hasVoted(uint256 proposalId, address account)
        public
        view
        virtual
        override(GovernorCountingSimpleUpgradeable, IGovernorUpgradeable)
        returns (bool)
    {
        address votingModule = _proposals[proposalId].votingModule;
        if (votingModule != address(0)) {
            return VotingModule(votingModule).hasVoted(proposalId, account);
        }

        return super.hasVoted(proposalId, account);
    }

    /**
     * @dev Updated `_quorumReached` which allows delegating logic to custom voting module. See {IGovernor-_quorumReached}.
     */
    function _quorumReached(uint256 proposalId) internal view virtual override returns (bool) {
        ProposalCore memory proposal = _proposals[proposalId];
        if (proposal.votingModule != address(0)) {
            return
                VotingModule(proposal.votingModule)._quorumReached(proposalId, quorum(proposal.voteStart.getDeadline()));
        }

        return super._quorumReached(proposalId);
    }

    /**
     * @dev Updated `_voteSucceeded` which allows delegating logic to custom voting module. See {Governor-_voteSucceeded}.
     */
    function _voteSucceeded(uint256 proposalId)
        internal
        view
        virtual
        override(GovernorCountingSimpleUpgradeable, GovernorUpgradeable)
        returns (bool)
    {
        address votingModule = _proposals[proposalId].votingModule;
        if (votingModule != address(0)) {
            return VotingModule(votingModule)._voteSucceeded(proposalId);
        }

        return super._voteSucceeded(proposalId);
    }

    /*//////////////////////////////////////////////////////////////
                                 UTILS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Same as `hashProposal` but based on `module` and `proposalData`. See {IGovernor-hashProposal}.
     */
    function hashProposalWithData(address module, bytes memory proposalData, bytes32 descriptionHash)
        public
        pure
        virtual
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(module, proposalData, descriptionHash)));
    }
}
