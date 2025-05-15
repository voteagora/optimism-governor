// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {OptimismGovernor} from "../src/OptimismGovernor.sol";
import {TimelockControllerUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

/**
 * @title SetCancellers
 * @notice Script to add three Optimism Foundation L2 Safes to the canceller role
 * for the timelock, allowing them to cancel queued transactions if a malicious
 * or erroneous proposal is discovered. Proposers will retain their canceller role.
 * @dev Run this script with:
 *      forge script script/SetCancellers.s.sol:SetCancellers --rpc-url $RPC_URL --broadcast --verify
 */
contract SetCancellers is Script {
    address constant GOVERNOR_ADDRESS = 0x0000000000000000000000000000000000000000; // Replace with actual Optimism Governor address
    address constant L2_SAFE_1 = address(0); // Replace with first L2 Safe address
    address constant L2_SAFE_2 = address(0); // Replace with second L2 Safe address
    address constant L2_SAFE_3 = address(0); // Replace with third L2 Safe address

    // Constants
    bytes32 constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
    bytes32 constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");

    function run() external {
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();

        // Get the governor contract
        OptimismGovernor governor = OptimismGovernor(payable(GOVERNOR_ADDRESS));

        // Get the timelock address from the governor
        address timelockAddress = governor.timelock();
        console.log("Timelock address:", timelockAddress);

        // Get the timelock contract
        TimelockControllerUpgradeable timelock = TimelockControllerUpgradeable(payable(timelockAddress));

        require(timelock.hasRole(TIMELOCK_ADMIN_ROLE, deployer), "Deployer does not have admin role on timelock");

        // Step 1: Grant CANCELLER_ROLE to the three L2 Safes (if they don't already have it)
        if (!timelock.hasRole(CANCELLER_ROLE, L2_SAFE_1)) {
            console.log("Granting CANCELLER_ROLE to L2 Safe 1:", L2_SAFE_1);
            timelock.grantRole(CANCELLER_ROLE, L2_SAFE_1);
        } else {
            console.log("L2 Safe 1 already has CANCELLER_ROLE:", L2_SAFE_1);
        }

        if (!timelock.hasRole(CANCELLER_ROLE, L2_SAFE_2)) {
            console.log("Granting CANCELLER_ROLE to L2 Safe 2:", L2_SAFE_2);
            timelock.grantRole(CANCELLER_ROLE, L2_SAFE_2);
        } else {
            console.log("L2 Safe 2 already has CANCELLER_ROLE:", L2_SAFE_2);
        }

        if (!timelock.hasRole(CANCELLER_ROLE, L2_SAFE_3)) {
            console.log("Granting CANCELLER_ROLE to L2 Safe 3:", L2_SAFE_3);
            timelock.grantRole(CANCELLER_ROLE, L2_SAFE_3);
        } else {
            console.log("L2 Safe 3 already has CANCELLER_ROLE:", L2_SAFE_3);
        }

        // Verify the results
        console.log("Verification:");
        console.log("L2 Safe 1 has CANCELLER_ROLE:", timelock.hasRole(CANCELLER_ROLE, L2_SAFE_1));
        console.log("L2 Safe 2 has CANCELLER_ROLE:", timelock.hasRole(CANCELLER_ROLE, L2_SAFE_2));
        console.log("L2 Safe 3 has CANCELLER_ROLE:", timelock.hasRole(CANCELLER_ROLE, L2_SAFE_3));

        vm.stopBroadcast();
    }
}
