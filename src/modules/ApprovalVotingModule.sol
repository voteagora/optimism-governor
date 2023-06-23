// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VotingModule} from "./VotingModule.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";

enum VoteType {
    Against,
    For,
    Abstain
}

enum PassingCriteria {
    Threshold,
    TopChoices
}

struct ExecuteParams {
    address targets;
    uint256 values;
    bytes calldatas;
}

struct ProposalSettings {
    uint8 maxApprovals;
    uint8 criteria;
    address budgetToken;
    uint128 criteriaValue;
    uint128 budgetAmount;
}

struct ProposalOption {
    uint256 budgetTokensSpent;
    address[] targets;
    uint256[] values;
    bytes[] calldatas;
    string description;
}

struct Proposal {
    address governor;
    uint256 initBalance;
    uint128[] optionVotes;
    ProposalOption[] options;
    ProposalSettings settings;
}

contract ApprovalVotingModule is VotingModule {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error WrongProposalId();
    error MaxChoicesExceeded();
    error MaxApprovalsExceeded();
    error BudgetExceeded();
    error OptionsNotStrictlyAscending();

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
        "((uint256 budgetTokensSpent,address[] targets,uint256[] values,bytes[] calldatas,string description)[] proposalOptions,(uint8 maxApprovals,uint8 criteria,address budgetToken,uint128 criteriaValue,uint128 budgetAmount) proposalSettings)";

    /**
     * Defines the encoding for the expected `params` in `_countVote`.
     * Encoding: `uint256[]`
     *
     * @dev Can be used by clients to interact with modules programmatically without prior knowledge
     * on expected types.
     */
    string public constant override VOTE_PARAMS_ENCODING = "uint256[] optionIds";

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 proposalId => Proposal) public proposals;
    mapping(uint256 proposalId => mapping(address account => uint256 votes)) public accountVotes;

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * Save settings and options for a new proposal.
     *
     * @param proposalId The id of the proposal.
     * @param proposalData The proposal data encoded as `PROPOSAL_DATA_ENCODING`.
     */
    function propose(uint256 proposalId, bytes memory proposalData, bytes32 descriptionHash) external override {
        if (proposalId != uint256(keccak256(abi.encode(msg.sender, address(this), proposalData, descriptionHash)))) {
            revert WrongProposalId();
        }

        if (proposals[proposalId].governor != address(0)) revert ExistingProposal();

        (ProposalOption[] memory proposalOptions, ProposalSettings memory proposalSettings) =
            abi.decode(proposalData, (ProposalOption[], ProposalSettings));

        uint256 optionsLength = proposalOptions.length;
        if (optionsLength == 0 || optionsLength > type(uint8).max) revert InvalidParams();
        if (proposalSettings.criteria == uint8(PassingCriteria.TopChoices)) {
            if (proposalSettings.criteriaValue > optionsLength) revert MaxChoicesExceeded();
        }

        unchecked {
            // Ensure proposal params of each option have the same length between themselves
            ProposalOption memory option;
            for (uint256 i; i < optionsLength; ++i) {
                option = proposalOptions[i];
                if (option.targets.length != option.values.length || option.targets.length != option.calldatas.length) {
                    revert InvalidParams();
                }

                proposals[proposalId].options.push(option);
            }
        }

        proposals[proposalId].governor = msg.sender;
        proposals[proposalId].settings = proposalSettings;
        proposals[proposalId].optionVotes = new uint128[](optionsLength);
    }

    /**
     * Count approvals voted by `account`. If voting for, options need to be set in ascending order. Votes can only be cast once.
     *
     * @param proposalId The id of the proposal.
     * @param account The account to count votes for.
     * @param support The type of vote to count.
     * @param weight The weight of the vote.
     * @param params The ids of the options to vote for sorted in ascending order, encoded as `uint256[]`.
     */
    function _countVote(uint256 proposalId, address account, uint8 support, uint256 weight, bytes memory params)
        external
        override
    {
        Proposal memory proposal = proposals[proposalId];
        _onlyGovernor(proposal.governor);
        if (accountVotes[proposalId][account] != 0) revert AlreadyVoted();

        if (support == uint8(VoteType.For)) {
            uint256[] memory options = abi.decode(params, (uint256[]));
            uint256 totalOptions = options.length;
            if (totalOptions == 0) revert InvalidParams();
            if (totalOptions > proposal.settings.maxApprovals) revert MaxApprovalsExceeded();

            uint128 weight_ = weight.toUint128();
            uint256 option;
            uint256 prevOption;
            for (uint256 i; i < totalOptions;) {
                option = options[i];

                // Revert if `option` is not strictly ascending
                if (i != 0) {
                    if (option <= prevOption) revert OptionsNotStrictlyAscending();
                }

                prevOption = option;

                /// @dev Revert if `option` is out of bounds
                proposals[proposalId].optionVotes[option] += weight_;

                unchecked {
                    ++i;
                }
            }

            accountVotes[proposalId][account] = totalOptions;
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
        override
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        address governor = proposals[proposalId].governor;
        _onlyGovernor(governor);

        (ProposalOption[] memory options, ProposalSettings memory settings) =
            abi.decode(proposalData, (ProposalOption[], ProposalSettings));

        // If budgetToken is not ETH
        if (settings.budgetToken != address(0)) {
            // Save initBalance to be used as comparison in `_afterExecute`
            proposals[proposalId].initBalance = IERC20(settings.budgetToken).balanceOf(governor);
        }

        (uint128[] memory sortedOptionVotes, ProposalOption[] memory sortedOptions) =
            _sortOptions(proposals[proposalId].optionVotes, options);

        (uint256 executeParamsLength, uint256 succeededOptionsLength) =
            _countOptions(sortedOptions, sortedOptionVotes, settings);

        ExecuteParams[] memory executeParams = new ExecuteParams[](executeParamsLength);
        executeParamsLength = 0;
        uint256 n;
        uint256 totalValue;
        ProposalOption memory option;

        // Flatten `options` by filling `executeParams` until budgetAmount is exceeded
        for (uint256 i; i < succeededOptionsLength;) {
            option = sortedOptions[i];

            for (n = 0; n < option.targets.length;) {
                // Shortcircuit if `budgetAmount` is exceeded
                if (settings.budgetAmount != 0) {
                    if (settings.budgetToken == address(0)) {
                        // If `budgetToken` is ETH and value is not zero, add msg value to `totalValue`
                        if (option.values[n] != 0) totalValue += option.values[n];
                    }

                    // Break loop if `budgetAmount` is exceeded
                    if (totalValue > settings.budgetAmount) break;
                }

                unchecked {
                    executeParams[executeParamsLength + n] =
                        ExecuteParams(option.targets[n], option.values[n], option.calldatas[n]);

                    ++n;
                }
            }

            if (settings.budgetAmount != 0) {
                // If `budgetToken` is not ETH and `option.budgetAmount` is not zero, add amount to `totalValue`
                if (settings.budgetToken != address(0)) {
                    if (option.budgetTokensSpent != 0) totalValue += option.budgetTokensSpent;
                }

                // Break loop if `budgetAmount` is exceeded
                if (totalValue > settings.budgetAmount) break;
            }

            unchecked {
                executeParamsLength += n;

                ++i;
            }
        }

        // Init param lengths based on the `n` passed elements
        targets = new address[](executeParamsLength);
        values = new uint256[](executeParamsLength);
        calldatas = new bytes[](executeParamsLength);

        // Set n `targets`, `values` and `calldatas`
        for (uint256 i; i < executeParamsLength;) {
            targets[i] = executeParams[i].targets;
            values[i] = executeParams[i].values;
            calldatas[i] = executeParams[i].calldatas;

            unchecked {
                ++i;
            }
        }
    }

    /**
     * Hook called by a governor after execute, for `proposalId` with `proposalData`.
     * Revert if the transaction has resulted in more tokens being spent than `budgetAmount`.
     *
     * @param proposalId The id of the proposal.
     * @param proposalData The proposal data encoded as `(ProposalOption[], ProposalSettings)`.
     */
    function _afterExecute(uint256 proposalId, bytes memory proposalData) public view override {
        (, ProposalSettings memory settings) = abi.decode(proposalData, (ProposalOption[], ProposalSettings));

        if (settings.budgetToken != address(0)) {
            address governor = proposals[proposalId].governor;

            if (
                proposals[proposalId].initBalance - IERC20(settings.budgetToken).balanceOf(governor)
                    > settings.budgetAmount
            ) revert BudgetExceeded();
        }
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Return true if at least one option satisfies the passing criteria.
     * Used by governor in `_voteSucceeded`. See {Governor-_voteSucceeded}.
     *
     * @param proposalId The id of the proposal.
     */
    function _voteSucceeded(uint256 proposalId) external view override returns (bool) {
        Proposal memory proposal = proposals[proposalId];

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
     * - `support=bravo`: Supports vote options 0 = Against, 1 = For, 2 = Abstain, as in `GovernorBravo`.
     * - `quorum=for,abstain`: Against, For and Abstain votes are counted towards quorum.
     * - `params=approvalVote`: params needs to be formatted as `VOTE_PARAMS_ENCODING`.
     */
    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "support=bravo&quorum=against,for,abstain&params=approvalVote";
    }

    /**
     * Module version.
     */
    function version() public pure returns (uint256) {
        return 1;
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    // Sort `options` by `optionVotes` in descending order
    function _sortOptions(uint128[] memory optionVotes, ProposalOption[] memory options)
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

    // Derive `executeParamsLength` and `succeededOptionsLength` based on passing criteria
    function _countOptions(
        ProposalOption[] memory options,
        uint128[] memory optionVotes,
        ProposalSettings memory settings
    ) internal pure returns (uint256 executeParamsLength, uint256 succeededOptionsLength) {
        uint256 n = options.length;
        unchecked {
            uint256 i;
            if (settings.criteria == uint8(PassingCriteria.Threshold)) {
                // if criteria is `Threshold`, loop through options until `optionVotes` is less than threshold
                for (i; i < n; ++i) {
                    if (optionVotes[i] >= settings.criteriaValue) {
                        executeParamsLength += options[i].targets.length;
                    } else {
                        break;
                    }
                }
            } else if (settings.criteria == uint8(PassingCriteria.TopChoices)) {
                // if criteria is `TopChoices`, loop through options until the top choices are filled
                for (i; i < settings.criteriaValue; ++i) {
                    executeParamsLength += options[i].targets.length;
                }
            }
            succeededOptionsLength = i;
        }
    }
}
