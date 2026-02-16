// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import {UpgradeBase} from "script/test/UpgradeBase.s.sol";

contract UpgradeMainnet is UpgradeBase {
    constructor() UpgradeBase(
        address(0),
        0x2501c477D0A35545a387Aa4A3EEe4292A9a8B3F0,
        0xcDF27F107725988f2261Ce2256bDfCdE8B382B10,
        0x7f08F3095530B67CdF8466B7a923607944136Df0,
        0x1b7CA7437748375302bAA8954A2447fC3FBE44CC,
        0xCE52b7cc490523B3e81C3076D5ae5Cca9a3e2D6F,
        0x0eDd4B2cCCf41453D8B5443FBB96cc577d1d06bF
    ) {}

    function run() external {
        setup();
    }

    // Exclude from coverage report
    function test() public override {}
}

