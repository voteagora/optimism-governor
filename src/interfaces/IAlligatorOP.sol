// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ProxyRules, SubdelegationRules} from "../structs/RulesV2.sol";

interface IAlligatorOP {
    // =============================================================
    //                      PROXY OPERATIONS
    // =============================================================

    function create(address owner, ProxyRules calldata proxyRules, bool registerEnsName)
        external
        returns (address endpoint);

    function registerProxyDeployment(address owner, ProxyRules calldata proxyRules) external;

    // =============================================================
    //                     GOVERNOR OPERATIONS
    // =============================================================

    function castVote(ProxyRules calldata proxyRules, address[] calldata authority, uint256 proposalId, uint8 support)
        external;

    function castVoteWithReason(
        ProxyRules calldata proxyRules,
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) external;

    function castVotesWithReasonBatched(
        ProxyRules[] calldata proxyRules,
        address[][] calldata authorities,
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) external;

    function castVoteBySig(
        ProxyRules calldata proxyRules,
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    // =============================================================
    //                        SUBDELEGATIONS
    // =============================================================

    function subDelegateAll(address to, ProxyRules calldata subDelegateRules) external;

    function subDelegateAllBatched(address[] calldata targets, ProxyRules[] calldata subDelegateRules) external;

    function subDelegate(
        address proxyOwner,
        ProxyRules calldata proxyRules,
        address to,
        ProxyRules calldata subDelegateRules
    ) external;

    function subDelegateBatched(
        address proxyOwner,
        ProxyRules calldata proxyRules,
        address[] calldata targets,
        ProxyRules[] calldata subDelegateRules
    ) external;

    // =============================================================
    //                          RESTRICTED
    // =============================================================

    function _togglePause() external;

    // =============================================================
    //                         VIEW FUNCTIONS
    // =============================================================

    function validate(
        ProxyRules memory rules,
        address sender,
        address[] memory authority,
        uint256 permissions,
        uint256 proposalId,
        uint256 support
    ) external view;

    function proxyAddress(address owner, ProxyRules calldata proxyRules) external view returns (address endpoint);
}
