// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

abstract contract IOptimismGovernor is IGovernor {
    function castVoteFromAlligator(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params,
        uint256 weight
    ) external virtual returns (uint256);

    function weightCast(uint256 proposalId, address account) external view virtual returns (uint256 votes);
}
