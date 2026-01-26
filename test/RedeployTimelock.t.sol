// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {
    TimelockControllerUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title RedeployTimelockTest
 * @notice Comprehensive test suite for the timelock redeployment functionality
 * @dev Tests the following scenarios:
 *      1. Successful timelock redeployment with proper role setup
 *      2. Governor update to use the new timelock
 *      3. Proposal execution through the new timelock
 *      4. Cancellation permissions for all authorized parties (Manager, L2 Safes)
 *
 * Run with: forge test --match-contract RedeployTimelockTest -vv
 */
interface IGovernor {
    function updateTimelock(TimelockControllerUpgradeable newTimelock) external;
    function timelock() external view returns (address);
}

// Wrapper contract to enable initialization of TimelockControllerUpgradeable
contract InitializableTimelock is TimelockControllerUpgradeable {
    function initialize(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        public
        initializer
    {
        __TimelockController_init(minDelay, proposers, executors, admin);
    }
}

contract RedeployTimelockTest is Test {
    // Test addresses
    address constant MANAGER_ADDRESS = address(0x5678);
    address constant L2_SAFE_1 = address(0x9ABC);
    address constant L2_SAFE_2 = address(0xDEF0);
    address constant L2_SAFE_3 = address(0x1357);

    // Role constants
    bytes32 constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");
    bytes32 constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
    bytes32 constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    // Mock governor
    MockGovernor governor;
    TimelockControllerUpgradeable oldTimelock;

    function setUp() public {
        // Deploy old timelock
        oldTimelock = _deployTimelock();

        // Deploy mock governor
        governor = new MockGovernor(address(oldTimelock));

        // Setup old timelock roles
        oldTimelock.grantRole(PROPOSER_ROLE, address(governor));
        oldTimelock.grantRole(CANCELLER_ROLE, address(governor));
        oldTimelock.grantRole(TIMELOCK_ADMIN_ROLE, address(oldTimelock));
        oldTimelock.renounceRole(TIMELOCK_ADMIN_ROLE, address(this));
    }

    function test_RedeployTimelock() public {
        // Record old timelock
        address oldTimelockAddr = address(oldTimelock);

        // Act as deployer
        address deployer = address(this);

        // Deploy new timelock
        TimelockControllerUpgradeable newTimelock = _deployTimelock();

        // Setup roles on new timelock
        newTimelock.grantRole(PROPOSER_ROLE, address(governor));
        newTimelock.grantRole(CANCELLER_ROLE, MANAGER_ADDRESS);
        newTimelock.grantRole(CANCELLER_ROLE, address(governor));
        newTimelock.grantRole(CANCELLER_ROLE, L2_SAFE_1);
        newTimelock.grantRole(CANCELLER_ROLE, L2_SAFE_2);
        newTimelock.grantRole(CANCELLER_ROLE, L2_SAFE_3);
        newTimelock.grantRole(TIMELOCK_ADMIN_ROLE, address(newTimelock));

        // Update governor to use new timelock
        governor.updateTimelock(newTimelock);

        // Renounce deployer admin role
        newTimelock.renounceRole(TIMELOCK_ADMIN_ROLE, deployer);

        // Verify new timelock is different
        assertNotEq(address(newTimelock), oldTimelockAddr, "New timelock should be different from old");

        // Verify governor points to new timelock
        assertEq(governor.timelock(), address(newTimelock), "Governor should point to new timelock");

        // Verify roles on new timelock
        assertTrue(newTimelock.hasRole(PROPOSER_ROLE, address(governor)), "Governor should have proposer role");
        assertTrue(newTimelock.hasRole(CANCELLER_ROLE, MANAGER_ADDRESS), "Manager should have canceller role");
        assertTrue(newTimelock.hasRole(CANCELLER_ROLE, address(governor)), "Governor should have canceller role");
        assertTrue(newTimelock.hasRole(CANCELLER_ROLE, L2_SAFE_1), "L2 Safe 1 should have canceller role");
        assertTrue(newTimelock.hasRole(CANCELLER_ROLE, L2_SAFE_2), "L2 Safe 2 should have canceller role");
        assertTrue(newTimelock.hasRole(CANCELLER_ROLE, L2_SAFE_3), "L2 Safe 3 should have canceller role");
        assertTrue(newTimelock.hasRole(EXECUTOR_ROLE, address(0)), "Anyone should be able to execute");
        assertTrue(newTimelock.hasRole(TIMELOCK_ADMIN_ROLE, address(newTimelock)), "Timelock should be self-admin");

        // Verify deployer doesn't have admin role
        assertFalse(newTimelock.hasRole(TIMELOCK_ADMIN_ROLE, deployer), "Deployer should not have admin role");

        // Verify min delay
        assertEq(newTimelock.getMinDelay(), 6 days, "Min delay should be 6 days");
    }

    function test_ProposalExecutionWithNewTimelock() public {
        // Deploy new timelock
        TimelockControllerUpgradeable newTimelock = _deployTimelock();

        // Setup roles
        newTimelock.grantRole(PROPOSER_ROLE, address(governor));
        newTimelock.grantRole(CANCELLER_ROLE, address(governor));
        newTimelock.grantRole(TIMELOCK_ADMIN_ROLE, address(newTimelock));
        newTimelock.renounceRole(TIMELOCK_ADMIN_ROLE, address(this));

        // Update governor
        governor.updateTimelock(newTimelock);

        // Create a proposal
        address[] memory targets = new address[](1);
        targets[0] = address(this);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("testFunction()");

        string memory description = "Test proposal";

        // Schedule through timelock
        vm.prank(address(governor));
        newTimelock.scheduleBatch(targets, values, calldatas, 0, keccak256(bytes(description)), 6 days);

        bytes32 proposalId =
            newTimelock.hashOperationBatch(targets, values, calldatas, 0, keccak256(bytes(description)));

        // Verify proposal is scheduled
        assertTrue(newTimelock.isOperationPending(proposalId), "Proposal should be pending");

        // Fast forward past timelock delay
        vm.warp(block.timestamp + 6 days + 1);

        // Execute (anyone can execute)
        vm.prank(address(0x9999)); // Random address
        newTimelock.executeBatch(targets, values, calldatas, 0, keccak256(bytes(description)));

        // Verify proposal was executed
        assertTrue(newTimelock.isOperationDone(proposalId), "Proposal should be executed");
    }

    function test_CancellerRoles() public {
        // Deploy new timelock
        TimelockControllerUpgradeable newTimelock = _deployTimelock();

        // Setup all roles
        newTimelock.grantRole(PROPOSER_ROLE, address(governor));
        newTimelock.grantRole(CANCELLER_ROLE, MANAGER_ADDRESS);
        newTimelock.grantRole(CANCELLER_ROLE, L2_SAFE_1);
        newTimelock.grantRole(CANCELLER_ROLE, L2_SAFE_2);
        newTimelock.grantRole(CANCELLER_ROLE, L2_SAFE_3);
        newTimelock.grantRole(TIMELOCK_ADMIN_ROLE, address(newTimelock));
        newTimelock.renounceRole(TIMELOCK_ADMIN_ROLE, address(this));

        // Create a proposal
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("testFunction()");

        // Test each canceller can cancel
        address[4] memory cancellers = [MANAGER_ADDRESS, L2_SAFE_1, L2_SAFE_2, L2_SAFE_3];

        for (uint256 i = 0; i < cancellers.length; i++) {
            // Schedule proposal
            vm.prank(address(governor));
            newTimelock.scheduleBatch(targets, values, calldatas, 0, bytes32(uint256(i)), 6 days);

            bytes32 proposalId = newTimelock.hashOperationBatch(targets, values, calldatas, 0, bytes32(uint256(i)));

            assertTrue(newTimelock.isOperationPending(proposalId), "Proposal should be pending");

            // Cancel with canceller
            vm.prank(cancellers[i]);
            newTimelock.cancel(proposalId);

            assertFalse(newTimelock.isOperationPending(proposalId), "Proposal should be cancelled");
        }
    }

    function testFunction() public pure {
        // Empty function
    }

    function _deployTimelock() internal returns (TimelockControllerUpgradeable) {
        InitializableTimelock timelockImpl = new InitializableTimelock();

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        bytes memory initData =
            abi.encodeCall(InitializableTimelock.initialize, (6 days, proposers, executors, address(this)));

        ERC1967Proxy proxy = new ERC1967Proxy(address(timelockImpl), initData);
        return TimelockControllerUpgradeable(payable(address(proxy)));
    }
}

// Simple mock governor for cleaner tests
contract MockGovernor is IGovernor {
    address public timelock;

    constructor(address _timelock) {
        timelock = _timelock;
    }

    function updateTimelock(TimelockControllerUpgradeable newTimelock) external override {
        timelock = address(newTimelock);
    }
}
