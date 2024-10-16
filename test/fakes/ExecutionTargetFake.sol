// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract ExecutionTargetFake {
    uint256 public number;

    function setNumber(uint256 _number) public {
        number = _number;
    }
}
