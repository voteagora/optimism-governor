// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {AllowanceType} from "./AllowanceType.sol";

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
