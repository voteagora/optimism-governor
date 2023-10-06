// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SubdelegationRules} from "../structs/RulesV3.sol";

interface IAlligatorOPV3 {
    // =============================================================
    //                      PROXY OPERATIONS
    // =============================================================

    function create(address owner) external returns (address endpoint);

    // =============================================================
    //                     GOVERNOR OPERATIONS
    // =============================================================

    function castVote(address[] calldata authority, uint256 proposalId, uint8 support) external;

    function castVoteWithReason(address[] calldata authority, uint256 proposalId, uint8 support, string calldata reason)
        external;

    function castVoteWithReasonAndParams(
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params
    ) external;

    function castVoteWithReasonAndParamsBatched(
        address[][] calldata authorities,
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params
    ) external;

    function castVoteBySig(
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function castVoteWithReasonAndParamsBySig(
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

    function subdelegate(address to, SubdelegationRules calldata subdelegateRules) external;

    function subdelegateBatched(address[] calldata targets, SubdelegationRules calldata subdelegateRules) external;

    // =============================================================
    //                          RESTRICTED
    // =============================================================

    function _togglePause() external;

    // =============================================================
    //                         VIEW FUNCTIONS
    // =============================================================

    function proxyAddress(address owner) external view returns (address endpoint);
}
