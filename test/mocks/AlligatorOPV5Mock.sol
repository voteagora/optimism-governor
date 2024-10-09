// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {AlligatorOP} from "../../src/alligator/AlligatorOP.sol";

// Expose internal functions for testing
contract AlligatorOPMock is AlligatorOP {
    function _validate(
        address proxy,
        address sender,
        address[] calldata authority,
        uint256 proposalId,
        uint256 support,
        uint256 voterAllowance
    ) public view returns (uint256 votesToCast) {
        return AlligatorOPV5.validate(proxy, sender, authority, proposalId, support, voterAllowance);
    }
}
