// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

abstract contract IOptimismGovernor is IGovernor {
    function manager() external view virtual returns (address);

    function increaseWeightCast(uint256 proposalId, address account, uint256 votes, uint256 proxyVotes)
        external
        virtual;

    function castVoteFromAlligator(
        uint256 proposalId,
        address voter,
        uint8 support,
        string memory reason,
        uint256 votes,
        bytes calldata params
    ) external virtual;

    function weightCast(uint256 proposalId, address account) external view virtual returns (uint256 votes);

    function votableSupply() external view virtual returns (uint256 supply);
}
