// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

interface IVotingToken is IVotesUpgradeable {
    /// @dev Return the votable supply at a given block number.
    function getPastVotableSupply(uint256 timepoint) external view returns (uint256);
}
