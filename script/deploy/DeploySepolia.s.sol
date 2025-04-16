// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import {DeployBase} from "script/deploy/DeployBase.s.sol";

contract DeploySepolia is DeployBase {
    constructor() DeployBase(0x648BFC4dB7e43e799a84d0f607aF0b4298F932DB) {}

    function run() external {
        setup();
    }

    // Exclude from coverage report
    function test() public override {}
}
