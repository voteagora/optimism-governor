// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ApprovalVotingModule, Proposal, VoteType} from "./ApprovalVotingModule.sol";
import {FractionalVotingModule} from "./FractionalVotingModule.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";
import {EnumerableSetUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

contract FractionalApprovalVotingModule is ApprovalVotingModule, FractionalVotingModule {
    /*//////////////////////////////////////////////////////////////
                               LIBRARIES
    //////////////////////////////////////////////////////////////*/

    using SafeCastLib for uint256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 proposalId => mapping(address account => EnumerableSetUpgradeable.UintSet votes)) private
        accountVotesSet;

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS 
    //////////////////////////////////////////////////////////////*/

    /**
     * Count approvals voted by `account`. If voting for, options need to be set in ascending order.
     * @dev Revoting is allowed via partial voting.
     *
     * @param proposalId The id of the proposal.
     * @param account The account to count votes for.
     * @param support The type of vote to count.
     * @param totalWeight The total vote weight of the `account`.
     * @param params The ids of the options to vote for sorted in ascending order, encoded as `uint256[]`.
     * @param voter The account that casted the vote, used with partial voting from alligator.
     */
    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 totalWeight,
        bytes calldata params,
        address voter
    ) external override {
        Proposal memory proposal = proposals[proposalId];
        _onlyGovernor(proposal.governor);

        (, uint256 forVotes,, uint256[] memory options) = abi.decode(params, (uint256, uint256, uint256, uint256[]));

        // Record votes only if weight is not 0
        if ((totalWeight != 0 && support == uint8(VoteType.For)) || forVotes != 0) {
            uint256 totalOptions = options.length;
            if (totalOptions == 0) revert InvalidParams();

            // Derive `weight` from `forVotes` when partial voting is used, otherwise use `totalWeight`
            uint128 weight = (forVotes != 0 ? forVotes : totalWeight).toUint128();

            // Use `voter` as `account` when partial voting is used, otherwise use `account`
            account = voter != address(0) ? voter : account;

            _recordVote(proposalId, account, weight, options, totalOptions, proposal.settings.maxApprovals);
        }
    }

    function _recordVote(
        uint256 proposalId,
        address account,
        uint128 weight,
        uint256[] memory options,
        uint256 totalOptions,
        uint256 maxApprovals
    ) internal {
        uint256 option;
        uint256 prevOption;
        for (uint256 i; i < totalOptions;) {
            option = options[i];

            accountVotesSet[proposalId][account].add(option);

            // Revert if `option` is not strictly ascending
            if (i != 0) {
                if (option <= prevOption) revert OptionsNotStrictlyAscending();
            }

            prevOption = option;

            /// @dev Revert if `option` is out of bounds
            proposals[proposalId].optionVotes[option] += weight;

            unchecked {
                ++i;
            }
        }

        if (accountVotesSet[proposalId][account].length() > maxApprovals) {
            revert MaxApprovalsExceeded();
        }
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * Return the ids of the options voted by `account` on `proposalId`.
     */
    function getAccountVotes(uint256 proposalId, address account) external view returns (uint256[] memory) {
        return accountVotesSet[proposalId][account].values();
    }

    /**
     * Return the total number of votes cast by `account` on `proposalId`.
     */
    function getAccountTotalVotes(uint256 proposalId, address account) external view returns (uint256) {
        return accountVotesSet[proposalId][account].length();
    }

    /**
     * Defines the encoding for the expected `params` in `_countVote`.
     * Encoding: `uint256,uint256,uint256,uint256[]`
     *
     * @dev Can be used by clients to interact with modules programmatically without prior knowledge
     * on expected types.
     */
    function VOTE_PARAMS_ENCODING() external pure virtual override returns (string memory) {
        return "uint256 againstVotes,uint256 forVotes,uint256 abstainVotes,uint256[] optionIds";
    }

    /**
     * @dev See {IGovernor-COUNTING_MODE}.
     *
     * - `support=bravo`: Supports vote options 0 = Against, 1 = For, 2 = Abstain, as in `GovernorBravo`.
     * - `quorum=for,abstain`: Against, For and Abstain votes are counted towards quorum.
     * - `params=fractional,approvalVote`: params needs to be formatted as `VOTE_PARAMS_ENCODING`.
     */
    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "support=bravo&quorum=against,for,abstain&params=fractional,approvalVote";
    }
}
