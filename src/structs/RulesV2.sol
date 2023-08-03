// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {AllowanceType} from "./AllowanceType.sol";

struct ProxyRules {
    uint8 maxRedelegations;
    uint32 notValidBefore;
    uint32 notValidAfter;
    uint16 blocksBeforeVoteCloses;
    address customRule;
}

struct SubdelegationRules {
    uint8 maxRedelegations;
    uint32 notValidBefore;
    uint32 notValidAfter;
    uint16 blocksBeforeVoteCloses;
    address customRule;
    AllowanceType allowanceType;
    uint256 allowance;
}
