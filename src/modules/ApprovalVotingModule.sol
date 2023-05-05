// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VotingModule} from "./VotingModule.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";

contract ApprovalVotingModule is VotingModule {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error MaxApprovalsExceeded();
    error InvalidOption(uint256 option);

    /*//////////////////////////////////////////////////////////////
                               LIBRARIES
    //////////////////////////////////////////////////////////////*/

    using SafeCastLib for uint256;

    /*//////////////////////////////////////////////////////////////
                           IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * Defines the encoding for the expected `proposalData` in `propose`.
     * Encoding: `(ProposalOption[], ProposalSettings)`
     *
     * @dev Can be used by clients to interact with modules programmatically without prior knowledge
     * on expected types.
     */
    string public constant override PROPOSAL_DATA_ENCODING =
        "((address[] targets,uint256[] values,bytes[] calldatas,string description)[] proposalOptions,(uint8 maxApprovals,uint8 criteria,uint112 criteriaValue,uint128 budget) proposalSettings)";

    /**
     * Defines the encoding for the expected `params` in `_countVote`.
     * Encoding: `uint256[]`
     *
     * @dev Can be used by clients to interact with modules programmatically without prior knowledge
     * on expected types.
     */
    string public constant override VOTE_PARAMS_ENCODING = "uint256[] options";

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
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string description;
    }

    struct Proposal {
        address governor;
        uint128[] optionVotes;
        ProposalVotes votes;
        ProposalOption[] options;
        ProposalSettings settings;
    }

    mapping(uint256 proposalId => Proposal) public _proposals;
    mapping(uint256 proposalId => mapping(address account => uint8 votes)) public _accountVotes;

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * Save settings and options for a new proposal.
     *
     * @param proposalId The id of the proposal.
     * @param proposalData The proposal data encoded as `PROPOSAL_DATA_ENCODING`.
     */
    function propose(uint256 proposalId, bytes memory proposalData) external override {
        if (_proposals[proposalId].governor != address(0)) revert ExistingProposal();

        (ProposalOption[] memory proposalOptions, ProposalSettings memory proposalSettings) =
            abi.decode(proposalData, (ProposalOption[], ProposalSettings));

        uint256 optionsLength = proposalOptions.length;
        if (optionsLength == 0 || optionsLength > type(uint8).max) revert InvalidParams();

        unchecked {
            // Ensure proposal params of each option have the same length between themselves
            ProposalOption memory option;
            for (uint256 i; i < optionsLength; ++i) {
                option = proposalOptions[i];
                if (option.targets.length != option.values.length || option.targets.length != option.calldatas.length) {
                    revert InvalidParams();
                }
            }

            // Push proposal options in storage
            for (uint256 i; i < optionsLength; ++i) {
                _proposals[proposalId].options[i] = proposalOptions[i];
            }
        }

        _proposals[proposalId].governor = msg.sender;
        _proposals[proposalId].settings = proposalSettings;
        _proposals[proposalId].optionVotes = new uint128[](optionsLength);
    }

    /**
     * Count approvals voted by `account`.
     *
     * @param proposalId The id of the proposal.
     * @param account The account to count votes for.
     * @param support The type of vote to count. 0 = For, 1 = Abstain.
     * @param weight The weight of the vote.
     * @param params The ids of the options to vote for sorted in ascending order, encoded as `uint256[]`.
     */
    function _countVote(uint256 proposalId, address account, uint8 support, uint256 weight, bytes memory params)
        external
        override
    {
        Proposal memory proposal = _proposals[proposalId];
        _onlyGovernor(proposal.governor);

        if (hasVoted(proposalId, account)) revert VoteAlreadyCast();

        uint128 weight_ = weight.toUint128();

        if (support == uint8(VoteType.For)) {
            uint256[] memory options = abi.decode(params, (uint256[]));
            uint256 totalOptions = options.length;
            if (totalOptions == 0) revert InvalidParams();
            if (totalOptions > proposal.settings.maxApprovals) revert MaxApprovalsExceeded();

            uint256 currOption;
            uint256 prevOption;
            for (uint256 i; i < totalOptions;) {
                currOption = options[i];

                /// @dev Expect options sorted in ascending order
                if (i != 0) {
                    if (currOption <= prevOption) {
                        revert InvalidOption(currOption);
                    }
                }

                prevOption = currOption;

                /// @dev Reverts if `currOption` is out of bounds
                _proposals[proposalId].optionVotes[currOption] += weight_;

                unchecked {
                    ++i;
                }
            }

            /// @dev `totalOptions` cannot overflow uint8 as it is checked against `maxApprovals`
            _accountVotes[proposalId][account] = uint8(totalOptions);
            _proposals[proposalId].votes.forVotes += weight_;
        } else if (support == uint8(VoteType.Abstain)) {
            _accountVotes[proposalId][account] = 1;
            _proposals[proposalId].votes.abstainVotes += weight_;
        } else {
            revert InvalidVoteType();
        }
    }

    /**
     * Format executeParams for a governor, given `proposalId` and `proposalData`.
     *
     * @param proposalId The id of the proposal.
     * @param proposalData The proposal data encoded as `(ProposalOption[], ProposalSettings)`.
     * @return targets The targets of the proposal.
     * @return values The values of the proposal.
     * @return calldatas The calldatas of the proposal.
     */
    function _formatExecuteParams(uint256 proposalId, bytes memory proposalData)
        public
        view
        override
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        _onlyGovernor(_proposals[proposalId].governor);

        (ProposalOption[] memory options, ProposalSettings memory settings) =
            abi.decode(proposalData, (ProposalOption[], ProposalSettings));

        // Sort `options` by `optionVotes` in descending order
        (uint128[] memory optionVotes_, ProposalOption[] memory options_) =
            _sort(_proposals[proposalId].optionVotes, options);

        uint256 executeParamsLength;
        uint256 succeededOptionsLength;

        // Set `executeParamsLength` and `succeededOptionsLength`
        uint256 n = options_.length;
        unchecked {
            uint256 i;
            if (settings.criteria == uint8(PassingCriteria.Threshold)) {
                for (i; i < n; ++i) {
                    if (optionVotes_[i] >= settings.criteriaValue) {
                        executeParamsLength += options_[i].targets.length;
                    } else {
                        break;
                    }
                }
                succeededOptionsLength = i;
            } else if (settings.criteria == uint8(PassingCriteria.TopChoices)) {
                for (i; i < n; ++i) {
                    if (succeededOptionsLength < settings.criteriaValue) {
                        executeParamsLength += options_[i].targets.length;
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
            option = options_[i];
            optionTargetsLength = option.targets.length;
            for (n; n < optionTargetsLength;) {
                optionValue = option.values[n];
                totalValue += optionValue;

                // Shortcircuit if the budget is exceeded
                if (settings.budget != 0) {
                    // TODO: consider budget is in OP
                    if (totalValue > settings.budget) {
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
     * @dev Return true if `account` has cast a vote for `proposalId`.
     *
     * @param proposalId The id of the proposal.
     * @param account The address of the account.
     */
    function hasVoted(uint256 proposalId, address account) public view override returns (bool) {
        return _accountVotes[proposalId][account] != 0;
    }

    /**
     * @dev Return for, abstain and option votes for a `proposalId`.
     *
     * @param proposalId The id of the proposal.
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
     *
     * @param proposalId The id of the proposal.
     * @param quorum The quorum value at the proposal start block.
     */
    function _quorumReached(uint256 proposalId, uint256 quorum) external view override returns (bool) {
        _onlyGovernor(_proposals[proposalId].governor);
        ProposalVotes memory votes = _proposals[proposalId].votes;

        return quorum <= votes.forVotes + votes.abstainVotes;
    }

    /**
     * @dev Return true if at least one option satisfies the passing criteria.
     * Used by governor in `_voteSucceeded`. See {Governor-_voteSucceeded}.
     *
     * @param proposalId The id of the proposal.
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
     * - `params=approvalVote`: params needs to be formatted as `VOTE_PARAMS_ENCODING`.
     */
    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "support=for,abstain&quorum=for,abstain&params=approvalVote";
    }

    /**
     * Module version.
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
