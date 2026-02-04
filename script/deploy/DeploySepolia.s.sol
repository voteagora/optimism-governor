// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import {DeployBase} from "script/deploy/DeployBase.s.sol";

contract DeploySepolia is DeployBase {
    constructor() DeployBase(0xA622279f76ddbed4f2CC986c09244262Dba8f4Ba) {}

    function run() external {
        setup();
    }

    // Exclude from coverage report
    function test() public override {}
}
