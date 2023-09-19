// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {AlligatorProxy} from "./AlligatorProxy.sol";
import {SubdelegationRules, AllowanceType} from "../structs/RulesV3.sol";
import {IAlligatorOPV3} from "../interfaces/IAlligatorOPV3.sol";
import {IRule} from "../interfaces/IRule.sol";
import {IOptimismGovernor} from "../interfaces/IOptimismGovernor.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @notice Liquid delegator contract for OP Governor.
 * Based on Alligator V2 (https://github.com/voteagora/liquid-delegator).
 *
 * Modifications from AlligatorOP:
 * - uses hashed proxy rules to reduce calldata size
 * - Assumes 1 proxy per owner
 */
contract AlligatorOPV3 is IAlligatorOPV3, Ownable, Pausable {
    // =============================================================
    //                             ERRORS
    // =============================================================

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
    event VoteCast(
        address indexed proxy, address indexed voter, address[] authority, uint256 proposalId, uint8 support
    );
    event VotesCast(
        address[] proxies, address indexed voter, address[][] authorities, uint256 proposalId, uint8 support
    );

    // =============================================================
    //                       IMMUTABLE STORAGE
    // =============================================================

    address public immutable governor;
    address public immutable op;

    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    bytes32 internal constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

    // =============================================================
    //                        MUTABLE STORAGE
    // =============================================================

    // Subdelegation rules `from` => `to`
    mapping(address from => mapping(address to => SubdelegationRules subdelegationRules)) public subDelegations;

    // Records if a voter has already voted on a specific proposal from a proxy
    mapping(address proxy => mapping(uint256 proposalId => mapping(address voter => uint256))) votesCast;

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    constructor(address _governor, address _op, address _initOwner) {
        governor = _governor;
        op = _op;
        _transferOwnership(_initOwner);
    }

    // =============================================================
    //                      PROXY OPERATIONS
    // =============================================================

    /**
     * @notice Deploy a new proxy for an owner deterministically.
     *
     * @param proxyOwner The owner of the proxy.
     *
     * @return endpoint Address of the proxy
     */
    function create(address proxyOwner) public override returns (address endpoint) {
        endpoint = address(
            new AlligatorProxy{salt: bytes32(uint256(uint160(proxyOwner)))}(
                governor
            )
        );

        emit ProxyDeployed(proxyOwner, endpoint);
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
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVote(address[] calldata authority, uint256 proposalId, uint8 support)
        external
        override
        whenNotPaused
    {
        (address proxy, uint256 votesToCast) = validate(msg.sender, authority, proposalId, support);

        _castVoteWithReasonAndParams(proxy, proposalId, support, "", abi.encode(votesToCast));

        emit VoteCast(proxy, msg.sender, authority, proposalId, support);
    }

    /**
     * @notice Validate subdelegation rules and cast a vote with reason on the governor.
     *
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVoteWithReason(address[] calldata authority, uint256 proposalId, uint8 support, string calldata reason)
        public
        override
        whenNotPaused
    {
        (address proxy, uint256 votesToCast) = validate(msg.sender, authority, proposalId, support);

        _castVoteWithReasonAndParams(proxy, proposalId, support, reason, abi.encode(votesToCast));

        emit VoteCast(proxy, msg.sender, authority, proposalId, support);
    }

    /**
     * @notice Validate subdelegation rules and cast a vote with reason on the governor.
     *
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     * @param params The custom params of the vote
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVoteWithReasonAndParams(
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes calldata params
    ) public override whenNotPaused {
        (address proxy, uint256 votesToCast) = validate(msg.sender, authority, proposalId, support);

        _castVoteWithReasonAndParams(proxy, proposalId, support, reason, abi.encode(bytes32(votesToCast), params));

        emit VoteCast(proxy, msg.sender, authority, proposalId, support);
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
     * @dev Reverts if the proxy has not been created.
     */
    function castVoteWithReasonAndParamsBatched(
        address[][] calldata authorities,
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes calldata params
    ) public override whenNotPaused {
        uint256 authorityLength = authorities.length;

        address[] memory proxies = new address[](authorityLength);
        address[] memory authority;
        uint256 votesToCast;
        for (uint256 i; i < authorityLength;) {
            authority = authorities[i];
            (proxies[i], votesToCast) = validate(msg.sender, authority, proposalId, support);

            _castVoteWithReasonAndParams(
                proxies[i], proposalId, support, reason, abi.encode(bytes32(votesToCast), params)
            );

            unchecked {
                ++i;
            }
        }

        emit VotesCast(proxies, msg.sender, authorities, proposalId, support);
    }

    /**
     * @notice Validate subdelegation rules and cast a vote by signature on the governor.
     *
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVoteBySig(
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override whenNotPaused {
        bytes32 domainSeparator =
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Alligator"), block.chainid, address(this)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);

        if (signatory == address(0)) {
            revert BadSignature();
        }

        (address proxy, uint256 votesToCast) = validate(signatory, authority, proposalId, support);

        _castVoteWithReasonAndParams(proxy, proposalId, support, "", abi.encode(votesToCast));

        emit VoteCast(proxy, signatory, authority, proposalId, support);
    }

    /**
     * @notice Validate subdelegation rules and cast a vote with reason and params by signature on the governor.
     *
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the signatory
     * @param params The custom params of the vote
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVoteWithReasonAndParamsBySig(
        address[] memory authority,
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes calldata params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override whenNotPaused {
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

        (address proxy, uint256 votesToCast) = validate(signatory, authority, proposalId, support);

        _castVoteWithReasonAndParams(proxy, proposalId, support, reason, abi.encode(bytes32(votesToCast), params));

        emit VoteCast(proxy, signatory, authority, proposalId, support);
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
    function subDelegate(address to, SubdelegationRules calldata subdelegationRules) external override whenNotPaused {
        if (proxyAddress(msg.sender).code.length == 0) {
            create(msg.sender);
        }

        subDelegations[msg.sender][to] = subdelegationRules;
        emit SubDelegation(msg.sender, to, subdelegationRules);
    }

    /**
     * @notice Subdelegate `targets` with `subdelegationRules`.
     * Creates a proxy for `msg.sender` if it does not exist.
     *
     * @param targets The addresses to subdelegate to.
     * @param subdelegationRules The rules to apply to the subdelegations.
     */
    function subDelegateBatched(address[] calldata targets, SubdelegationRules calldata subdelegationRules)
        external
        override
        whenNotPaused
    {
        if (proxyAddress(msg.sender).code.length == 0) {
            create(msg.sender);
        }

        uint256 targetsLength = targets.length;
        for (uint256 i; i < targetsLength;) {
            subDelegations[msg.sender][targets[i]] = subdelegationRules;

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
     * @param sender The sender address to validate.
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal for which validation is being performed.
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain, 0xFF=proposal
     *
     * @return proxy The address of the proxy to cast votes from.
     * @return votesToCast The number of votes to cast by `sender`.
     */
    function validate(address sender, address[] memory authority, uint256 proposalId, uint256 support)
        internal
        returns (address proxy, uint256 votesToCast)
    {
        address from = authority[0];
        proxy = proxyAddress(from);

        if (proxy.code.length == 0) revert ProxyNotExistent();

        // Initialize `voterAllowance` with the proxy's voting power at snapshot block
        uint256 voterAllowance = IVotes(op).getPastVotes(proxy, _proposalSnapshot(proposalId));

        /// @dev Cannot underflow as `weightCast` is always less than or equal to total votes.
        unchecked {
            uint256 weightCast = _weightCast(proposalId, proxy);
            votesToCast = weightCast == 0 ? voterAllowance : voterAllowance - weightCast;
        }

        // If `sender` is the proxy owner, only the proxy rules are validated.
        if (from == sender) {
            return (proxy, votesToCast);
        }

        uint256 delegatorsVotes;
        uint256 k;
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

        // Prevent double spending of votes already cast by previous delegators.
        // Reverts for underflow when `delegatorsVotes` exceeds `voterAllowance`, meaning that `sender` has no votes left.
        if (delegatorsVotes != 0) {
            voterAllowance -= delegatorsVotes;
        }

        votesToCast = voterAllowance > votesToCast ? votesToCast : voterAllowance;

        if (from != sender) revert NotDelegated(from, sender);
        if (votesToCast == 0) revert ZeroVotesToCast();

        if (k != 0) {
            // Record `votesToCast` across the authority chain, only for voters whose allowance does not exceed
            // proxy remaining votes. This is because it would be unnecessary to do so as if they voted they would exhaust the
            // proxy votes regardless of votes cast by their delegates.
            for (k; k < authority.length;) {
                /// @dev cumulative votesCast cannot exceed proxy voting power, thus cannot overflow
                unchecked {
                    votesCast[proxy][proposalId][authority[k]] += votesToCast;

                    ++k;
                }
            }
        }
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
     * @param proxy The address of the proxy
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     * @param params The params to be passed to the governor
     */
    function _castVoteWithReasonAndParams(
        address proxy,
        uint256 proposalId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal {
        IOptimismGovernor(proxy).castVoteWithReasonAndParams(proposalId, support, reason, params);
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
