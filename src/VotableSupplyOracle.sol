// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IVotableSupplyOracle} from "./interfaces/IVotableSupplyOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/Checkpoints.sol";
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

    constructor(address owner, uint256 initVotableSupply) {
        _transferOwnership(owner);

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
}

// TODO: Test that blocks prior to init block return 0
// TODO: Check updateVotableSupplyAt reverts if index is out of bounds
