// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IVotableSupplyOracle {
    /**
     * Emitted when the votable supply is updated.
     */
    event VotableSupplyUpdated(uint256 blockNumber, uint256 oldVotableSupply, uint256 newVotableSupply);

    function _updateVotableSupply(uint256 newVotableSupply) external;

    function votableSupply(uint256 blockNumber) external view returns (uint256);

    function votableSupply() external view returns (uint256);
}
