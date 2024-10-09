// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {AlligatorProxy} from "./AlligatorProxy.sol";
import {BaseRules, SubdelegationRules, BaseRulesStorage, AllowanceType} from "../structs/RulesV2.sol";
import {IAlligatorOPV2} from "../interfaces/IAlligatorOPV2.sol";
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
 */
contract AlligatorOPV2 is IAlligatorOPV2, Ownable, Pausable {
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

    event ProxyDeployed(address indexed owner, bytes32 proxyRulesHash, address proxy);
    event SubDelegation(address indexed from, address indexed to, SubdelegationRules subdelegationRules);
    event SubDelegations(address indexed from, address[] to, SubdelegationRules subdelegationRules);
    event ProxySubdelegation(
        address indexed proxy, address indexed from, address indexed to, SubdelegationRules subdelegationRules
    );
    event ProxySubdelegations(
        address indexed proxy, address indexed from, address[] to, SubdelegationRules subdelegationRules
    );
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
    mapping(address from => mapping(address to => SubdelegationRules subdelegationRules)) public subdelegations;

    // Subdelegation rules `from` => `to`, for a specific proxy
    mapping(address proxy => mapping(address from => mapping(address to => SubdelegationRules subdelegationRules)))
        public subdelegationsProxy;

    // Records if a voter has already voted on a specific proposal from a proxy
    mapping(address proxy => mapping(uint256 proposalId => mapping(address voter => uint256))) votesCast;

    // Base rules for proxies
    mapping(bytes32 proxyRulesHash => BaseRulesStorage) public encodedProxyRules;

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
     * @param proxyRules The base rules of the proxy.
     *
     * @return endpoint Address of the proxy
     */
    function create(address proxyOwner, BaseRules calldata proxyRules) external override returns (address endpoint) {
        bytes32 proxyRulesHash = keccak256(abi.encode(proxyRules));

        endpoint = _create(proxyOwner, proxyRules, proxyRulesHash);
    }

    /**
     * @notice Internal version of `create` that doesn't recalculate proxyRulesHash
     *
     * @param proxyOwner The owner of the proxy.
     * @param proxyRules The base rules of the proxy.
     *
     * @return endpoint Address of the proxy
     */
    function _create(address proxyOwner, BaseRules calldata proxyRules, bytes32 proxyRulesHash)
        internal
        returns (address endpoint)
    {
        endpoint = address(new AlligatorProxy{salt: keccak256(abi.encode(proxyOwner, proxyRulesHash))}(governor));

        if (!encodedProxyRules[proxyRulesHash].isStored) {
            encodedProxyRules[proxyRulesHash] = BaseRulesStorage({
                isStored: true,
                maxRedelegations: proxyRules.maxRedelegations,
                notValidBefore: proxyRules.notValidBefore,
                notValidAfter: proxyRules.notValidAfter,
                blocksBeforeVoteCloses: proxyRules.blocksBeforeVoteCloses,
                customRule: proxyRules.customRule
            });
        }

        emit ProxyDeployed(proxyOwner, proxyRulesHash, endpoint);
    }

    // =============================================================
    //                     GOVERNOR OPERATIONS
    // =============================================================

    /**
     * @notice Validate subdelegation rules and cast a vote on the governor.
     *
     * @param proxyRulesHash The hash of the base rules of the proxy.
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVote(bytes32 proxyRulesHash, address[] calldata authority, uint256 proposalId, uint8 support)
        external
        override
        whenNotPaused
    {
        (address proxy, uint256 votesToCast) = validate(proxyRulesHash, msg.sender, authority, proposalId, support);

        _castVoteWithReasonAndParams(proxy, proposalId, support, "", abi.encode(votesToCast));

        emit VoteCast(proxy, msg.sender, authority, proposalId, support);
    }

    /**
     * @notice Validate subdelegation rules and cast a vote with reason on the governor.
     *
     * @param proxyRulesHash The hash of the base rules of the proxy.
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVoteWithReason(
        bytes32 proxyRulesHash,
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) public override whenNotPaused {
        (address proxy, uint256 votesToCast) = validate(proxyRulesHash, msg.sender, authority, proposalId, support);

        _castVoteWithReasonAndParams(proxy, proposalId, support, reason, abi.encode(votesToCast));

        emit VoteCast(proxy, msg.sender, authority, proposalId, support);
    }

    /**
     * @notice Validate subdelegation rules and cast a vote with reason on the governor.
     *
     * @param proxyRulesHash The hash of the base rules of the proxy.
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     * @param params The custom params of the vote
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVoteWithReasonAndParams(
        bytes32 proxyRulesHash,
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes calldata params
    ) public override whenNotPaused {
        (address proxy, uint256 votesToCast) = validate(proxyRulesHash, msg.sender, authority, proposalId, support);

        _castVoteWithReasonAndParams(proxy, proposalId, support, reason, abi.encode(bytes32(votesToCast), params));

        emit VoteCast(proxy, msg.sender, authority, proposalId, support);
    }

    /**
     * @notice Validate subdelegation rules and cast multiple votes with reason on the governor.
     *
     * @param proxyRulesHashes The hashes of the base rules of the proxies.
     * @param authorities The authority chains to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     * @param params The custom params of the vote
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVoteWithReasonAndParamsBatched(
        bytes32[] calldata proxyRulesHashes,
        address[][] calldata authorities,
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes calldata params
    ) public override whenNotPaused {
        uint256 authorityLength = authorities.length;
        require(authorityLength == proxyRulesHashes.length);

        address[] memory proxies = new address[](authorityLength);
        address[] memory authority;
        bytes32 proxyRulesHash;
        uint256 votesToCast;
        for (uint256 i; i < authorityLength;) {
            authority = authorities[i];
            proxyRulesHash = proxyRulesHashes[i];
            (proxies[i], votesToCast) = validate(proxyRulesHash, msg.sender, authority, proposalId, support);

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
     * @param proxyRulesHash The hash of the base rules of the proxy.
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVoteBySig(
        bytes32 proxyRulesHash,
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

        (address proxy, uint256 votesToCast) = validate(proxyRulesHash, signatory, authority, proposalId, support);

        _castVoteWithReasonAndParams(proxy, proposalId, support, "", abi.encode(votesToCast));

        emit VoteCast(proxy, signatory, authority, proposalId, support);
    }

    /**
     * @notice Validate subdelegation rules and cast a vote with reason and params by signature on the governor.
     *
     * @param proxyRulesHash The hash of the base rules of the proxy.
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the signatory
     * @param params The custom params of the vote
     *
     * @dev Reverts if the proxy has not been created.
     */
    function castVoteWithReasonAndParamsBySig(
        bytes32 proxyRulesHash,
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

        (address proxy, uint256 votesToCast) = validate(proxyRulesHash, signatory, authority, proposalId, support);

        _castVoteWithReasonAndParams(proxy, proposalId, support, reason, abi.encode(bytes32(votesToCast), params));

        emit VoteCast(proxy, signatory, authority, proposalId, support);
    }

    // =============================================================
    //                        SUBDELEGATIONS
    // =============================================================

    /**
     * @notice Subdelegate all sender Proxies to an address with rules.
     *
     * @param to The address to subdelegate to.
     * @param subdelegationRules The rules to apply to the subdelegation.
     */
    function subdelegateAll(address to, SubdelegationRules calldata subdelegationRules)
        external
        override
        whenNotPaused
    {
        subdelegations[msg.sender][to] = subdelegationRules;
        emit SubDelegation(msg.sender, to, subdelegationRules);
    }

    /**
     * @notice Subdelegate all sender Proxies to multiple addresses with rules.
     *
     * @param targets The addresses to subdelegate to.
     * @param subdelegationRules The rules to apply to the subdelegations.
     */
    function subdelegateAllBatched(address[] calldata targets, SubdelegationRules calldata subdelegationRules)
        external
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
     * @notice Subdelegate one proxy to an address with rules.
     * Creates a proxy for `proxyOwner` and `proxyRules` if it does not exist.
     *
     * @param proxyOwner Owner of the proxy being subdelegated.
     * @param proxyRules The base rules of the proxy to sign from.
     * @param to The address to subdelegate to.
     * @param subdelegationRules The rules to apply to the subdelegation.
     */
    function subdelegate(
        address proxyOwner,
        BaseRules calldata proxyRules,
        address to,
        SubdelegationRules calldata subdelegationRules
    ) external override whenNotPaused {
        bytes32 proxyRulesHash = keccak256(abi.encode(proxyRules));

        address proxy = proxyAddress(proxyOwner, proxyRulesHash);
        if (proxy.code.length == 0) {
            _create(proxyOwner, proxyRules, proxyRulesHash);
        }

        subdelegationsProxy[proxy][msg.sender][to] = subdelegationRules;
        emit ProxySubdelegation(proxy, msg.sender, to, subdelegationRules);
    }

    /**
     * @notice Subdelegate one proxy to multiple addresses with rules.
     * Creates a proxy for `proxyOwner` and `proxyRules` if it does not exist.
     *
     * @param proxyOwner Owner of the proxy being subdelegated.
     * @param proxyRules The base rules of the proxy to sign from.
     * @param targets The addresses to subdelegate to.
     * @param subdelegationRules The rules to apply to the subdelegations.
     */
    function subdelegateBatched(
        address proxyOwner,
        BaseRules calldata proxyRules,
        address[] calldata targets,
        SubdelegationRules calldata subdelegationRules
    ) external override whenNotPaused {
        bytes32 proxyRulesHash = keccak256(abi.encode(proxyRules));

        address proxy = proxyAddress(proxyOwner, proxyRulesHash);
        if (proxy.code.length == 0) {
            _create(proxyOwner, proxyRules, proxyRulesHash);
        }

        uint256 targetsLength = targets.length;
        for (uint256 i; i < targetsLength;) {
            subdelegationsProxy[proxy][msg.sender][targets[i]] = subdelegationRules;

            unchecked {
                ++i;
            }
        }

        emit ProxySubdelegations(proxy, msg.sender, targets, subdelegationRules);
    }

    // =============================================================
    //                         VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Validate proxy and subdelegation rules. proxy-specific delegations override address-specific delegations.
     *
     * @param proxyRulesHash The hash of the base rules of the proxy.
     * @param sender The sender address to validate.
     * @param authority The authority chain to validate against.
     * @param proposalId The id of the proposal for which validation is being performed.
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain, 0xFF=proposal
     *
     * @return proxy The address of the proxy to cast votes from.
     * @return votesToCast The number of votes to cast.
     */
    function validate(
        bytes32 proxyRulesHash,
        address sender,
        address[] memory authority,
        uint256 proposalId,
        uint256 support
    ) internal returns (address proxy, uint256 votesToCast) {
        // Validate base proxy rules
        _validateRules(
            _formatBaseRules(encodedProxyRules[proxyRulesHash]),
            sender,
            authority.length,
            proposalId,
            support,
            address(0),
            address(0),
            1
        );

        address from = authority[0];
        proxy = proxyAddress(from, proxyRulesHash);

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

            subdelegationRules = subdelegationsProxy[proxy][from][to];

            // If a subdelegation is not present, fallback to address-specific subdelegation rules
            if (subdelegationRules.allowance == 0) {
                subdelegationRules = subdelegations[from][to];

                if (subdelegationRules.allowance == 0) {
                    revert NotDelegated(from, to);
                }
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
                    subdelegationRules.baseRules,
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
     * @param proxyRulesHash The hash of the base rules of the proxy.
     *
     * @return endpoint The address of the proxy.
     */
    function proxyAddress(address proxyOwner, bytes32 proxyRulesHash) public view override returns (address endpoint) {
        endpoint = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            keccak256(abi.encode(proxyOwner, proxyRulesHash)), // salt
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
        BaseRules memory rules,
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

    /**
     * @notice Format base rules from `BaseRulesStorage` to `BaseRules`.
     */
    function _formatBaseRules(BaseRulesStorage memory rules) internal pure returns (BaseRules memory) {
        return BaseRules({
            maxRedelegations: rules.maxRedelegations,
            notValidBefore: rules.notValidBefore,
            notValidAfter: rules.notValidAfter,
            blocksBeforeVoteCloses: rules.blocksBeforeVoteCloses,
            customRule: rules.customRule
        });
    }
}
