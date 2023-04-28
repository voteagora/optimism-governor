// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VotingModule} from "./VotingModule.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";
import {LibSort} from "@solady/utils/LibSort.sol";

contract ApprovalVotingModule is VotingModule {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error ExistingProposal();
    error InvalidParams();
    error VoteAlreadyCast();
    error MaxApprovalsExceeded();
    error RepeatedOption(uint256 option);
    error InvalidVoteType();

    /*//////////////////////////////////////////////////////////////
                               LIBRARIES
    //////////////////////////////////////////////////////////////*/

    using LibSort for uint256[];
    using SafeCastLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    enum VoteType {
        For,
        Abstain
    }

    enum PassingCriteria {
        Threshold,
        TopChoices
    }

    struct ProposalVotes {
        uint128 forVotes;
        uint128 abstainVotes;
    }

    struct ProposalSettings {
        uint8 maxApprovals;
        uint8 criteria;
        uint112 criteriaValue;
        uint128 budget;
    }

    struct ProposalOption {
        string description;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
    }

    struct Proposal {
        address governor;
        uint128[] optionVotes;
        ProposalVotes votes;
        ProposalOption[] options;
        ProposalSettings settings;
    }

    struct ApprovalVoteParams {
        uint256[] options;
    }

    struct ApprovalVoteProposalParams {
        ProposalOption[] options;
        ProposalSettings settings;
    }

    mapping(uint256 proposalId => Proposal) public _proposals;
    mapping(uint256 proposalId => mapping(address account => uint8)) public _accountVotes;

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function propose(uint256 proposalId, bytes memory proposalData) external override {
        if (_proposals[proposalId].governor != address(0)) revert ExistingProposal();

        ApprovalVoteProposalParams memory params = abi.decode(proposalData, (ApprovalVoteProposalParams));

        uint256 optionsLength = params.options.length;
        if (optionsLength == 0 || optionsLength > type(uint8).max) revert InvalidParams();

        unchecked {
            // Ensure proposal params of each option have the same length between themselves
            ProposalOption memory option;
            for (uint256 i; i < optionsLength; ++i) {
                option = params.options[i];
                if (option.targets.length != option.values.length || option.targets.length != option.calldatas.length) {
                    revert InvalidParams();
                }
            }

            // Push proposal options in storage
            for (uint256 i; i < optionsLength; ++i) {
                _proposals[proposalId].options[i] = params.options[i];
            }
        }

        _proposals[proposalId].governor = msg.sender;
        _proposals[proposalId].settings = params.settings;
        _proposals[proposalId].optionVotes = new uint128[](optionsLength);
    }

    function _countVote(uint256 proposalId, address account, uint8 support, uint256 weight, bytes memory params)
        external
        override
    {
        Proposal memory proposal = _proposals[proposalId];
        _onlyGovernor(proposal.governor);

        if (hasVoted(proposalId, account)) revert VoteAlreadyCast();

        if (support == uint8(VoteType.Abstain)) {
            _proposals[proposalId].votes.abstainVotes += weight.toUint128();
            _accountVotes[proposalId][account] = 1;
        } else if (support == uint8(VoteType.For)) {
            ApprovalVoteParams memory approvalVoteParams = abi.decode(params, (ApprovalVoteParams));
            uint256[] memory options = approvalVoteParams.options;
            uint256 totalOptions = options.length;
            if (totalOptions == 0) revert InvalidParams();
            if (totalOptions > proposal.settings.maxApprovals) revert MaxApprovalsExceeded();

            // TODO: Change - Assume sorted options and revert if otherwise
            // sort options array in place
            options.sort();

            uint128 weight_ = weight.toUint128();
            uint256 currOption;
            uint256 prevOption;
            for (uint256 i; i < totalOptions;) {
                currOption = options[i];
                if (i != 0) {
                    if (currOption == prevOption) {
                        revert RepeatedOption(currOption);
                    }
                }
                prevOption = currOption;

                _proposals[proposalId].optionVotes[currOption] += weight_;

                unchecked {
                    ++i;
                }
            }
            _proposals[proposalId].votes.forVotes += weight_;
            // `totalOptions` cannot overflow uint8 as it is checked against `maxApprovals`
            _accountVotes[proposalId][account] = uint8(totalOptions);
        } else {
            revert InvalidVoteType();
        }
    }

    function _formatExecuteParams(uint256 proposalId, bytes memory proposalData)
        public
        view
        override
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        _onlyGovernor(_proposals[proposalId].governor);

        ApprovalVoteProposalParams memory params = abi.decode(proposalData, (ApprovalVoteProposalParams));

        // Sort `options` by `optionVotes` in descending order
        (uint128[] memory optionVotes, ProposalOption[] memory options) =
            _sort(_proposals[proposalId].optionVotes, params.options);

        uint256 executeParamsLength;
        uint256 succeededOptionsLength;

        // Set `executeParamsLength` and `succeededOptionsLength`
        uint256 n = options.length;
        unchecked {
            uint256 i;
            if (params.settings.criteria == uint8(PassingCriteria.Threshold)) {
                for (i; i < n; ++i) {
                    if (optionVotes[i] >= params.settings.criteriaValue) {
                        executeParamsLength += options[i].targets.length;
                    } else {
                        break;
                    }
                }
                succeededOptionsLength = i;
            } else if (params.settings.criteria == uint8(PassingCriteria.TopChoices)) {
                for (i; i < n; ++i) {
                    if (succeededOptionsLength < params.settings.criteriaValue) {
                        executeParamsLength += options[i].targets.length;
                        ++succeededOptionsLength;
                    } else {
                        break;
                    }
                }
            }
        }

        targets = new address[](executeParamsLength);
        values = new uint256[](executeParamsLength);
        calldatas = new bytes[](executeParamsLength);

        n = 0;
        uint256 totalValue;
        uint256 optionTargetsLength;
        uint256 optionValue;
        ProposalOption memory option;

        // Set `targets`, `values` and `calldatas`
        for (uint256 i; i < succeededOptionsLength;) {
            option = options[i];
            optionTargetsLength = option.targets.length;
            for (n; n < optionTargetsLength;) {
                optionValue = option.values[n];
                totalValue += optionValue;

                // Shortcircuit if the budget is exceeded
                if (params.settings.budget != 0) {
                    // TODO: consider budget is in OP
                    if (totalValue > params.settings.budget) {
                        return (targets, values, calldatas);
                    }
                }

                targets[n] = option.targets[n];
                values[n] = optionValue;
                calldatas[n] = option.calldatas[n];

                unchecked {
                    ++n;
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Return true if `account` has cast at least a vote for `proposalId`.
     */
    function hasVoted(uint256 proposalId, address account) public view override returns (bool) {
        return _accountVotes[proposalId][account] != 0;
    }

    /**
     * @dev Return for, abstain and option votes for a `proposalId`.
     */
    function proposalVotes(uint256 proposalId)
        public
        view
        virtual
        returns (uint256 forVotes, uint256 abstainVotes, uint128[] memory optionVotes)
    {
        ProposalVotes memory votes = _proposals[proposalId].votes;
        return (votes.forVotes, votes.abstainVotes, _proposals[proposalId].optionVotes);
    }

    /**
     * @dev Used by governor in `_quorumReached`. See {Governor-_quorumReached}.
     */
    function _quorumReached(uint256 proposalId, uint256 quorum) external view override returns (bool) {
        _onlyGovernor(_proposals[proposalId].governor);
        ProposalVotes memory votes = _proposals[proposalId].votes;

        return quorum <= votes.forVotes + votes.abstainVotes;
    }

    /**
     * @dev Return true if at least one option satisfies the passing criteria.
     * Used by governor in `_voteSucceeded`. See {Governor-_voteSucceeded}.
     */
    function _voteSucceeded(uint256 proposalId) external view override returns (bool) {
        Proposal memory proposal = _proposals[proposalId];
        _onlyGovernor(proposal.governor);

        ProposalOption[] memory options = proposal.options;
        uint256 n = options.length;
        unchecked {
            if (proposal.settings.criteria == uint8(PassingCriteria.Threshold)) {
                for (uint256 i; i < n; ++i) {
                    if (proposal.optionVotes[i] >= proposal.settings.criteriaValue) return true;
                }
            } else if (proposal.settings.criteria == uint8(PassingCriteria.TopChoices)) {
                for (uint256 i; i < n; ++i) {
                    if (proposal.optionVotes[i] != 0) return true;
                }
            }
        }

        return false;
    }

    /**
     * @dev See {IGovernor-COUNTING_MODE}.
     *
     * - `support=for,abstain`: the vote options are 0 = For, 1 = Abstain.
     * - `quorum=for,abstain`: For and Abstain votes are counted towards quorum.
     * - `params=approvalVote`: params needs to be formatted as `ApprovalVoteParams`.
     */
    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "support=for,abstain&quorum=for,abstain&params=approvalVote";
    }

    /**
     * @notice Module version.
     */
    function version() public pure returns (uint256) {
        return 1;
    }

    // TODO: consider alternatives, or test extensively
    function _sort(uint128[] memory optionVotes, ProposalOption[] memory options)
        internal
        pure
        returns (uint128[] memory, ProposalOption[] memory)
    {
        unchecked {
            uint128 highestValue;
            ProposalOption memory highestOption;
            uint256 index;

            for (uint256 i; i < optionVotes.length - 1; ++i) {
                highestValue = optionVotes[i];

                for (uint256 j = i + 1; j < optionVotes.length; ++j) {
                    if (optionVotes[j] > highestValue) {
                        highestValue = optionVotes[j];
                        index = j;
                    }
                }

                if (index != 0) {
                    optionVotes[index] = optionVotes[i];
                    optionVotes[i] = highestValue;

                    highestOption = options[index];
                    options[index] = options[i];
                    options[i] = highestOption;

                    index = 0;
                }
            }

            return (optionVotes, options);
        }
    }
}

/**
 * GovernorV5
 * - Add tests to verify ProposalCore upgrade safety. Also refactor changes to original OZ contract to make it cleaner.
 */
