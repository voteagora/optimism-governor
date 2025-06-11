// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {OptimismGovernor} from "src/OptimismGovernor.sol";
import {VotableSupplyOracle} from "src/VotableSupplyOracle.sol";
import {IProposalTypesConfigurator, ProposalTypesConfigurator} from "src/ProposalTypesConfigurator.sol";
import {GovernanceToken} from "src/GovernanceToken.sol";
import {AlligatorOP} from "src/alligator/AlligatorOP.sol";

import {Timelock, TimelockControllerUpgradeable} from "test/mocks/TimelockMock.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract UpgradeGovernor is Script {
    ProxyAdmin proxyAdmin = ProxyAdmin(0x7d377a66c4A803bbB457b4541e5ec62b1dCe2Ad3);
    OptimismGovernor governor = OptimismGovernor(payable(0x368723068b6C762b416e5A7d506a605E8b816C22));
    AlligatorOP alligator = AlligatorOP(0x5d729d4c0BF5d0a2Fa0F801c6e0023BD450c4fd6);
    VotableSupplyOracle oracle = VotableSupplyOracle(0x2451dAF2153B1293Da2abF19C36c450321835C55);
    ProposalTypesConfigurator ptc = ProposalTypesConfigurator(0xb88131610ff4D7D46050c9d1DEE413f8b6b8A5bd);
    Timelock timelock = Timelock(payable(0xf8D15c3132eFA557989A1C9331B6667Ca8Caa3a9));
 
    function run() external {
        vm.startBroadcast();

        // Read caller information.
        (, address deployer,) = vm.readCallers();
        assert(deployer == proxyAdmin.owner());

        // Deploy new governor impl
        address governorImplementation = address(new OptimismGovernor());
        TransparentUpgradeableProxy govProxy = TransparentUpgradeableProxy(payable(governor));

        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(governor)), governorImplementation);

        assert(proxyAdmin.getProxyImplementation(govProxy) == governorImplementation);

        governor.reinitialize(
            address(alligator), // Alligator
            address(oracle), // VotableSupplyOracle
            address(ptc), // ProposalTypesConfigurator
            timelock // Timelock
            /* address authorizedProposer */
        );

        vm.stopBroadcast();
    }

    // Exclude from coverage report
    function test() public virtual {}
}

