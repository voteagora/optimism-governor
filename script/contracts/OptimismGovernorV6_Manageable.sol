// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {OptimismGovernorV6} from "src/OptimismGovernorV6.sol";

// Expose internal functions for testing
contract OptimismGovernorV6_Manageable is OptimismGovernorV6 {
    function _setManager(address newManager) external {
        require(msg.sender == 0x6EF3E0179e669C77C82664D0feDad3a637121Efe);
        manager = newManager;
    }
}
