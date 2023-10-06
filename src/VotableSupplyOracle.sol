// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IVotableSupplyOracle} from "./interfaces/IVotableSupplyOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/Checkpoints.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";

/**
 * Oracle managed by Optimism Governance to keep track of the total votable supply of OP tokens.
 */
contract VotableSupplyOracle is IVotableSupplyOracle, Ownable {
    /*//////////////////////////////////////////////////////////////
                               LIBRARIES
    //////////////////////////////////////////////////////////////*/

    using Checkpoints for Checkpoints.History;
    using SafeCastLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    Checkpoints.History internal _votableSupplyHistory;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address initOwner, uint256 initVotableSupply) {
        _transferOwnership(initOwner);

        // Initialize votable supply
        _votableSupplyHistory._checkpoints.push(
            Checkpoints.Checkpoint({_blockNumber: block.number.toUint32(), _value: initVotableSupply.toUint224()})
        );
        emit VotableSupplyUpdated(block.number, 0, initVotableSupply);
    }

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * Set `newVotableSupply` for checkpoint at current block. Emits a {VotableSupplyUpdated} event.
     */
    function _updateVotableSupply(uint256 newVotableSupply) external onlyOwner {
        uint256 oldVotableSupply = _votableSupplyHistory.latest();

        // Set new votableSupply for future proposals
        _votableSupplyHistory.push(newVotableSupply);

        emit VotableSupplyUpdated(block.number, oldVotableSupply, newVotableSupply);
    }

    /**
     * Set `newVotableSupply` for checkpoint at `index`. Emits a {VotableSupplyUpdated} event.
     */
    function _updateVotableSupplyAt(uint256 index, uint256 newVotableSupply) external onlyOwner {
        Checkpoints.Checkpoint memory checkpoint = _votableSupplyHistory._checkpoints[index];

        _votableSupplyHistory._checkpoints[index] =
            Checkpoints.Checkpoint({_blockNumber: checkpoint._blockNumber, _value: newVotableSupply.toUint224()});

        emit VotableSupplyUpdated(checkpoint._blockNumber, checkpoint._value, newVotableSupply);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the votableSupply numerator at a specific block number. See {votableSupplyDenominator}.
     */
    function votableSupply(uint256 blockNumber) public view returns (uint256) {
        uint256 length = _votableSupplyHistory._checkpoints.length;

        // Optimistic search, check the latest checkpoint
        Checkpoints.Checkpoint memory latest = _votableSupplyHistory._checkpoints[length - 1];
        if (latest._blockNumber <= blockNumber) {
            return latest._value;
        }

        // Otherwise, do the binary search
        return _votableSupplyHistory.getAtBlock(blockNumber);
    }

    /**
     * @dev Returns the value in the most recent checkpoint, or zero if there are no checkpoints.
     */
    function votableSupply() public view returns (uint256) {
        return _votableSupplyHistory.latest();
    }

    /**
     * @dev Returns whether there is a checkpoint in the structure (i.e. it is not empty), and if so the key and value
     * in the most recent checkpoint.
     */
    function latestCheckpoint()
        public
        view
        returns (
            bool, // exists
            uint32, // _blockNumber
            uint224 // _value
        )
    {
        return _votableSupplyHistory.latestCheckpoint();
    }

    /**
     * @dev Returns the number of checkpoint.
     */
    function nextIndex() public view returns (uint256) {
        return _votableSupplyHistory.length();
    }

    /**
     * @dev Return the index of the last checkpoint whose `blockNumber` is lower than the search `blockNumber`,
     * or `high` if there is none.
     */
    function getIndexBeforeBlock(uint32 blockNumber) public view returns (uint256) {
        uint256 low = 0;
        uint256 high = _votableSupplyHistory.length();

        while (low < high) {
            uint256 mid = Math.average(low, high);
            if (_votableSupplyHistory._checkpoints[mid]._blockNumber > blockNumber) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        return high - 1;
    }
}
