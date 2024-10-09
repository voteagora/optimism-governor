// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IAlligatorOP {
    /**
     * @dev The type of allowance.
     */
    enum AllowanceType {
        Absolute,
        Relative
    }

    /**
     * @param maxRedelegations The maximum number of times the delegated votes can be redelegated.
     * @param blocksBeforeVoteCloses The number of blocks before the vote closes that the delegation is valid.
     * @param notValidBefore The timestamp after which the delegation is valid.
     * @param notValidAfter The timestamp before which the delegation is valid.
     * @param customRule The address of a contract that implements the `IRule` interface.
     * @param baseRules The base subdelegation rules.
     * @param allowanceType The type of allowance. If Absolute, the amount of votes delegated is fixed.
     * If Relative, the amount of votes delegated is relative to the total amount of votes the delegator has.
     * @param allowance The amount of votes delegated. If `allowanceType` is Relative 100% of allowance corresponds
     * to 1e5, otherwise this is the exact amount of votes delegated.
     */
    struct SubdelegationRules {
        uint8 maxRedelegations;
        uint16 blocksBeforeVoteCloses;
        uint32 notValidBefore;
        uint32 notValidAfter;
        address customRule;
        AllowanceType allowanceType;
        uint256 allowance;
    }

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
        address[][] memory authorities,
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params
    ) external;

    function limitedCastVoteWithReasonAndParamsBatched(
        uint256 maxVotingPower,
        address[][] memory authorities,
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

    function limitedCastVoteWithReasonAndParamsBatchedBySig(
        uint256 maxVotingPower,
        address[][] memory authorities,
        uint256 proposalId,
        uint8 support,
        string memory reason,
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

    function subdelegateBatched(address[] calldata targets, SubdelegationRules[] calldata subdelegationRules)
        external;
    // =============================================================
    //                          RESTRICTED
    // =============================================================

    function _togglePause() external;

    // =============================================================
    //                         VIEW FUNCTIONS
    // =============================================================

    function proxyAddress(address owner) external view returns (address endpoint);

    function votesCast(address proxy, uint256 proposalId, address delegator, address delegate)
        external
        view
        returns (uint256 votes);
}
