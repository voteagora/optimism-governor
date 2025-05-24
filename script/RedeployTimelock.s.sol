// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {OptimismGovernor} from "../src/OptimismGovernor.sol";
import {TimelockControllerUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

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

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

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

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy new timelock
        TimelockControllerUpgradeable newTimelock = _deployTimelock(deployer);

        // 2. Setup roles
        _setupRoles(newTimelock, deployer);

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

        // Deploy implementation
        TimelockControllerUpgradeable timelockImpl = new TimelockControllerUpgradeable();

        // Prepare initialization
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Anyone can execute

        bytes memory initData = abi.encodeWithSignature(
            "__TimelockController_init(uint256,address[],address[],address)",
            MIN_DELAY,
            proposers,
            executors,
            deployer // deployer is initial admin
        );

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(timelockImpl), initData);
        TimelockControllerUpgradeable timelock = TimelockControllerUpgradeable(payable(address(proxy)));

        console.log("New Timelock deployed:", address(timelock));
        console.log("");

        return timelock;
    }

    function _setupRoles(TimelockControllerUpgradeable timelock, address deployer) internal {
        console.log("========== SETTING UP ROLES ==========");

        // Grant proposer role to governor
        timelock.grantRole(PROPOSER_ROLE, EXISTING_GOVERNOR);
        console.log("Granted PROPOSER_ROLE to Governor");

        // Grant canceller roles
        timelock.grantRole(CANCELLER_ROLE, MANAGER_ADDRESS);
        timelock.grantRole(CANCELLER_ROLE, EXISTING_GOVERNOR);
        timelock.grantRole(CANCELLER_ROLE, L2_SAFE_1);
        timelock.grantRole(CANCELLER_ROLE, L2_SAFE_2);
        timelock.grantRole(CANCELLER_ROLE, L2_SAFE_3);
        console.log("Granted CANCELLER_ROLE to Manager, Governor, and L2 Safes");

        // Grant admin role to timelock itself for self-administration
        timelock.grantRole(TIMELOCK_ADMIN_ROLE, address(timelock));
        console.log("Granted TIMELOCK_ADMIN_ROLE to Timelock (self)");

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
