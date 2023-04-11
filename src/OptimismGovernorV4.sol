// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OptimismGovernorV3} from "./OptimismGovernorV3.sol";
import "@openzeppelin/contracts-upgradeable/utils/CheckpointsUpgradeable.sol";

contract OptimismGovernorV4 is OptimismGovernorV3 {
    function _correctQuorumForBlock83241938() public reinitializer(2) {
        _quorumNumeratorHistory._checkpoints[3] = 
                CheckpointsUpgradeable.Checkpoint({_blockNumber: 83241938, _value: 149})
            ;
    }
}
