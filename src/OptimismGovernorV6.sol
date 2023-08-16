// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OptimismGovernorV5} from "./OptimismGovernorV5.sol";
import {VotingModule, PartialVotingModule} from "./modules/PartialVotingModule.sol";
import {GovernorCountingSimpleUpgradeableV2} from "./lib/openzeppelin/v2/GovernorCountingSimpleUpgradeableV2.sol";
import {GovernorVotesQuorumFractionUpgradeableV2} from
    "./lib/openzeppelin/v2/GovernorVotesQuorumFractionUpgradeableV2.sol";
import {GovernorUpgradeableV2, IGovernorUpgradeable} from "./lib/openzeppelin/v2/GovernorUpgradeableV2.sol";
import {ECDSAUpgradeable} from "./lib/openzeppelin/ECDSAUpgradeable.sol";
import {SignatureCheckerUpgradeable} from "./lib/openzeppelin/SignatureCheckerUpgradeable.sol";
import {TimersUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/TimersUpgradeable.sol";

/**
 * - Adds support for partial voting
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

    /// Thrown when a module does not support partial voting.
    error PartialVotingNotSupported(address module);

    /*//////////////////////////////////////////////////////////////
                               LIBRARIES
    //////////////////////////////////////////////////////////////*/

    using TimersUpgradeable for TimersUpgradeable.BlockNumber;

    /*//////////////////////////////////////////////////////////////
                           IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    // Max value of `VoteType` enum
    uint8 internal constant MAX_VOTE_TYPE = 2;

    // TODO: Add alligator address
    address public constant alligator = address(0);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address account => uint256 nonce) private _nonces;

    /**
     * Total number of `votes` that `account` has cast for `proposalId`.
     * @dev Replaces non-quantitative `_proposalVotes.hasVoted` to add support for partial voting.
     */
    mapping(uint256 proposalId => mapping(address account => uint256 votes)) public weightCast;

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * Add check to ensure the used `module` supports partial voting.
     */
    function proposeWithModule(VotingModule module, bytes memory proposalData, string memory description)
        public
        override
        returns (uint256)
    {
        if (!PartialVotingModule(address(module)).supportsPartialVoting()) {
            revert PartialVotingNotSupported(address(module));
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
        // TODO: Use allowlist of allowed contracts?
        if (account == alligator) {
            // Derive `voter` from address appended in `params`
            assembly {
                // TODO: Test this
                /// @dev no need to clean dirty bytes as they are sent already cleaned by alligator
                voter := mload(add(params, sub(mload(params), 0x20)))
            }
        }

        if (proposal.votingModule != address(0)) {
            PartialVotingModule(proposal.votingModule)._countVote(proposalId, account, support, weight, params, voter);
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
     * @dev If `params` is empty, or the first 32 bytes corresponding to `votes`
     * are 0, then standard nominal voting is used. Otherwise Partial voting is used.
     * @dev `votes` must be less than or equal to the delegate's remaining weight on the proposal
     * @dev This function can be called multiple times for the same `account` and `proposalId`
     * @dev Partial votes are still final once cast and cannot be modified
     */
    function _countVote(uint256 proposalId, address account, uint8 support, uint256 totalWeight, bytes memory params)
        internal
        virtual
        override(GovernorCountingSimpleUpgradeableV2, GovernorUpgradeableV2)
    {
        uint256 votes;

        if (params.length != 0) {
            /// @dev we decode partial votes from the first 32 bytes of `params`
            (votes) = abi.decode(params, (uint256));
        }

        if (votes == 0) {
            require(!hasVoted(proposalId, account), "Governor: vote already cast");

            if (totalWeight != 0) {
                // Count as nominal vote
                votes = totalWeight;
            } else {
                if (support > MAX_VOTE_TYPE) {
                    revert("GovernorVotingSimple: invalid value for enum VoteType");
                }

                // Set flag to prevent `account` from revoting with null weight
                _proposalVotes[proposalId].hasVoted[account] = true;
            }
        }

        require((weightCast[proposalId][account] += votes) <= totalWeight, "Governor: total weight exceeded");

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
     * - partial [0..31] = (uint256 partialVotes)
     * - modules [32..] = custom external module params
     */
    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "support=bravo&quorum=against,for,abstain&params=partial,modules";
    }

    /*//////////////////////////////////////////////////////////////
                                NONCE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the next unused nonce for an address. See {NoncesUpgradeable}.
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
