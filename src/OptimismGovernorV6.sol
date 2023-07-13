// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OptimismGovernorV5} from "./OptimismGovernorV5.sol";
import {VotingModule, FractionalVotingModule} from "./modules/FractionalVotingModule.sol";
import {GovernorCountingSimpleUpgradeableV2} from "./lib/openzeppelin/v2/GovernorCountingSimpleUpgradeableV2.sol";
import {GovernorVotesQuorumFractionUpgradeableV2} from
    "./lib/openzeppelin/v2/GovernorVotesQuorumFractionUpgradeableV2.sol";
import {GovernorUpgradeableV2, IGovernorUpgradeable} from "./lib/openzeppelin/v2/GovernorUpgradeableV2.sol";
import {ECDSAUpgradeable} from "./lib/openzeppelin/ECDSAUpgradeable.sol";
import {SignatureCheckerUpgradeable} from "./lib/openzeppelin/SignatureCheckerUpgradeable.sol";
import {TimersUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/TimersUpgradeable.sol";

/**
 * - Adds support for fractional voting
 * - Deprecate old version of `castVoteWithReasonAndParamsBySig` and add new version with `voter`, `signature` and `nonce`.
 * - Adds support for votable supply oracle
 */
contract OptimismGovernorV6 is OptimismGovernorV5 {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * Modified version of `VoteCastWithParams` which includes `voter` address.
     */
    event VoteCastWithParams(
        address account, uint256 proposalId, uint8 support, uint256 weight, string reason, bytes params, address voter
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev The provided signature is not valid for the expected `voter`.
     * If the `voter` is a contract, the signature is not valid using {IERC1271-isValidSignature}.
     */
    error GovernorInvalidSignature(address voter);

    /// Thrown when a module does not support fractional voting.
    error FractionalVotingNotSupported(address module);

    /*//////////////////////////////////////////////////////////////
                               LIBRARIES
    //////////////////////////////////////////////////////////////*/

    using TimersUpgradeable for TimersUpgradeable.BlockNumber;

    /*//////////////////////////////////////////////////////////////
                           IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    // Max value of `VoteType` enum
    uint8 internal constant MAX_VOTE_TYPE = 2;

    uint256 internal constant MASK_HALF_WORD_RIGHT = 0xffffffffffffffffffffffffffffffff;

    uint256 internal constant ORACLE_DEPLOY_BLOCKNUMBER = 0;

    address public immutable alligator;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address account => uint256 nonce) private _nonces;

    /**
     * Total number of `votes` that `account` has cast for `proposalId`.
     * @dev Replaces non-quantitative `_proposalVotes.hasVoted` to add support for fractional voting.
     */
    mapping(uint256 proposalId => mapping(address account => uint256 votes)) public weightCast;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address alligator_) {
        alligator = alligator_;
    }

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * Add check to ensure the used `module` supports fractional voting.
     */
    function proposeWithModule(VotingModule module, bytes memory proposalData, string memory description)
        public
        override
        returns (uint256)
    {
        if (!FractionalVotingModule(address(module)).supportsFractionaVoting()) {
            revert FractionalVotingNotSupported(address(module));
        }

        return super.proposeWithModule(module, proposalData, description);
    }

    /**
     * @dev Updated internal vote casting mechanism which delegates counting logic to voting module,
     * in addition to executing standard `_countVote`. See {IGovernor-_castVote}.
     */
    function _castVote(uint256 proposalId, address account, uint8 support, string memory reason, bytes memory params)
        internal
        override
        returns (uint256)
    {
        ProposalCore memory proposal = _proposals[proposalId];
        require(state(proposalId) == ProposalState.Active, "Governor: vote not currently active");

        uint256 weight = _getVotes(account, proposal.voteStart.getDeadline(), "");

        _countVote(proposalId, account, support, weight, params);

        address voter;
        if (account == alligator) {
            // Derive `voter` from address appended in `params`
            assembly {
                // TODO: Test if correct
                // TODO: Add append to alligator
                /// @dev no need to clean dirty bytes as they are sent already cleaned by alligator
                voter := mload(add(params, sub(mload(params), 0x20)))
            }
        }

        if (proposal.votingModule != address(0)) {
            FractionalVotingModule(proposal.votingModule)._countVote(
                proposalId, account, support, weight, params, voter
            );
        }

        if (params.length == 0) {
            emit VoteCast(account, proposalId, support, weight, reason);
        } else {
            emit VoteCastWithParams(account, proposalId, support, weight, reason, params, voter);
        }

        return weight;
    }

    /**
     * See {Governor-_countVote}.
     *
     * @dev If `params` is empty, or the first 96 bytes corresponding to `againstVotes`, `forVotes` or `abstainVotes`
     * are 0, then standard nominal voting is used. Otherwise Fractional voting is used.
     */
    function _countVote(uint256 proposalId, address account, uint8 support, uint256 totalWeight, bytes memory params)
        internal
        virtual
        override(GovernorCountingSimpleUpgradeableV2, GovernorUpgradeableV2)
    {
        uint256 againstVotes;
        uint256 forVotes;
        uint256 abstainVotes;

        if (params.length != 0) {
            /// @dev we decode voting data from the first 96 bytes of `params`
            (againstVotes, forVotes, abstainVotes) = abi.decode(params, (uint256, uint256, uint256));
        }

        if (againstVotes == 0 && forVotes == 0 && abstainVotes == 0) {
            _countVoteNominal(proposalId, account, totalWeight, support);
        } else {
            _countVoteFractional(proposalId, account, totalWeight, againstVotes, forVotes, abstainVotes);
        }
    }

    /**
     * @dev Count votes with full weight cast for `support`. This is the standard voting behaviour.
     */
    function _countVoteNominal(uint256 proposalId, address account, uint256 totalWeight, uint8 support) internal {
        require(!hasVoted(proposalId, account), "Governor: vote already cast");

        if (totalWeight != 0) {
            weightCast[proposalId][account] = totalWeight;
            ProposalVote storage proposalVote = _proposalVotes[proposalId];

            if (support == uint8(VoteType.Against)) {
                proposalVote.againstVotes += totalWeight;
            } else if (support == uint8(VoteType.For)) {
                proposalVote.forVotes += totalWeight;
            } else if (support == uint8(VoteType.Abstain)) {
                proposalVote.abstainVotes += totalWeight;
            } else {
                revert("GovernorVotingSimple: invalid value for enum VoteType");
            }
        } else {
            if (support > MAX_VOTE_TYPE) {
                revert("GovernorVotingSimple: invalid value for enum VoteType");
            }

            // Set flag to prevent `account` from revoting with null weight
            _proposalVotes[proposalId].hasVoted[account] = true;
        }
    }

    /**
     * Count votes with fractional weight.
     *
     * @dev The sum of the three vote weights must be less than or equal to the
     * delegate's remaining weight on the proposal
     * @dev This function can be called multiple times for the same `account` and
     * `proposalId`
     * @dev Partial votes are still final once cast and cannot be modified
     */
    function _countVoteFractional(
        uint256 proposalId,
        address account,
        uint256 totalWeight,
        uint256 againstVotes,
        uint256 forVotes,
        uint256 abstainVotes
    ) internal {
        require(
            (weightCast[proposalId][account] += againstVotes + forVotes + abstainVotes) <= totalWeight,
            "Governor: total weight exceeded"
        );

        ProposalVote storage proposalVote = _proposalVotes[proposalId];

        if (againstVotes != 0) proposalVote.againstVotes += againstVotes;
        if (forVotes != 0) proposalVote.forVotes += forVotes;
        if (abstainVotes != 0) proposalVote.abstainVotes += abstainVotes;
    }

    /**
     * Deprecate current version of `castVoteWithReasonAndParamsBySig` to prevent
     * signature replayability with partial voting.
     */
    function castVoteWithReasonAndParamsBySig(
        uint256, /* proposalId */
        uint8, /* support */
        string calldata, /* reason */
        bytes memory, /* params */
        uint8, /* v */
        bytes32, /* r */
        bytes32 /* s */
    ) public virtual override returns (uint256) {
        revert("unsupported");
    }

    /**
     * @dev Track nonce for `voter` to prevent replayed signatures.
     * @dev See {IGovernor-castVoteWithReasonAndParamsBySig}.
     */
    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint8 support,
        address voter,
        string calldata reason,
        bytes memory params,
        bytes memory signature
    ) public virtual returns (uint256) {
        bool valid = SignatureCheckerUpgradeable.isValidSignatureNow(
            voter,
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        EXTENDED_BALLOT_TYPEHASH,
                        proposalId,
                        support,
                        voter,
                        _useNonce(voter),
                        keccak256(bytes(reason)),
                        keccak256(params)
                    )
                )
            ),
            signature
        );

        if (!valid) {
            revert GovernorInvalidSignature(voter);
        }

        return _castVote(proposalId, voter, support, reason, params);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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
     * - fractional [0..95] = (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes)
     * - modules [96..] = custom external module params
     */
    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "support=bravo&quorum=against,for,abstain&params=fractional,modules";
    }

    /*//////////////////////////////////////////////////////////////
                                NONCE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns an the next unused nonce for an address. See {NoncesUpgradeable}.
     */
    function nonces(address owner) public view virtual returns (uint256) {
        return _nonces[owner];
    }

    /**
     * @dev Consumes a nonce. See {NoncesUpgradeable}.
     *
     * Returns the current value and increments nonce.
     */
    function _useNonce(address owner) internal virtual returns (uint256) {
        // For each account, the nonce has an initial value of 0, can only be incremented by one, and cannot be
        // decremented or reset. This guarantees that the nonce never overflows.
        unchecked {
            // It is important to do x++ and not ++x here.
            return _nonces[owner]++;
        }
    }
}

/**
 * TODO: tests for castVote scenarios
 *
 * User
 * - full standard (0 weight) -> ""
 * - full standard -> ""
 * - full module (0 weight) -> (fractional),module
 * - full module -> (fractional),module
 *
 * Alligator
 * - partial standard (0 weight) -> "" [TODO: DISALLOW ON ALLIGATOR!!] intent-votes should only be used directly from voter address
 * - partial standard -> fractional
 * - partial module (0 weight) -> (fractional),module [TODO: DISALLOW ON ALLIGATOR!!] otherwise alligator would vote with
 * - partial module -> fractional,module
 */
