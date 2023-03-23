// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OptimismGovernorV2} from "./OptimismGovernorV2.sol";

contract OptimismGovernorV3 is OptimismGovernorV2 {
    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public onlyManager returns (uint256) {
        return _cancel(targets, values, calldatas, descriptionHash);
    }
}
