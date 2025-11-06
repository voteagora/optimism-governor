// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import {UpgradeBase} from "script/test/UpgradeBase.s.sol";

contract UpgradeSepolia is UpgradeBase {
    constructor() UpgradeBase(
        0x7d377a66c4A803bbB457b4541e5ec62b1dCe2Ad3,
        address(0),
        0x368723068b6C762b416e5A7d506a605E8b816C22,
        0x5d729d4c0BF5d0a2Fa0F801c6e0023BD450c4fd6,
        0x2451dAF2153B1293Da2abF19C36c450321835C55,
        0xb88131610ff4D7D46050c9d1DEE413f8b6b8A5bd,
        0xf8D15c3132eFA557989A1C9331B6667Ca8Caa3a9
    ) {}

    function run() external {
        setup();
    }

    // Exclude from coverage report
    function test() public override {}
}
