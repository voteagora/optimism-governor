// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (governance/extensions/GovernorVotesQuorumFraction.sol)

pragma solidity ^0.8.0;

import "./GovernorVotesUpgradeableV2.sol";
import "@openzeppelin/contracts-upgradeable/utils/CheckpointsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// Contract is empty as it was deprecated and only left for storage compatibility
abstract contract GovernorVotesQuorumFractionUpgradeableV2 is Initializable, GovernorVotesUpgradeableV2 {
    using CheckpointsUpgradeable for CheckpointsUpgradeable.History;

    uint256 private _quorumNumerator; // DEPRECATED
    CheckpointsUpgradeable.History internal _quorumNumeratorHistory;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[48] private __gap;
}
