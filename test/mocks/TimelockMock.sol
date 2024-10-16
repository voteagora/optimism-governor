// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {TimelockControllerUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

contract Timelock is TimelockControllerUpgradeable {
    function initialize(uint256 minDelay, address governor, address admin) public initializer {
        address[] memory proposers = new address[](1);
        proposers[0] = governor;
        address[] memory executors = new address[](1);
        executors[0] = governor;

        __TimelockController_init(minDelay, proposers, executors, admin);
    }
}
