// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {OptimismGovernorV4} from "../src/OptimismGovernorV4.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract OptimismGovernorV4UpgradeTest is Test {
    TransparentUpgradeableProxy internal constant proxy = TransparentUpgradeableProxy(payable(0xcDF27F107725988f2261Ce2256bDfCdE8B382B10));
    OptimismGovernorV4 internal governor = OptimismGovernorV4(payable(address(proxy)));
    address internal constant admin = 
0x2501c477D0A35545a387Aa4A3EEe4292A9a8B3F0;
    address internal constant manager = 0xE4553b743E74dA3424Ac51f8C1E586fd43aE226F;
    
    uint256 internal constant proposalIdDelegateSuspension = 27878184270712708211495755831534918916136653803154031118511283847257927730426;
    uint256 internal constant proposalIdBedrock = 114732572201709734114347859370226754519763657304898989580338326275038680037913;
    uint256 internal constant proposalIdTestVote3 = 103606400798595803012644966342403441743733355496979747669804254618774477345292;
        

    function setUp() public {
        // Block number 88792077 is ~ Apr-11-2023 01:30:52 AM UTC
        vm.createSelectFork("https://mainnet.optimism.io", 88792077);

        OptimismGovernorV4 implementation = new OptimismGovernorV4();

        vm.prank(admin);
        proxy.upgradeTo(address(implementation));
    }

    function testInitializeCheckpoint() public {
        // Checkpoint[2]
        assertEq(governor.quorumNumerator(83241937), 149);
        // Checkpoint[3]
        assertEq(governor.quorumNumerator(83241938), 709);
        // Checkpoint[4]
        assertEq(governor.quorumNumerator(83249765), 280);

        // Proposal "Delegate Suspension": Defeated
        assertEq(uint256(governor.state(proposalIdDelegateSuspension)), 3);
        // Proposal "Bedrock": Defeated
        assertEq(uint256(governor.state(proposalIdBedrock)), 3);
        // Proposal "Test Vote 3": Succeeded
        assertEq(uint256(governor.state(proposalIdTestVote3)), 4);

        vm.prank(manager);
        governor._initializeCheckpoint();

        // Checkpoint[2]: preserved
        assertEq(governor.quorumNumerator(83241937), 149);
        // Checkpoint[3]: updated
        assertEq(governor.quorumNumerator(83241938), 149);
        // Checkpoint[4]: preserved
        assertEq(governor.quorumNumerator(83249765), 280);

        // Proposal "Delegate Suspension": Succeeded
        assertEq(uint256(governor.state(proposalIdDelegateSuspension)), 4);
        // Proposal "Bedrock": Succeeded
        assertEq(uint256(governor.state(proposalIdBedrock)), 4);
        // Proposal "Test Vote 3": Succeeded
        assertEq(uint256(governor.state(proposalIdTestVote3)), 4);
    }
}
