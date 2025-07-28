// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {OptimismGovernor} from "../src/OptimismGovernor.sol";
import {TimelockControllerUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

import {Timelock, TimelockControllerUpgradeable} from "test/mocks/TimelockMock.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title RedeployTimelock
 * @notice Redeploys timelock w/ better roles and updates governor to use the new timelock
 * @dev Run with:
 *      forge script script/RedeployTimelock.s.sol:RedeployTimelock --rpc-url $RPC_URL --broadcast --verify
 */
contract RedeployTimelock is Script {
    // ========== CONFIGURATION ==========

    // Existing contracts
    address constant EXISTING_GOVERNOR = 0x0000000000000000000000000000000000000000; // TODO: Set existing governor
    address constant MANAGER_ADDRESS = 0x0000000000000000000000000000000000000000; // TODO: Set manager address
    address constant PROXY_ADMIN = 0x0000000000000000000000000000000000000000;

    // L2 Safes to be added as cancellers
    address constant L2_SAFE_1 = 0x0000000000000000000000000000000000000000; // TODO: Set L2 Safe 1
    address constant L2_SAFE_2 = 0x0000000000000000000000000000000000000000; // TODO: Set L2 Safe 2
    address constant L2_SAFE_3 = 0x0000000000000000000000000000000000000000; // TODO: Set L2 Safe 3

    // Timelock configuration
    uint256 constant MIN_DELAY = 6 days;

    // Roles
    bytes32 constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");
    bytes32 constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
    bytes32 constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    Timelock timelock;

    function run() external {
        vm.startBroadcast();

        (, address deployer,) = vm.readCallers();

        console.log("========================================");
        console.log("Timelock Redeployment");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("Existing Governor:", EXISTING_GOVERNOR);
        console.log("Manager:", MANAGER_ADDRESS);
        console.log("");

        // Validate configuration
        require(EXISTING_GOVERNOR != address(0), "Governor not set");
        require(MANAGER_ADDRESS != address(0), "Manager not set");
        require(L2_SAFE_1 != address(0), "L2 Safe 1 not set");
        require(L2_SAFE_2 != address(0), "L2 Safe 2 not set");
        require(L2_SAFE_3 != address(0), "L2 Safe 3 not set");

        // 1. Deploy new timelock
        TimelockControllerUpgradeable newTimelock = _deployTimelock(deployer);

        // 2. Setup roles
        _setupRoles(newTimelock);

        // 3. Update governor to use new timelock
        OptimismGovernor governor = OptimismGovernor(payable(EXISTING_GOVERNOR));
        governor.updateTimelock(newTimelock);
        console.log("Governor updated with new timelock");

        // 4. Renounce deployer admin role
        newTimelock.renounceRole(TIMELOCK_ADMIN_ROLE, deployer);
        console.log("Renounced TIMELOCK_ADMIN_ROLE from deployer");

        vm.stopBroadcast();

        _verifyDeployment(newTimelock);
    }

    function _deployTimelock(address deployer) internal returns (TimelockControllerUpgradeable) {
        console.log("========== DEPLOYING NEW TIMELOCK ==========");

        timelock = Timelock(payable(new TransparentUpgradeableProxy(address(new Timelock()), address(PROXY_ADMIN), "")));
        // Prepare initialization
        timelock.initialize(MIN_DELAY, EXISTING_GOVERNOR, deployer);

        console.log("New Timelock deployed:", address(timelock));
        console.log("");

        return timelock;
    }

    function _setupRoles(TimelockControllerUpgradeable timelock) internal {
        console.log("========== SETTING UP ROLES ==========");

        // Grant canceller roles
        timelock.grantRole(CANCELLER_ROLE, MANAGER_ADDRESS);
        timelock.grantRole(CANCELLER_ROLE, L2_SAFE_1);
        timelock.grantRole(CANCELLER_ROLE, L2_SAFE_2);
        timelock.grantRole(CANCELLER_ROLE, L2_SAFE_3);
        console.log("Granted CANCELLER_ROLE to Manager, Governor, and L2 Safes");

        console.log("");
    }

    function _verifyDeployment(TimelockControllerUpgradeable timelock) internal view {
        console.log("========== VERIFICATION ==========");
        console.log("New Timelock:", address(timelock));
        console.log("Min Delay:", timelock.getMinDelay());
        console.log("");

        console.log("Role Holders:");
        console.log("PROPOSER_ROLE:");
        console.log("  - Governor: %s", timelock.hasRole(PROPOSER_ROLE, EXISTING_GOVERNOR));
        console.log("CANCELLER_ROLE:");
        console.log("  - Manager: %s", timelock.hasRole(CANCELLER_ROLE, MANAGER_ADDRESS));
        console.log("  - Governor: %s", timelock.hasRole(CANCELLER_ROLE, EXISTING_GOVERNOR));
        console.log("  - L2 Safe 1: %s", timelock.hasRole(CANCELLER_ROLE, L2_SAFE_1));
        console.log("  - L2 Safe 2: %s", timelock.hasRole(CANCELLER_ROLE, L2_SAFE_2));
        console.log("  - L2 Safe 3: %s", timelock.hasRole(CANCELLER_ROLE, L2_SAFE_3));
        console.log("TIMELOCK_ADMIN_ROLE:");
        console.log("  - Timelock: %s", timelock.hasRole(TIMELOCK_ADMIN_ROLE, address(timelock)));
        console.log("");

        // Verify governor points to new timelock
        OptimismGovernor governor = OptimismGovernor(payable(EXISTING_GOVERNOR));
        console.log("Governor's timelock:", governor.timelock());
        console.log("Matches new timelock: %s", governor.timelock() == address(timelock));
        console.log("");

        console.log("========================================");
        console.log("Timelock redeployment complete!");
        console.log("========================================");
    }
}
