// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VotingModule} from "./VotingModule.sol";

contract ApprovalVotingModule is VotingModule {
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

    struct ApprovalVotingParams {
        ProposalOption[] options;
        ProposalSettings settings;
    }

    mapping(uint256 proposalId => Proposal) public _proposals;
    mapping(uint256 proposalId => mapping(address account => uint8)) public _approvals;

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function propose(uint256 proposalId, bytes memory proposalData) external override {
        require(_proposals[proposalId].governor == address(0), "VotingModule: proposal already exists");

        ApprovalVotingParams memory params = abi.decode(proposalData, (ApprovalVotingParams));

        uint256 optionsLength = params.options.length;
        require(optionsLength != 0, "VotingModule: invalid proposal length");

        unchecked {
            // Ensure proposal params of each option have the same length between themselves
            ProposalOption memory option;
            for (uint256 i; i < optionsLength; ++i) {
                option = params.options[i];
                require(option.targets.length == option.values.length, "VotingModule: invalid proposal length");
                require(option.targets.length == option.calldatas.length, "VotingModule: invalid proposal length");
            }

            // Push proposal options in storage
            for (uint256 i; i < optionsLength; ++i) {
                _proposals[proposalId].options.push(params.options[i]);
            }
        }

        _proposals[proposalId].governor = msg.sender;
        _proposals[proposalId].settings = params.settings;
        _proposals[proposalId].optionVotes = new uint128[](optionsLength); // TODO: check if it can be removed
    }

    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params,
        uint256 weight
    ) external override {
        Proposal memory proposal = _proposals[proposalId];
        _onlyGovernor(proposal.governor);

        // TODO: TO DEFINE
        require(!hasVoted(proposalId, account), "GovernorVotingSimple: vote already cast");

        // if (support == uint8(VoteType.Against)) {
        //     proposalVote.againstVotes += weight.toUint128();
        // } else if (support == uint8(VoteType.For)) {
        //     proposalVote.forVotes += weight.toUint128();
        // } else if (support == uint8(VoteType.Abstain)) {
        //     proposalVote.abstainVotes += weight.toUint96();
        // } else {
        //     revert("GovernorVotingSimple: invalid value for enum VoteType");
        // }

        _approvals[proposalId][account] += 1;
    }

    function _formatExecuteParams(uint256 proposalId, bytes memory proposalData)
        public
        view
        override
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        _onlyGovernor(_proposals[proposalId].governor);

        ApprovalVotingParams memory params = abi.decode(proposalData, (ApprovalVotingParams));

        // Sort `options` by `optionVotes` in descending order
        (uint128[] memory optionVotes, ProposalOption[] memory options) =
            _sort(_proposals[proposalId].optionVotes, params.options);

        uint256 executeParamsLength;
        uint256 succeededOptionsLength;

        // Set `executeParamsLength` and `succeededOptionsLength`
        uint256 n = options.length;
        unchecked {
            if (params.settings.criteria == uint8(PassingCriteria.Threshold)) {
                for (uint256 i; i < n; ++i) {
                    if (optionVotes[i] >= params.settings.criteriaValue) {
                        executeParamsLength += options[i].targets.length;
                        ++succeededOptionsLength;
                    } else {
                        break;
                    }
                }
            } else if (params.settings.criteria == uint8(PassingCriteria.TopChoices)) {
                for (uint256 i; i < n; ++i) {
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

    function hasVoted(uint256 proposalId, address account) public view override returns (bool) {
        return _approvals[proposalId][account] != 0;
    }

    /**
     * @dev Accessor to the internal vote counts.
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
        // TODO: Check if by reading only 2 slots (governor + params) we save gas compared to getting all `proposal`
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
     * - `support=bravo`: the vote options are 1 = For, 2 = Abstain. TODO: TBD
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

    // TODO: Test, or directly optimize
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
 *
 *
 * GovernorV5
 * - Add tests to verify ProposalCore upgrade safety. Also refactor changes to original OZ contract to make it cleaner.
 */
