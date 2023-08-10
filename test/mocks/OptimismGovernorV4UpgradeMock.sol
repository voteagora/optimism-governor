// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {OptimismGovernorV4} from "../../src/OptimismGovernorV4.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Mock UUPSUpgradeable to test upgradeability
contract OptimismGovernorV4UpgradeMock is OptimismGovernorV4, UUPSUpgradeable {
    function _authorizeUpgrade(address newImplementation) internal override {}
}
