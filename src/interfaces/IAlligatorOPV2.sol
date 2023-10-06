// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {BaseRules, SubdelegationRules} from "../structs/RulesV2.sol";

interface IAlligatorOPV2 {
    // =============================================================
    //                      PROXY OPERATIONS
    // =============================================================

    function create(address owner, BaseRules calldata proxyRules) external returns (address endpoint);

    // =============================================================
    //                     GOVERNOR OPERATIONS
    // =============================================================

    function castVote(bytes32 proxyRulesHash, address[] calldata authority, uint256 proposalId, uint8 support)
        external;

    function castVoteWithReason(
        bytes32 proxyRulesHash,
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) external;

    function castVoteWithReasonAndParams(
        bytes32 proxyRulesHash,
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params
    ) external;

    function castVoteWithReasonAndParamsBatched(
        bytes32[] calldata proxyRulesHashes,
        address[][] calldata authorities,
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params
    ) external;

    function castVoteBySig(
        bytes32 proxyRulesHash,
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function castVoteWithReasonAndParamsBySig(
        bytes32 proxyRulesHash,
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    // =============================================================
    //                        SUBDELEGATIONS
    // =============================================================

    function subdelegateAll(address to, SubdelegationRules calldata subdelegateRules) external;

    function subdelegateAllBatched(address[] calldata targets, SubdelegationRules calldata subdelegateRules) external;

    function subdelegate(
        address proxyOwner,
        BaseRules calldata proxyRules,
        address to,
        SubdelegationRules calldata subdelegateRules
    ) external;

    function subdelegateBatched(
        address proxyOwner,
        BaseRules calldata proxyRules,
        address[] calldata targets,
        SubdelegationRules calldata subdelegateRules
    ) external;

    // =============================================================
    //                          RESTRICTED
    // =============================================================

    function _togglePause() external;

    // =============================================================
    //                         VIEW FUNCTIONS
    // =============================================================

    function proxyAddress(address owner, bytes32 proxyRulesHash) external view returns (address endpoint);
}
