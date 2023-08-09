// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

abstract contract IOptimismGovernor is IGovernor {
    function weightCast(uint256 proposalId, address account) external view virtual returns (uint256 votes);
}
