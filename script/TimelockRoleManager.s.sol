// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {OptimismGovernor} from "../src/OptimismGovernor.sol";
import {TimelockControllerUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

/**
 * @title TimelockRoleManager
 * @notice Script to manage and verify roles on the timelock controller
 * @dev Run this script with:
 *      - To verify roles only:
 *        forge script script/TimelockRoleManager.s.sol:TimelockRoleManager --sig "verify()" --rpc-url $RPC_URL
 *      - To simulate role changes:
 *        forge script script/TimelockRoleManager.s.sol:TimelockRoleManager --sig "simulateL2SafesCancellers()" --rpc-url $RPC_URL
 *      - To apply role changes:
 *        forge script script/TimelockRoleManager.s.sol:TimelockRoleManager --sig "addL2SafesCancellers()" --rpc-url $RPC_URL --broadcast
 */
contract TimelockRoleManager is Script {
    // Address of the deployed Optimism Governor
    address constant GOVERNOR_ADDRESS = 0x0000000000000000000000000000000000000000; // Replace with actual address

    // L2 Safes to be added as cancellers
    address constant L2_SAFE_1 = address(0); // Replace with actual address
    address constant L2_SAFE_2 = address(0); // Replace with actual address
    address constant L2_SAFE_3 = address(0); // Replace with actual address

    // Role constants
    bytes32 constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");
    bytes32 constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
    bytes32 constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    bytes32[4] private roles = [TIMELOCK_ADMIN_ROLE, PROPOSER_ROLE, CANCELLER_ROLE, EXECUTOR_ROLE];

    // State tracking for simulation
    struct SimulationState {
        mapping(address => mapping(bytes32 => bool)) roles;
        address[] addresses;
    }

    SimulationState simulationState;

    /**
     * @notice Verify all roles on the timelock
     */
    function verify() external view {
        _verifyRoles(false);
    }

    /**
     * @notice Simulate adding L2 Safes as cancellers
     * @dev Shows what would change without making actual changes
     */
    function simulateL2SafesCancellers() external {
        console.log("\n=== SIMULATING ADDING L2 SAFES AS CANCELLERS ===");

        _initializeSimulation();

        address[3] memory safes = [L2_SAFE_1, L2_SAFE_2, L2_SAFE_3];
        for (uint256 i = 0; i < safes.length; i++) {
            _simulateGrantRole(CANCELLER_ROLE, safes[i]);
        }

        _verifySimulatedState();
    }

    /**
     * @notice Actually add L2 Safes as cancellers
     * @dev This will broadcast transactions that modify the chain
     */
    function addL2SafesCancellers() external {
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();

        console.log("\n=== BEFORE CHANGES ===");
        _verifyRoles(false);

        // Get contract instances
        OptimismGovernor governor = OptimismGovernor(payable(GOVERNOR_ADDRESS));
        TimelockControllerUpgradeable timelock = TimelockControllerUpgradeable(payable(governor.timelock()));

        // Check admin permission
        require(timelock.hasRole(TIMELOCK_ADMIN_ROLE, deployer), "Not admin");

        // Grant canceller role to L2 Safes
        address[3] memory safes = [L2_SAFE_1, L2_SAFE_2, L2_SAFE_3];
        string[3] memory names = ["L2 Safe 1", "L2 Safe 2", "L2 Safe 3"];

        for (uint256 i = 0; i < safes.length; i++) {
            _grantRoleIfNeeded(timelock, CANCELLER_ROLE, safes[i], names[i]);
        }

        console.log("\n=== AFTER CHANGES ===");
        _verifyRoles(false);

        vm.stopBroadcast();
    }

    /**
     * @notice Initialize the simulation with the current chain state
     */
    function _initializeSimulation() internal {
        // Clear any previous simulation state
        delete simulationState;

        OptimismGovernor governor = OptimismGovernor(payable(GOVERNOR_ADDRESS));
        AccessControlEnumerableUpgradeable accessControl =
            AccessControlEnumerableUpgradeable(payable(governor.timelock()));

        // Copy role states
        for (uint256 i = 0; i < roles.length; i++) {
            _copyRoleState(accessControl, roles[i]);
        }
    }

    /**
     * @notice Copy the current role state for an AccessControl contract
     */
    function _copyRoleState(AccessControlEnumerableUpgradeable accessControl, bytes32 role) internal {
        uint256 memberCount = accessControl.getRoleMemberCount(role);
        for (uint256 i = 0; i < memberCount; i++) {
            address member = accessControl.getRoleMember(role, i);
            simulationState.roles[member][role] = true;
            _addUniqueAddress(member);
        }
    }

    /**
     * @notice Add a unique address to the simulation state
     */
    function _addUniqueAddress(address addr) internal {
        for (uint256 i = 0; i < simulationState.addresses.length; i++) {
            if (simulationState.addresses[i] == addr) return;
        }
        simulationState.addresses.push(addr);
    }

    /**
     * @notice Simulate granting a role to an address
     */
    function _simulateGrantRole(bytes32 role, address account) internal {
        if (!simulationState.roles[account][role]) {
            console.log("SIMULATED: Granting %s to %s", _getRoleName(role), account);
            simulationState.roles[account][role] = true;
            _addUniqueAddress(account);
        } else {
            console.log("SIMULATED: %s already has %s", account, _getRoleName(role));
        }
    }

    /**
     * @notice Simulate revoking a role from an address
     */
    function _simulateRevokeRole(bytes32 role, address account) internal {
        if (simulationState.roles[account][role]) {
            console.log("SIMULATED: Revoking %s from %s", _getRoleName(role), account);
            simulationState.roles[account][role] = false;
        } else {
            console.log("SIMULATED: %s doesn't have %s", account, _getRoleName(role));
        }
    }

    /**
     * @notice Verify the simulated state after changes
     */
    function _verifySimulatedState() internal view {
        console.log("\n=== SIMULATED STATE AFTER CHANGES ===");

        for (uint256 r = 0; r < roles.length; r++) {
            bytes32 role = roles[r];
            console.log("\n=== %s ===", _getRoleName(role));

            uint256 memberCount = 0;
            for (uint256 i = 0; i < simulationState.addresses.length; i++) {
                address member = simulationState.addresses[i];
                if (simulationState.roles[member][role]) {
                    memberCount++;
                    console.log("  Address: %s", member);
                    _logOtherRoles(member, role);
                }
            }

            console.log("  Total holders: %s", memberCount);
        }
    }

    /**
     * @notice Log other roles held by a member
     */
    function _logOtherRoles(address member, bytes32 currentRole) internal view {
        for (uint256 j = 0; j < roles.length; j++) {
            bytes32 otherRole = roles[j];
            if (otherRole != currentRole && simulationState.roles[member][otherRole]) {
                console.log("    - Also has %s", _getRoleName(otherRole));
            }
        }
    }

    // ======== INTERNAL HELPER FUNCTIONS ========

    /**
     * @dev Internal function to verify all roles on the timelock
     * @param showCombined Whether to show a combined view of all roles per address
     */
    function _verifyRoles(bool showCombined) internal view {
        // Get the governor contract
        OptimismGovernor governor = OptimismGovernor(payable(GOVERNOR_ADDRESS));

        // Get the timelock address from the governor
        address timelockAddress = governor.timelock();
        console.log("Timelock address:", timelockAddress);

        // Get the timelock contract
        AccessControlEnumerableUpgradeable accessControl = AccessControlEnumerableUpgradeable(payable(timelockAddress));

        if (!showCombined) {
            // Check individual roles
            for (uint256 i = 0; i < roles.length; i++) {
                console.log("\n=== %s ===", _getRoleName(roles[i]));
                _printRoleHolders(accessControl, roles[i]);
            }
        } else {
            // Collect all unique addresses with any role
            console.log("\n=== ALL ROLES BY ADDRESS ===");
            _printCombinedRoles(accessControl);
        }

        // Check open roles (address(0) having a role means anyone can perform that role)
        console.log("\n=== OPEN ROLES (address(0)) ===");
        for (uint256 i = 0; i < roles.length; i++) {
            console.log("%s open to all: %s", _getRoleName(roles[i]), accessControl.hasRole(roles[i], address(0)));
        }
    }

    /**
     * @dev Print holders of a specific role
     */
    function _printRoleHolders(AccessControlEnumerableUpgradeable accessControl, bytes32 role) internal view {
        uint256 memberCount = accessControl.getRoleMemberCount(role);
        console.log("Total holders:", memberCount);

        for (uint256 i = 0; i < memberCount; i++) {
            address member = accessControl.getRoleMember(role, i);
            console.log("  Address:", member);

            // Check if this member also holds other roles
            for (uint256 j = 0; j < roles.length; j++) {
                if (roles[j] != role && accessControl.hasRole(roles[j], member)) {
                    console.log("    - Also has %s", _getRoleName(roles[j]));
                }
            }
        }
    }

    /**
     * @dev Print combined roles for all addresses
     */
    function _printCombinedRoles(AccessControlEnumerableUpgradeable accessControl) internal view {
        console.log("\n=== ALL ROLES BY ADDRESS ===");
        address[] memory allAddresses = _getAllUniqueAddresses(accessControl);

        for (uint256 i = 0; i < allAddresses.length; i++) {
            address addr = allAddresses[i];
            console.log("Address:", addr);

            for (uint256 j = 0; j < roles.length; j++) {
                if (accessControl.hasRole(roles[j], addr)) {
                    console.log("  - Has %s", _getRoleName(roles[j]));
                }
            }
            console.log("");
        }
    }

    /**
     * @dev Get all unique addresses with any role
     */
    function _getAllUniqueAddresses(AccessControlEnumerableUpgradeable accessControl)
        internal
        view
        returns (address[] memory)
    {
        address[] memory result = new address[](0);

        for (uint256 r = 0; r < roles.length; r++) {
            uint256 memberCount = accessControl.getRoleMemberCount(roles[r]);
            for (uint256 i = 0; i < memberCount; i++) {
                address member = accessControl.getRoleMember(roles[r], i);
                bool found = false;

                for (uint256 j = 0; j < result.length; j++) {
                    if (result[j] == member) {
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    address[] memory expanded = new address[](result.length + 1);
                    for (uint256 j = 0; j < result.length; j++) {
                        expanded[j] = result[j];
                    }
                    expanded[result.length] = member;
                    result = expanded;
                }
            }
        }
        return result;
    }

    /**
     * @dev Grant a role if the account doesn't already have it
     */
    function _grantRoleIfNeeded(
        TimelockControllerUpgradeable timelock,
        bytes32 role,
        address account,
        string memory accountName
    ) internal {
        if (!timelock.hasRole(role, account)) {
            console.log("Granting %s to %s (%s)", _getRoleName(role), accountName, account);
            timelock.grantRole(role, account);
        } else {
            console.log("%s (%s) already has %s", accountName, account, _getRoleName(role));
        }
    }

    /**
     * @dev Get a human-readable role name
     */
    function _getRoleName(bytes32 role) internal pure returns (string memory) {
        if (role == TIMELOCK_ADMIN_ROLE) return "TIMELOCK_ADMIN_ROLE";
        if (role == PROPOSER_ROLE) return "PROPOSER_ROLE";
        if (role == CANCELLER_ROLE) return "CANCELLER_ROLE";
        if (role == EXECUTOR_ROLE) return "EXECUTOR_ROLE";
        return "UNKNOWN_ROLE";
    }
}
