// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {OptimismGovernorV6} from "../../src/OptimismGovernorV6.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Mock UUPSUpgradeable to test upgradeability
contract OptimismGovernorV6UpgradeMock is OptimismGovernorV6, UUPSUpgradeable {
    function _authorizeUpgrade(address newImplementation) internal override {}
}
