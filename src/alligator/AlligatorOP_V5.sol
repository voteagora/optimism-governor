// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {AlligatorProxy} from "./AlligatorProxy.sol";
import {SubdelegationRules, AllowanceType} from "../structs/RulesV3.sol";
import {IAlligatorOPV4} from "../interfaces/IAlligatorOPV4.sol";
import {IRule} from "../interfaces/IRule.sol";
import {IOptimismGovernor} from "../interfaces/IOptimismGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @notice Liquid delegator contract for OP Governor.
 * Based on Alligator V2 (https://github.com/voteagora/liquid-delegator).
 *
 * Modifications from AlligatorOP:
 * - uses hashed proxy rules to reduce calldata size
 * - Assumes 1 proxy per owner
 * - Use proxies without deploying them
 * - Casts votes in batch directly to governor via `castVoteFromAlligator`
 * - Add alt methods to limit the sender's voting power when casting votes
 * - Upgradeable version of the contract
 *
 * TODO:
 * - Remove authority chains -> ESTIMATE IMPROVEMENT FIRST + CAN WE ADD IT AS AN UPGRADE
 * - Votable supply oracle
 * - Proposal types configurator
 */
contract AlligatorOPV5 is IAlligatorOPV4, UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable {
    // =============================================================
    //                             ERRORS
    // =============================================================

    error LengthMismatch();
    error BadSignature();
    error ZeroVotesToCast();
    error ProxyNotExistent();
    error NotDelegated(address from, address to);
    error TooManyRedelegations(address from, address to);
    error NotValidYet(address from, address to, uint256 willBeValidFrom);
    error NotValidAnymore(address from, address to, uint256 wasValidUntil);
    error TooEarly(address from, address to, uint256 blocksBeforeVoteCloses);
    error InvalidCustomRule(address from, address to, address customRule);

    // =============================================================
    //                             EVENTS
    // =============================================================

    event ProxyDeployed(address indexed owner, address proxy);
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
    //                       IMMUTABLE STORAGE
    // =============================================================

    address public constant governor = 0xcDF27F107725988f2261Ce2256bDfCdE8B382B10;

    address public constant op = 0x4200000000000000000000000000000000000042;

    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    bytes32 internal constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

    // =============================================================
    //                        MUTABLE STORAGE
    // =============================================================

    // Subdelegation rules `from` => `to`
    mapping(address from => mapping(address to => SubdelegationRules subdelegationRules)) public subDelegations;

    // Records of votes cast across an authority chain, to prevent double voting from the same proxy
    mapping(address proxy => mapping(uint256 proposalId => mapping(address voter => uint256))) public votesCast;

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _initOwner) external initializer {
        PausableUpgradeable.__Pausable_init();
        _transferOwnership(_initOwner);
    }

    // =============================================================
    //                     GOVERNOR OPERATIONS
    // =============================================================

    /**
     * @notice Validate subdelegation rules and cast a vote on the governor.
     *
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     */
    function castVote(address[] calldata authority, uint256 proposalId, uint8 support) public override whenNotPaused {
        _castVoteWithReasonAndParams(msg.sender, authority, proposalId, support, "", "");
    }

    /**
     * @notice Validate subdelegation rules and cast a vote with reason on the governor.
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
     * @notice Validate subdelegation rules and cast a vote with reason on the governor.
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
     * @notice Validate subdelegation rules and cast a vote by signature on the governor.
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
        address signatory = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Alligator"), block.chainid, address(this))),
                    keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support))
                )
            ),
            v,
            r,
            s
        );

        if (signatory == address(0)) {
            revert BadSignature();
        }

        _castVoteWithReasonAndParams(signatory, authority, proposalId, support, "", "");
    }

    /**
     * @notice Validate subdelegation rules and cast a vote with reason and params by signature on the governor.
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
        address signatory = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Alligator"), block.chainid, address(this))),
                    keccak256(
                        abi.encode(BALLOT_TYPEHASH, proposalId, support, keccak256(bytes(reason)), keccak256(params))
                    )
                )
            ),
            v,
            r,
            s
        );

        if (signatory == address(0)) {
            revert BadSignature();
        }

        _castVoteWithReasonAndParams(signatory, authority, proposalId, support, reason, params);
    }

    /**
     * @notice Validate subdelegation rules and cast multiple votes with reason on the governor.
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
        address[][] memory authorities,
        uint256 proposalId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) public override whenNotPaused {
        uint256 snapshotBlock = _proposalSnapshot(proposalId);
        address[] memory proxies = new address[](authorities.length);
        address[] memory authority;
        uint256 votesToCast;
        uint256 totalVotesToCast;
        uint256 proxyTotalVotes;
        uint256 k;
        for (uint256 i; i < authorities.length;) {
            authority = authorities[i];
            proxies[i] = proxyAddress(authority[0]);
            proxyTotalVotes = IVotes(op).getPastVotes(proxies[i], snapshotBlock);

            (votesToCast, k) = validate(proxies[i], msg.sender, authority, proposalId, support, proxyTotalVotes);

            if (votesToCast != 0) {
                totalVotesToCast += votesToCast;

                _recordVotesToCast(k, proxies[i], proposalId, authority, votesToCast, proxyTotalVotes);
            }

            unchecked {
                ++i;
            }
        }

        if (totalVotesToCast == 0) revert ZeroVotesToCast();

        _castVote(msg.sender, proposalId, support, reason, totalVotesToCast, params);

        emit VotesCast(proxies, msg.sender, authorities, proposalId, support);
    }

    /**
     * @notice Validate subdelegation rules and cast multiple votes with reason on the governor.
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
        address[][] memory authorities,
        uint256 proposalId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) public override whenNotPaused {
        uint256 snapshotBlock = _proposalSnapshot(proposalId);
        address[] memory proxies = new address[](authorities.length);
        address[] memory authority;
        uint256 votesToCast;
        uint256 totalVotesToCast;
        uint256 proxyTotalVotes;
        uint256 k;
        for (uint256 i; i < authorities.length;) {
            authority = authorities[i];
            proxies[i] = proxyAddress(authority[0]);
            proxyTotalVotes = IVotes(op).getPastVotes(proxies[i], snapshotBlock);

            (votesToCast, k) = validate(proxies[i], msg.sender, authority, proposalId, support, proxyTotalVotes);

            if (votesToCast != 0) {
                // Increase `totalVotesToCast` and check if it exceeds `maxVotingPower`
                if ((totalVotesToCast += votesToCast) < maxVotingPower) {
                    _recordVotesToCast(k, proxies[i], proposalId, authority, votesToCast, proxyTotalVotes);
                } else {
                    // If `totalVotesToCast` exceeds `maxVotingPower`, calculate the remaining votes to cast
                    votesToCast = maxVotingPower - (totalVotesToCast - votesToCast);
                    _recordVotesToCast(k, proxies[i], proposalId, authority, votesToCast, proxyTotalVotes);
                    totalVotesToCast = maxVotingPower;

                    break;
                }
            }

            unchecked {
                ++i;
            }
        }

        if (totalVotesToCast == 0) revert ZeroVotesToCast();

        _castVote(msg.sender, proposalId, support, reason, totalVotesToCast, params);

        emit VotesCast(proxies, msg.sender, authorities, proposalId, support);
    }

    /**
     * @notice Validate subdelegation rules and cast a vote with reason on the governor.
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
        uint256 proxyTotalVotes = IVotes(op).getPastVotes(proxy, _proposalSnapshot(proposalId));

        (uint256 votesToCast, uint256 k) = validate(proxy, voter, authority, proposalId, support, proxyTotalVotes);

        if (votesToCast == 0) revert ZeroVotesToCast();

        _recordVotesToCast(k, proxy, proposalId, authority, votesToCast, proxyTotalVotes);
        _castVote(proxy, proposalId, support, reason, votesToCast, params);

        emit VoteCast(proxy, voter, authority, proposalId, support);
    }

    function _recordVotesToCast(
        uint256 k,
        address proxy,
        uint256 proposalId,
        address[] memory authority,
        uint256 votesToCast,
        uint256 proxyTotalVotes
    ) internal {
        // Record weight cast for a proxy, on the governor
        IOptimismGovernor(governor).increaseWeightCast(proposalId, proxy, votesToCast, proxyTotalVotes);

        if (k != 0) {
            // Record `votesToCast` across the authority chain, only for voters whose allowance does not exceed proxy
            // remaining votes. This is because it would be unnecessary to do so as if they voted they would exhaust the
            // proxy votes regardless of votes cast by their delegates.
            uint256 authorityLength = authority.length;
            for (k; k < authorityLength;) {
                /// @dev cumulative votesCast cannot exceed proxy voting power, thus cannot overflow
                unchecked {
                    votesCast[proxy][proposalId][authority[k]] += votesToCast;

                    ++k;
                }
            }
        }
    }

    // =============================================================
    //                        SUBDELEGATIONS
    // =============================================================

    /**
     * @notice Subdelegate `to` with `subdelegationRules`.
     * Creates a proxy for `msg.sender` if it does not exist.
     *
     * @param to The address to subdelegate to.
     * @param subdelegationRules The rules to apply to the subdelegation.
     */
    function subDelegate(address to, SubdelegationRules calldata subdelegationRules) public override {
        subDelegations[msg.sender][to] = subdelegationRules;
        emit SubDelegation(msg.sender, to, subdelegationRules);
    }

    /**
     * @notice Subdelegate `targets` with `subdelegationRules`.
     *
     * @param targets The addresses to subdelegate to.
     * @param subdelegationRules The rules to apply to the subdelegations.
     */
    function subDelegateBatched(address[] calldata targets, SubdelegationRules calldata subdelegationRules)
        public
        override
    {
        uint256 targetsLength = targets.length;
        for (uint256 i; i < targetsLength;) {
            subDelegations[msg.sender][targets[i]] = subdelegationRules;

            unchecked {
                ++i;
            }
        }

        emit SubDelegations(msg.sender, targets, subdelegationRules);
    }

    /**
     * @notice Subdelegate `targets` with different `subdelegationRules` for each target.
     *
     * @param targets The addresses to subdelegate to.
     * @param subdelegationRules The rules to apply to the subdelegations.
     */
    function subDelegateBatched(address[] calldata targets, SubdelegationRules[] calldata subdelegationRules)
        public
        override
    {
        uint256 targetsLength = targets.length;
        if (targetsLength != subdelegationRules.length) revert LengthMismatch();

        for (uint256 i; i < targetsLength;) {
            subDelegations[msg.sender][targets[i]] = subdelegationRules[i];

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
     * @notice Validate subdelegation rules and partial delegation allowances.
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
        address[] memory authority,
        uint256 proposalId,
        uint256 support,
        uint256 voterAllowance
    ) internal view returns (uint256 votesToCast, uint256 k) {
        address from = authority[0];

        /// @dev Cannot underflow as `weightCast` is always less than or equal to total votes.
        unchecked {
            uint256 weightCast = _weightCast(proposalId, proxy);
            votesToCast = weightCast == 0 ? voterAllowance : voterAllowance - weightCast;
        }

        // If `sender` is the proxy owner, only the proxy rules are validated.
        if (from == sender) {
            return (votesToCast, k);
        }

        uint256 delegatorsVotes;
        uint256 toVotesCast;
        address to;
        SubdelegationRules memory subdelegationRules;
        for (uint256 i = 1; i < authority.length;) {
            to = authority[i];

            subdelegationRules = subDelegations[from][to];

            if (subdelegationRules.allowance == 0) {
                revert NotDelegated(from, to);
            }

            // Calculate `voterAllowance` based on allowance given by `from`
            voterAllowance =
                _getVoterAllowance(subdelegationRules.allowanceType, subdelegationRules.allowance, voterAllowance);

            // Record the highest `delegatorsVotes` in the authority chain
            toVotesCast = votesCast[proxy][proposalId][to];
            if (toVotesCast > delegatorsVotes) {
                delegatorsVotes = toVotesCast;
            }

            // If subdelegation allowance is lower than proxy remaining votes, record the point in the authority chain
            // after which we need to keep track of votes cast.
            if (k == 0) {
                if (
                    subdelegationRules.allowance
                        < (subdelegationRules.allowanceType == AllowanceType.Relative ? 1e5 : votesToCast)
                ) {
                    k = i;
                }
            }

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

        // Prevent double spending of votes already cast by previous delegators.
        // Reverts for underflow when `delegatorsVotes` exceeds `voterAllowance`, meaning that `sender` has no votes left.
        if (delegatorsVotes != 0) {
            voterAllowance -= delegatorsVotes;
        }

        votesToCast = voterAllowance > votesToCast ? votesToCast : voterAllowance;
    }

    /**
     * @notice Returns the address of the proxy contract for a given owner.
     *
     * @param proxyOwner The owner of the proxy.
     *
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
                            keccak256(abi.encodePacked(type(AlligatorProxy).creationCode, abi.encode(governor)))
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
     * @notice Cast a vote on the governor with reason and params.
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
        IOptimismGovernor(governor).castVoteFromAlligator(proposalId, voter, support, reason, votes, params);
    }

    /**
     * @notice Retrieve number of the proposal's end block.
     *
     * @param proposalId The id of the proposal to vote on
     * @return endBlock Proposal's end block number
     */
    function _proposalEndBlock(uint256 proposalId) internal view returns (uint256 endBlock) {
        return IOptimismGovernor(governor).proposalDeadline(proposalId);
    }

    /**
     * @notice Retrieve number of the proposal's snapshot.
     *
     * @param proposalId The id of the proposal to vote on
     * @return snapshotBlock Proposal's snapshot block number
     */
    function _proposalSnapshot(uint256 proposalId) internal view returns (uint256 snapshotBlock) {
        return IOptimismGovernor(governor).proposalSnapshot(proposalId);
    }

    /**
     * @notice Retrieve number of the proposal's snapshot.
     *
     * @param proposalId The id of the proposal to vote on
     * @param proxy The address of the proxy
     * @return weightCast Weight cast by the proxy
     */
    function _weightCast(uint256 proposalId, address proxy) internal view returns (uint256 weightCast) {
        return IOptimismGovernor(governor).weightCast(proposalId, proxy);
    }

    // =============================================================
    //                     RESTRICTED, INTERNAL
    // =============================================================

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @notice Pauses and unpauses propose, vote and sign operations.
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
            // TODO: Test if this condition is correct for nested subdelegations
            if (rules.maxRedelegations + redelegationIndex < authorityLength) {
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
                    IRule(rules.customRule).validate(governor, sender, proposalId, uint8(support))
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
}
