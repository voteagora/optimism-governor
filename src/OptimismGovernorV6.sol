// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OptimismGovernorV5} from "./OptimismGovernorV5.sol";
import {IVotableSupplyOracle} from "./interfaces/IVotableSupplyOracle.sol";
import {VotingModule} from "./modules/VotingModule.sol";
import {GovernorVotesQuorumFractionUpgradeableV2} from
    "./lib/openzeppelin/v2/GovernorVotesQuorumFractionUpgradeableV2.sol";
import {GovernorCountingSimpleUpgradeableV2} from "./lib/openzeppelin/v2/GovernorCountingSimpleUpgradeableV2.sol";
import {IGovernorUpgradeable} from "./lib/openzeppelin/v2/GovernorUpgradeableV2.sol";
import {TimersUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/TimersUpgradeable.sol";

/**
 * Modifications from OptimismGovernorV5
 * - Adds support for partial voting, only via Alligator
 */
contract OptimismGovernorV6 is OptimismGovernorV5 {
    /*//////////////////////////////////////////////////////////////
                               LIBRARIES
    //////////////////////////////////////////////////////////////*/

    using TimersUpgradeable for TimersUpgradeable.BlockNumber;

    /*//////////////////////////////////////////////////////////////
                           IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 private constant GOVERNOR_VERSION = 1;

    // Max value of `VoteType` enum
    uint8 internal constant MAX_VOTE_TYPE = 2;

    // TODO: Set correct alligator address
    address public constant alligator = 0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9;

    // TODO: Set correct votableSupplyOracle address
    IVotableSupplyOracle public constant votableSupplyOracle = IVotableSupplyOracle(address(1));

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * Total number of `votes` that `account` has cast for `proposalId`.
     * @dev Replaces non-quantitative `_proposalVotes.hasVoted` to add support for partial voting.
     */
    mapping(uint256 proposalId => mapping(address account => uint256 votes)) public weightCast;

    /*//////////////////////////////////////////////////////////////
                               ALLIGATOR
    //////////////////////////////////////////////////////////////*/

    modifier onlyAlligator() {
        if (msg.sender != alligator) revert("Unauthorized");
        _;
    }

    /**
     * @dev Count `votes` for `account` on `proposalId` and update `weightCast`.
     * Reverts if `votes` exceeds the remaining weight of `account` on `proposalId`.
     *
     * @param proposalId The id of the proposal to vote on
     * @param account The address for which to count votes for, the proxy
     * @param votes The number of votes to count
     * @param accountVotes The total number of votes delegated to `account`
     */
    function increaseWeightCast(uint256 proposalId, address account, uint256 votes, uint256 accountVotes)
        external
        onlyAlligator
    {
        require((weightCast[proposalId][account] += votes) <= accountVotes, "Governor: total weight exceeded");
    }

    /**
     * @dev Cast a vote assuming `alligator` is sending the correct voting power, has recorded weight cast
     * for proxy addresses and has done the necessary checks.
     *
     * @param proposalId The id of the proposal to vote on
     * @param voter The address who cast the vote on behalf of the proxy
     * @param support The support of the vote, `0` for against and `1` for for
     * @param reason The reason given for the vote by the voter
     * @param votes The number of votes to count
     * @param params The params for the vote
     */
    function castVoteFromAlligator(
        uint256 proposalId,
        address voter,
        uint8 support,
        string memory reason,
        uint256 votes,
        bytes calldata params
    ) external onlyAlligator {
        require(state(proposalId) == ProposalState.Active, "Governor: vote not currently active");

        // Skip `totalWeight` check and count `votes`
        ProposalVote storage proposalVote = _proposalVotes[proposalId];

        if (support == uint8(VoteType.Against)) {
            proposalVote.againstVotes += votes;
        } else if (support == uint8(VoteType.For)) {
            proposalVote.forVotes += votes;
        } else if (support == uint8(VoteType.Abstain)) {
            proposalVote.abstainVotes += votes;
        } else {
            revert("GovernorVotingSimple: invalid value for enum VoteType");
        }

        address votingModule = _proposals[proposalId].votingModule;

        if (votingModule != address(0)) {
            VotingModule(votingModule)._countVote(proposalId, voter, support, votes, params);
        }

        /// @dev `voter` is emitted in the event instead of `proxy`
        emit VoteCastWithParams(voter, proposalId, support, votes, reason, params);
    }

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Updated internal vote casting mechanism which delegates counting logic to voting module,
     * in addition to executing standard `_countVote`. See {IGovernor-_castVote}.
     */
    function _castVote(uint256 proposalId, address account, uint8 support, string memory reason, bytes memory params)
        internal
        virtual
        override
        returns (uint256)
    {
        require(state(proposalId) == ProposalState.Active, "Governor: vote not currently active");

        uint256 weight = _getVotes(account, _proposals[proposalId].voteStart.getDeadline(), "");

        _countVote(proposalId, account, support, weight, params);

        address votingModule = _proposals[proposalId].votingModule;

        if (votingModule != address(0)) {
            VotingModule(votingModule)._countVote(proposalId, account, support, weight, params);
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
     * Returns the quorum for a block number, in terms of number of votes: `supply * numerator / denominator`.
     *
     * @dev Based on `votableSupply` by default, but falls back to `totalSupply` if not available.
     */
    function quorum(uint256 blockNumber)
        public
        view
        virtual
        override(GovernorVotesQuorumFractionUpgradeableV2, IGovernorUpgradeable)
        returns (uint256)
    {
        uint256 supply = votableSupplyOracle.votableSupply(blockNumber);

        // Fallback to total supply if votable supply was unset at `blockNumber`
        if (supply == 0) {
            supply = token.getPastTotalSupply(blockNumber);
        }

        return (supply * quorumNumerator(blockNumber)) / quorumDenominator();
    }

    /**
     * Add support for `weightCast` to check if `account` has voted on `proposalId`.
     */
    function hasVoted(uint256 proposalId, address account)
        public
        view
        virtual
        override(GovernorCountingSimpleUpgradeableV2, IGovernorUpgradeable)
        returns (bool)
    {
        return weightCast[proposalId][account] != 0 || _proposalVotes[proposalId].hasVoted[account];
    }

    /**
     * Params encoding:
     * - modules = custom external params depending on module used
     */
    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "support=bravo&quorum=against,for,abstain&params=modules";
    }

    /**
     * @dev Returns the current version of the governor.
     */
    function VERSION() public pure virtual returns (uint256) {
        return GOVERNOR_VERSION;
    }
}
