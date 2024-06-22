// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {AlligatorProxy} from "./AlligatorProxy.sol";
import {SubdelegationRules, AllowanceType} from "../structs/RulesV3.sol";
import {IAlligatorOPV6} from "../interfaces/IAlligatorOPV6.sol";
import {IRule} from "../interfaces/IRule.sol";
import {IOptimismGovernor} from "../interfaces/IOptimismGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Permit} from "src/lib/OptimismToken.sol";
import {ERC20} from "src/lib/OptimismToken.sol";
import {ContextUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import {Context} from "src/lib/OptimismToken.sol";
import {SafeCast} from "src/lib/OptimismToken.sol";
import {Math} from "src/lib/OptimismToken.sol";
import {ECDSA} from "src/lib/OptimismToken.sol";
import {GovernanceToken} from "src/lib/OptimismToken.sol";
import {ERC20Votes} from "src/lib/OptimismToken.sol";


/**
 * Liquid delegator contract for OP Governor.
 * Based on Alligator V2 (https://github.com/voteagora/liquid-delegator).
 *
 * Modifications from AlligatorOP:
 * - uses hashed proxy rules to reduce calldata size
 * - Assumes 1 proxy per owner
 * - Use proxies without deploying them
 * - Casts votes in batch directly to governor via `castVoteFromAlligator`
 * - Add alt methods to limit the sender's voting power when casting votes
 * - Upgradeable version of the contract
 * - Add castVoteBySigBatched
 */
contract AlligatorOPV6 is IAlligatorOPV6, ERC20Permit, UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable {
    // =============================================================
    //                             ERRORS
    // =============================================================

    error LengthMismatch();
    error InvalidSignature(ECDSAUpgradeable.RecoverError recoverError);
    error ZeroVotesToCast();
    error NotDelegated(address from, address to);
    error TooManyRedelegations(address from, address to);
    error NotValidYet(address from, address to, uint256 willBeValidFrom);
    error NotValidAnymore(address from, address to, uint256 wasValidUntil);
    error TooEarly(address from, address to, uint256 blocksBeforeVoteCloses);
    error InvalidCustomRule(address from, address to, address customRule);

    // =============================================================
    //                             EVENTS
    // =============================================================

    event SubDelegation(address indexed from, address indexed to, SubdelegationRules subdelegationRules);
    event SubDelegations(address indexed from, address[] to, SubdelegationRules subdelegationRules);
    event SubDelegations(address indexed from, address[] to, SubdelegationRules[] subdelegationRules);
    event VoteCast(
        address indexed proxy, address indexed voter, address[] authority, uint256 proposalId, uint8 support
    );
    event VotesCast(
        address[] proxies, address indexed voter, address[][] authorities, uint256 proposalId, uint8 support
    );

    // =============================================================
    //                           LIBRARIES
    // =============================================================

    // =============================================================
    //                       IMMUTABLE STORAGE
    // =============================================================

    address public constant GOVERNOR = 0xcDF27F107725988f2261Ce2256bDfCdE8B382B10;
    address public constant OP_TOKEN = 0x4200000000000000000000000000000000000042;
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support,address[] authority)");
    bytes32 public constant BALLOT_WITHPARAMS_TYPEHASH =
        keccak256("Ballot(uint256 proposalId,uint8 support,address[] authority,string reason,bytes params)");
    bytes32 public constant BALLOT_WITHPARAMS_BATCHED_TYPEHASH = keccak256(
        "Ballot(uint256 proposalId,uint8 support,uint256 maxVotingPower,address[][] authorities,string reason,bytes params)"
    );
    bytes32 private constant _DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    // =============================================================
    //                        MUTABLE STORAGE
    // =============================================================

    // Subdelegation rules `from` => `to`
    mapping(address from => mapping(address to => SubdelegationRules subdelegationRules)) public subdelegations;

    mapping(address proxy => mapping(uint256 proposalId => mapping(address voter => uint256))) private UNUSED_SLOT;

    // Records allowance of `delegator` used by `delegate` to vote on `proposalId` using `proxy`'s voting power
    // Used to prevent double voting with absolute allowances.
    mapping(
        address proxy
            => mapping(uint256 proposalId => mapping(address delegator => mapping(address delegate => uint256)))
    ) public votesCast;
    // Records votes cast by `delegate` using `authorityChainHash` to vote on `proposalId` using `proxy`'s voting power
    // Used to prevent double voting with relative allowances.
    mapping(
        address proxy
            => mapping(
                uint256 proposalId => mapping(bytes32 authorityChainHash => mapping(address delegate => uint256))
            )
    ) public votesCastByAuthorityChain;

    // Mapping to keep track of migrated accounts
    mapping(address account => bool migrated) public migrated;

    // Mapping to keep track of the delegates of each account
    mapping(address => address) private _delegates;

    // Checkpointing for votes for each account
    mapping(address => Checkpoint[]) private _checkpoints;

    // Array of all checkpoints
    Checkpoint[] private _totalSupplyCheckpoints;

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() ERC20("Alligator", "ALL") ERC20Permit("Alligator") {
        _disableInitializers();
    }

    function initialize(address _initOwner) external initializer {
        PausableUpgradeable.__Pausable_init();
        OwnableUpgradeable.__Ownable_init();
        UUPSUpgradeable.__UUPSUpgradeable_init();
        _transferOwnership(_initOwner);
    }

    // =============================================================
    //                    ERC20Votes FUNCTIONS
    // =============================================================

    /**
     * @dev Get the `pos`-th checkpoint for `account`.
     */
     function checkpoints(address account, uint32 pos) public view virtual returns (Checkpoint memory) {
        if (migrated[account]) {
            return _checkpoints[account][pos];
        } else {
            return Checkpoint(GovernanceToken(OP_TOKEN).checkpoints(account, pos).fromBlock, GovernanceToken(OP_TOKEN).checkpoints(account, pos).votes);
        }
    }

    /**
     * @dev Get number of checkpoints for `account`.
     */
    function numCheckpoints(address account) public view virtual returns (uint32) {
        if (migrated[account]) {
            return SafeCast.toUint32(_checkpoints[account].length);
        } else {
            return GovernanceToken(OP_TOKEN).numCheckpoints(account);
        }
    }

    /**
     * @dev Get the address `account` is currently delegating to.
     */
    function delegates(address account) public view virtual override returns (address) {
        if (migrated[account]) {
            return _delegates[account];
        } else {
            return GovernanceToken(OP_TOKEN).delegates(account);
        }
    }

    /**
     * @dev Gets the current votes balance for `account`
     */
    function getVotes(address account) public view virtual override returns (uint256) {
        if (migrated[account]) {
            uint256 pos = _checkpoints[account].length;
            return pos == 0 ? 0 : _checkpoints[account][pos - 1].votes;
        } else {
            return GovernanceToken(OP_TOKEN).getVotes(account);
        }
    }

    /**
     * @dev Retrieve the number of votes for `account` at the end of `blockNumber`.
     *
     * Requirements:
     *
     * - `blockNumber` must have been already mined
     */
    function getPastVotes(address account, uint256 blockNumber) public view virtual override returns (uint256) {
        if (migrated[account]) {
            require(blockNumber < block.number, "Alligator: block not yet mined");
            return _checkpointsLookup(_checkpoints[account], blockNumber);
        } else {
            return GovernanceToken(OP_TOKEN).getPastVotes(account, blockNumber);
        }
    }

    /**
     * @dev Retrieve the `totalSupply` at the end of `blockNumber`. Note, this value is the sum of all balances.
     * It is but NOT the sum of all the delegated votes!
     *
     * Requirements:
     *
     * - `blockNumber` must have been already mined
     */
    function getPastTotalSupply(uint256 blockNumber) public view virtual override returns (uint256) {
        require(blockNumber < block.number, "Alligator: block not yet mined");
        return _checkpointsLookup(_totalSupplyCheckpoints, blockNumber);
    }

    /**
     * @dev Lookup a value in a list of (sorted) checkpoints.
     */
    function _checkpointsLookup(Checkpoint[] storage ckpts, uint256 blockNumber) private view returns (uint256) {
        // We run a binary search to look for the earliest checkpoint taken after `blockNumber`.
        //
        // During the loop, the index of the wanted checkpoint remains in the range [low-1, high).
        // With each iteration, either `low` or `high` is moved towards the middle of the range to maintain the invariant.
        // - If the middle checkpoint is after `blockNumber`, we look in [low, mid)
        // - If the middle checkpoint is before or equal to `blockNumber`, we look in [mid+1, high)
        // Once we reach a single value (when low == high), we've found the right checkpoint at the index high-1, if not
        // out of bounds (in which case we're looking too far in the past and the result is 0).
        // Note that if the latest checkpoint available is exactly for `blockNumber`, we end up with an index that is
        // past the end of the array, so we technically don't find a checkpoint after `blockNumber`, but it works out
        // the same.
        uint256 high = ckpts.length;
        uint256 low = 0;
        while (low < high) {
            uint256 mid = Math.average(low, high);
            if (ckpts[mid].fromBlock > blockNumber) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        return high == 0 ? 0 : ckpts[high - 1].votes;
    }

    /**
     * @dev Delegate votes from the sender to `delegatee`.
     */
    function delegate(address delegatee) public virtual override {
        require(migrated[_msgSender()], "Alligator: msg.sender account not migrated");
        _delegate(_msgSender(), delegatee);
    }

    /**
     * @dev Delegates votes from signer to `delegatee`
     */
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override {
        require(block.timestamp <= expiry, "Alligator: signature expired");
        address signer = ECDSA.recover(
            _hashTypedDataV4(keccak256(abi.encode(_DELEGATION_TYPEHASH, delegatee, nonce, expiry))),
            v,
            r,
            s
        );
        require(nonce == _useNonce(signer), "Alligator: invalid nonce");
        if (migrated[signer]) {
            _delegate(signer, delegatee);
        } else {
            GovernanceToken(OP_TOKEN).delegateBySig(delegatee, nonce, expiry, v, r, s);
        }
    }

    /**
     * @dev Maximum token supply. Defaults to `type(uint224).max` (2^224^ - 1).
     */
    function _maxSupply() internal view virtual returns (uint224) {
        return type(uint224).max;
    }

    /**
     * @dev Snapshots the totalSupply after it has been increased.
     */
    function _mint(address account, uint256 amount) internal virtual override {
        super._mint(account, amount);
        require(totalSupply() <= _maxSupply(), "ERC20Votes: total supply risks overflowing votes");

        _writeCheckpoint(_totalSupplyCheckpoints, _add, amount);
    }

    /**
     * @dev Snapshots the totalSupply after it has been decreased.
     */
    function _burn(address account, uint256 amount) internal virtual override {
        super._burn(account, amount);

        _writeCheckpoint(_totalSupplyCheckpoints, _subtract, amount);
    }

    /**
     * @dev Move voting power when tokens are transferred.
     *
     * Emits a {DelegateVotesChanged} event.
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._afterTokenTransfer(from, to, amount);

        _moveVotingPower(delegates(from), delegates(to), amount);
    }

    /**
     * @dev Change delegation for `delegator` to `delegatee`.
     *
     * Emits events {DelegateChanged} and {DelegateVotesChanged}.
     */
    function _delegate(address delegator, address delegatee) internal virtual {
        address currentDelegate = delegates(delegator);
        uint256 delegatorBalance = balanceOf(delegator);
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveVotingPower(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveVotingPower(
        address src,
        address dst,
        uint256 amount
    ) private {
        if (src != dst && amount > 0) {
            if (src != address(0)) {
                (uint256 oldWeight, uint256 newWeight) = _writeCheckpoint(_checkpoints[src], _subtract, amount);
                emit DelegateVotesChanged(src, oldWeight, newWeight);
            }

            if (dst != address(0)) {
                (uint256 oldWeight, uint256 newWeight) = _writeCheckpoint(_checkpoints[dst], _add, amount);
                emit DelegateVotesChanged(dst, oldWeight, newWeight);
            }
        }
    }

    function _writeCheckpoint(
        Checkpoint[] storage ckpts,
        function(uint256, uint256) view returns (uint256) op,
        uint256 delta
    ) private returns (uint256 oldWeight, uint256 newWeight) {
        uint256 pos = ckpts.length;
        oldWeight = pos == 0 ? 0 : ckpts[pos - 1].votes;
        newWeight = op(oldWeight, delta);

        if (pos > 0 && ckpts[pos - 1].fromBlock == block.number) {
            ckpts[pos - 1].votes = SafeCast.toUint224(newWeight);
        } else {
            ckpts.push(Checkpoint({fromBlock: SafeCast.toUint32(block.number), votes: SafeCast.toUint224(newWeight)}));
        }
    }

    function _add(uint256 a, uint256 b) private pure returns (uint256) {
        return a + b;
    }

    function _subtract(uint256 a, uint256 b) private pure returns (uint256) {
        return a - b;
    }
    
    // =============================================================
    //                     GOVERNOR OPERATIONS
    // =============================================================

    /**
     * Function to be called by governance token after a token transfer.
     *
     * @param from The sender of the tokens
     * @param to The receiver of the tokens
     * @param amount The amount of tokens to transfer
    */
    function afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) external {
        _afterTokenTransfer(from, to, amount);

        if (!migrated[from]) _migrate(from);
        if (!migrated[to]) _migrate(to);
    }

    /**
     * Validate subdelegation rules and cast a vote on the governor.
     *
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     */
    function castVote(address[] calldata authority, uint256 proposalId, uint8 support) public override whenNotPaused {
        _castVoteWithReasonAndParams(msg.sender, authority, proposalId, support, "", "");
    }

    /**
     * Validate subdelegation rules and cast a vote with reason on the governor.
     *
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     */
    function castVoteWithReason(address[] calldata authority, uint256 proposalId, uint8 support, string calldata reason)
        public
        override
        whenNotPaused
    {
        _castVoteWithReasonAndParams(msg.sender, authority, proposalId, support, reason, "");
    }

    /**
     * Validate subdelegation rules and cast a vote with reason on the governor.
     *
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     * @param params The custom params of the vote
     */
    function castVoteWithReasonAndParams(
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) public override whenNotPaused {
        _castVoteWithReasonAndParams(msg.sender, authority, proposalId, support, reason, params);
    }

    /**
     * Validate subdelegation rules and cast multiple votes with reason on the governor.
     *
     * @param authorities The authority chains to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     * @param params The custom params of the vote
     *
     * @dev Authority chains with 0 votes to cast are skipped instead of triggering a revert.
     */
    function castVoteWithReasonAndParamsBatched(
        address[][] calldata authorities,
        uint256 proposalId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) public override whenNotPaused {
        _limitedCastVoteWithReasonAndParamsBatched(
            msg.sender, type(uint256).max, authorities, proposalId, support, reason, params
        );
    }

    /**
     * Validate subdelegation rules and cast multiple votes with reason on the governor.
     * Limits the max number of votes used to `maxVotingPower`, blocking iterations once reached.
     *
     * @param maxVotingPower The maximum voting power allowed to be used for the batchVote
     * @param authorities The authority chains to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     * @param params The custom params of the vote
     *
     * @dev Authority chains with 0 votes to cast are skipped instead of triggering a revert.
     */
    function limitedCastVoteWithReasonAndParamsBatched(
        uint256 maxVotingPower,
        address[][] calldata authorities,
        uint256 proposalId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) public override whenNotPaused {
        _limitedCastVoteWithReasonAndParamsBatched(
            msg.sender, maxVotingPower, authorities, proposalId, support, reason, params
        );
    }

    /**
     * Validate subdelegation rules and cast a vote by signature on the governor.
     *
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     */
    function castVoteBySig(
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override whenNotPaused {
        address signatory =
            _getSignatory(keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support, authority)), v, r, s);

        _castVoteWithReasonAndParams(signatory, authority, proposalId, support, "", "");
    }

    /**
     * Validate subdelegation rules and cast a vote with reason and params by signature on the governor.
     *
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the signatory
     * @param params The custom params of the vote
     */
    function castVoteWithReasonAndParamsBySig(
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        string memory reason,
        bytes memory params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override whenNotPaused {
        address signatory = _getSignatory(
            keccak256(
                abi.encode(
                    BALLOT_WITHPARAMS_TYPEHASH,
                    proposalId,
                    support,
                    authority,
                    keccak256(bytes(reason)),
                    keccak256(params)
                )
            ),
            v,
            r,
            s
        );

        _castVoteWithReasonAndParams(signatory, authority, proposalId, support, reason, params);
    }

    /**
     * Validate subdelegation rules and cast a vote with reason and params by signature on the governor.
     *
     * @param maxVotingPower The maximum voting power allowed to be used for the batchVote
     * @param authorities The authority chains to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the signatory
     * @param params The custom params of the vote
     */
    function limitedCastVoteWithReasonAndParamsBatchedBySig(
        uint256 maxVotingPower,
        address[][] calldata authorities,
        uint256 proposalId,
        uint8 support,
        string memory reason,
        bytes memory params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override whenNotPaused {
        address signatory = _getSignatory(
            keccak256(
                abi.encode(
                    BALLOT_WITHPARAMS_BATCHED_TYPEHASH,
                    proposalId,
                    support,
                    maxVotingPower,
                    authorities,
                    keccak256(bytes(reason)),
                    keccak256(params)
                )
            ),
            v,
            r,
            s
        );

        _limitedCastVoteWithReasonAndParamsBatched(
            signatory, maxVotingPower, authorities, proposalId, support, reason, params
        );
    }

    /**
     * Validate subdelegation rules and cast a vote with reason on the governor.
     *
     * @param voter The address of the voter
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     * @param params The custom params of the vote
     *
     * @dev Reverts if there are no votes to cast.
     */
    function _castVoteWithReasonAndParams(
        address voter,
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal {
        address proxy = proxyAddress(authority[0]);
        uint256 proxyTotalVotes = IVotes(OP_TOKEN).getPastVotes(proxy, _proposalSnapshot(proposalId));

        (uint256 votesToCast) = validate(proxy, voter, authority, proposalId, support, proxyTotalVotes);

        if (votesToCast == 0) revert ZeroVotesToCast();

        _recordVotesToCast(proxy, proposalId, authority, votesToCast, proxyTotalVotes);
        _castVote(voter, proposalId, support, reason, votesToCast, params);

        emit VoteCast(proxy, voter, authority, proposalId, support);
    }

    /**
     * Validate subdelegation rules and cast multiple votes with reason on the governor.
     * Limits the max number of votes used to `maxVotingPower`, blocking iterations once reached.
     *
     * @param voter The address of the voter
     * @param maxVotingPower The maximum voting power allowed to be used for the batchVote
     * @param authorities The authority chains to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     * @param params The custom params of the vote
     *
     * @dev Authority chains with 0 votes to cast are skipped instead of triggering a revert.
     */
    function _limitedCastVoteWithReasonAndParamsBatched(
        address voter,
        uint256 maxVotingPower,
        address[][] calldata authorities,
        uint256 proposalId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal {
        uint256 snapshotBlock = _proposalSnapshot(proposalId);
        address[] memory proxies = new address[](authorities.length);
        uint256 votesToCast;
        uint256 totalVotesToCast;
        uint256 proxyTotalVotes;
        for (uint256 i; i < authorities.length;) {
            proxies[i] = proxyAddress(authorities[i][0]);
            proxyTotalVotes = IVotes(OP_TOKEN).getPastVotes(proxies[i], snapshotBlock);

            (votesToCast) = validate(proxies[i], voter, authorities[i], proposalId, support, proxyTotalVotes);

            if (votesToCast != 0) {
                // Increase `totalVotesToCast` and check if it exceeds `maxVotingPower`
                if ((totalVotesToCast += votesToCast) < maxVotingPower) {
                    _recordVotesToCast(proxies[i], proposalId, authorities[i], votesToCast, proxyTotalVotes);
                } else {
                    // If `totalVotesToCast` exceeds `maxVotingPower`, calculate the remaining votes to cast
                    votesToCast = maxVotingPower - (totalVotesToCast - votesToCast);
                    _recordVotesToCast(proxies[i], proposalId, authorities[i], votesToCast, proxyTotalVotes);
                    totalVotesToCast = maxVotingPower;

                    break;
                }
            }

            unchecked {
                ++i;
            }
        }

        if (totalVotesToCast == 0) revert ZeroVotesToCast();

        _castVote(voter, proposalId, support, reason, totalVotesToCast, params);

        emit VotesCast(proxies, voter, authorities, proposalId, support);
    }

    function _recordVotesToCast(
        address proxy,
        uint256 proposalId,
        address[] calldata authority,
        uint256 votesToCast,
        uint256 proxyTotalVotes
    ) internal {
        // Record weight cast for a proxy, on the governor
        IOptimismGovernor(GOVERNOR).increaseWeightCast(proposalId, proxy, votesToCast, proxyTotalVotes);

        // Record `votesToCast` across the authority chain

        /// @dev cumulative votesCast cannot exceed proxy voting power, thus cannot overflow
        unchecked {
            address delegator = authority[0];
            uint256 authorityLength = authority.length;

            for (uint256 i = 1; i < authorityLength;) {
                // We save votesCast twice to always have the correct values for absolute and relative allowances
                votesCastByAuthorityChain[proxy][proposalId][keccak256(abi.encode(authority[0:i]))][authority[i]] +=
                    votesToCast;
                votesCast[proxy][proposalId][delegator][delegator = authority[i]] += votesToCast;

                ++i;
            }
        }
    }

    function _getSignatory(bytes32 structHash, uint8 v, bytes32 r, bytes32 s)
        internal
        view
        returns (address signatory)
    {
        ECDSAUpgradeable.RecoverError recoverError;
        (signatory, recoverError) = ECDSAUpgradeable.tryRecover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Alligator"), block.chainid, address(this))),
                    structHash
                )
            ),
            v,
            r,
            s
        );

        if (signatory == address(0)) {
            revert InvalidSignature(recoverError);
        }
    }

    // =============================================================
    //                        SUBDELEGATIONS
    // =============================================================

    /**
     * Subdelegate `to` with `subdelegationRules`.
     * Creates a proxy for `msg.sender` if it does not exist.
     *
     * @param to The address to subdelegate to.
     * @param subdelegationRules The rules to apply to the subdelegation.
     */
    function subdelegate(address to, SubdelegationRules calldata subdelegationRules) public override whenNotPaused {
        subdelegations[msg.sender][to] = subdelegationRules;
        emit SubDelegation(msg.sender, to, subdelegationRules);
    }

    /**
     * Subdelegate `targets` with `subdelegationRules`.
     *
     * @param targets The addresses to subdelegate to.
     * @param subdelegationRules The rules to apply to the subdelegations.
     */
    function subdelegateBatched(address[] calldata targets, SubdelegationRules calldata subdelegationRules)
        public
        override
        whenNotPaused
    {
        uint256 targetsLength = targets.length;
        for (uint256 i; i < targetsLength;) {
            subdelegations[msg.sender][targets[i]] = subdelegationRules;

            unchecked {
                ++i;
            }
        }

        emit SubDelegations(msg.sender, targets, subdelegationRules);
    }

    /**
     * Subdelegate `targets` with different `subdelegationRules` for each target.
     *
     * @param targets The addresses to subdelegate to.
     * @param subdelegationRules The rules to apply to the subdelegations.
     */
    function subdelegateBatched(address[] calldata targets, SubdelegationRules[] calldata subdelegationRules)
        public
        override
        whenNotPaused
    {
        uint256 targetsLength = targets.length;
        if (targetsLength != subdelegationRules.length) revert LengthMismatch();

        for (uint256 i; i < targetsLength;) {
            subdelegations[msg.sender][targets[i]] = subdelegationRules[i];

            unchecked {
                ++i;
            }
        }

        emit SubDelegations(msg.sender, targets, subdelegationRules);
    }

    // =============================================================
    //                         VIEW FUNCTIONS
    // =============================================================

    /**
     * Validate subdelegation rules and partial delegation allowances.
     *
     * @param proxy The address of the proxy.
     * @param sender The sender address to validate.
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal for which validation is being performed.
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain, 0xFF=proposal
     * @param voterAllowance The allowance of the voter.
     *
     * @return votesToCast The number of votes to cast by `sender`.
     */
    function validate(
        address proxy,
        address sender,
        address[] calldata authority,
        uint256 proposalId,
        uint256 support,
        uint256 voterAllowance
    ) internal view returns (uint256 votesToCast) {
        address from = authority[0];

        /// @dev Cannot underflow as `weightCast` is always less than or equal to total votes.
        unchecked {
            uint256 weightCast = _weightCast(proposalId, proxy);
            votesToCast = weightCast == 0 ? voterAllowance : voterAllowance - weightCast;
        }

        // If `sender` is the proxy owner, only the proxy rules are validated.
        if (from == sender) {
            return (votesToCast);
        }

        address to;
        SubdelegationRules memory subdelegationRules;
        uint256 votesCastFactor;
        for (uint256 i = 1; i < authority.length;) {
            to = authority[i];

            subdelegationRules = subdelegations[from][to];

            if (subdelegationRules.allowance == 0) {
                revert NotDelegated(from, to);
            }

            // Prevent double spending of votes already cast by previous delegators by adjusting `subdelegationRules.allowance`.
            if (subdelegationRules.allowanceType == AllowanceType.Relative) {
                // `votesCastFactor`: remaining votes to cast by the delegate
                // Get `votesCastFactor` by subtracting `votesCastByAuthorityChain` to given allowance amount
                // Reverts for underflow when `votesCastByAuthorityChain > votesCastFactor`, when delegate has exceeded the allowance.
                votesCastFactor = subdelegationRules.allowance * voterAllowance / 1e5
                    - votesCastByAuthorityChain[proxy][proposalId][keccak256(abi.encode(authority[0:i]))][to];

                // Adjust `votesToCast` to the minimum between `votesCastFactor` and `votesToCast`
                if (votesCastFactor < votesToCast) {
                    votesToCast = votesCastFactor;
                }
            } else {
                // `votesCastFactor`: total votes cast by the delegate
                // Retrieve votes cast by `to` via `from` regardless of the used authority chain
                votesCastFactor = votesCast[proxy][proposalId][from][to];

                // Adjust allowance by subtracting eventual votes already cast by the delegate
                // Reverts for underflow when `votesCastFactor > voterAllowance`, when delegate has exceeded the allowance.
                if (votesCastFactor != 0) {
                    subdelegationRules.allowance = subdelegationRules.allowance - votesCastFactor;
                }
            }

            // Calculate `voterAllowance` based on allowance given by `from`
            voterAllowance =
                _getVoterAllowance(subdelegationRules.allowanceType, subdelegationRules.allowance, voterAllowance);

            unchecked {
                _validateRules(
                    subdelegationRules,
                    sender,
                    authority.length,
                    proposalId,
                    support,
                    from,
                    to,
                    ++i // pass `i + 1` and increment at the same time
                );
            }

            from = to;
        }

        if (from != sender) revert NotDelegated(from, sender);

        votesToCast = voterAllowance > votesToCast ? votesToCast : voterAllowance;
    }

    /**
     * Returns the address of the proxy contract for a given owner.
     *
     * @param proxyOwner The owner of the proxy.
     * @return endpoint The address of the proxy.
     */
    function proxyAddress(address proxyOwner) public view override returns (address endpoint) {
        endpoint = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            bytes32(uint256(uint160(proxyOwner))), // salt
                            keccak256(abi.encodePacked(type(AlligatorProxy).creationCode, abi.encode(GOVERNOR)))
                        )
                    )
                )
            )
        );
    }

    // =============================================================
    //                   CUSTOM GOVERNOR FUNCTIONS
    // =============================================================

    /**
     * Cast a vote on the governor with reason and params.
     *
     * @param voter The address of the voter
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     * @param params The params to be passed to the governor
     */
    function _castVote(
        address voter,
        uint256 proposalId,
        uint8 support,
        string memory reason,
        uint256 votes,
        bytes memory params
    ) internal {
        IOptimismGovernor(GOVERNOR).castVoteFromAlligator(proposalId, voter, support, reason, votes, params);
    }

    /**
     * Retrieve number of the proposal's end block.
     *
     * @param proposalId The id of the proposal to vote on
     * @return endBlock Proposal's end block number
     */
    function _proposalEndBlock(uint256 proposalId) internal view returns (uint256) {
        return IOptimismGovernor(GOVERNOR).proposalDeadline(proposalId);
    }

    /**
     * Retrieve number of the proposal's snapshot.
     *
     * @param proposalId The id of the proposal to vote on
     * @return snapshotBlock Proposal's snapshot block number
     */
    function _proposalSnapshot(uint256 proposalId) internal view returns (uint256) {
        return IOptimismGovernor(GOVERNOR).proposalSnapshot(proposalId);
    }

    /**
     * Retrieve number of the proposal's snapshot.
     *
     * @param proposalId The id of the proposal to vote on
     * @param proxy The address of the proxy
     * @return weightCast Weight cast by the proxy
     */
    function _weightCast(uint256 proposalId, address proxy) internal view returns (uint256) {
        return IOptimismGovernor(GOVERNOR).weightCast(proposalId, proxy);
    }

    // =============================================================
    //                     RESTRICTED, INTERNAL
    // =============================================================

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * Pauses and unpauses propose, vote and sign operations.
     *
     * @dev Only contract owner can toggle pause.
     */
    function _togglePause() external onlyOwner {
        if (!paused()) {
            _pause();
        } else {
            _unpause();
        }
    }

    function _validateRules(
        SubdelegationRules memory rules,
        address sender,
        uint256 authorityLength,
        uint256 proposalId,
        uint256 support,
        address from,
        address to,
        uint256 redelegationIndex
    ) internal view {
        /// @dev `maxRedelegation` cannot overflow as it increases by 1 each iteration
        /// @dev block.number + rules.blocksBeforeVoteCloses cannot overflow uint256
        unchecked {
            if (uint256(rules.maxRedelegations) + redelegationIndex < authorityLength) {
                revert TooManyRedelegations(from, to);
            }
            if (block.timestamp < rules.notValidBefore) {
                revert NotValidYet(from, to, rules.notValidBefore);
            }
            if (rules.notValidAfter != 0) {
                if (block.timestamp > rules.notValidAfter) revert NotValidAnymore(from, to, rules.notValidAfter);
            }
            if (rules.blocksBeforeVoteCloses != 0) {
                if (_proposalEndBlock(proposalId) > uint256(block.number) + uint256(rules.blocksBeforeVoteCloses)) {
                    revert TooEarly(from, to, rules.blocksBeforeVoteCloses);
                }
            }
            if (rules.customRule != address(0)) {
                if (
                    IRule(rules.customRule).validate(GOVERNOR, sender, proposalId, uint8(support))
                        != IRule.validate.selector
                ) {
                    revert InvalidCustomRule(from, to, rules.customRule);
                }
            }
        }
    }

    /**
     * Return the allowance of a voter, used in `validate`.
     */
    function _getVoterAllowance(AllowanceType allowanceType, uint256 subdelegationAllowance, uint256 delegatorAllowance)
        private
        pure
        returns (uint256)
    {
        if (allowanceType == AllowanceType.Relative) {
            return
                subdelegationAllowance >= 1e5 ? delegatorAllowance : delegatorAllowance * subdelegationAllowance / 1e5;
        }

        // else if (allowanceType == AllowanceType.Absolute)
        return delegatorAllowance > subdelegationAllowance ? subdelegationAllowance : delegatorAllowance;
    }

    /**
     * Migrate the account's delegation data from the governance token to this contract.
     *
     * @param account The account to migrate.
     */
    function _migrate(address account) public {
        // set migrated flag
        migrated[account] = true;

        // copy delegates from governance token
        _delegates[account] = GovernanceToken(OP_TOKEN).delegates(account);

        // copy checkpoints from governance token
        Checkpoint[] storage accountCheckpoints = _checkpoints[account];

        for (uint32 i = 0; i < GovernanceToken(OP_TOKEN).numCheckpoints(account); i++) {
            Checkpoint memory checkpoint = Checkpoint(GovernanceToken(OP_TOKEN).checkpoints(account, i).fromBlock, GovernanceToken(OP_TOKEN).checkpoints(account, i).votes);
            accountCheckpoints.push(checkpoint);
        }

        _checkpoints[account] = accountCheckpoints;
    }

    /**
     * Retrieves the msg sender.
     *
     * @return Msg sender.
     */
    function _msgSender() internal view override(Context, ContextUpgradeable) returns (address) {
        // TODO: check that the line below is correct
        return super._msgSender();
    }

    /**
     * Retrieves the msg data.
     *
     * @return Msg data.
     */
    function _msgData() internal view override(Context, ContextUpgradeable) returns (bytes calldata) {
        // TODO: check that the line below is correct
        return super._msgData();
    }
}
