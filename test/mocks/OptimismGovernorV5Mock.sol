// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {OptimismGovernorV5} from "../../src/OptimismGovernorV5.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Mock UUPSUpgradeable to test upgradeability
contract OptimismGovernorV5Mock is OptimismGovernorV5, UUPSUpgradeable {
    function _authorizeUpgrade(address newImplementation) internal override {}
}
