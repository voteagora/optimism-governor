// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IVotableSupplyOracle {
    /**
     * Emitted when the votable supply is updated with `_updateVotableSupply`.
     */
    event VotableSupplyUpdated(uint256 prevVotableSupply, uint256 newVotableSupply);
    /**
     * Emitted when the votable supply is updated with `_updateVotableSupplyAt`.
     */
    event VotableSupplyCheckpointUpdated(
        uint256 checkpointBlockNumber, uint256 prevVotableSupply, uint256 newVotableSupply
    );

    function _updateVotableSupply(uint256 newVotableSupply) external;
    function _updateVotableSupplyAt(uint256 index, uint256 newVotableSupply) external;

    function votableSupply(uint256 blockNumber) external view returns (uint256);

    function votableSupply() external view returns (uint256);
}
