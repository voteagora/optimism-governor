// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {OptimismGovernorV5} from "src/OptimismGovernorV5.sol";
import {OptimismGovernorV6} from "src/OptimismGovernorV6.sol";
import {OptimismGovernorV6_Manageable} from "./contracts/OptimismGovernorV6_Manageable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {VotableSupplyOracle} from "src/VotableSupplyOracle.sol";
import {ProposalTypesConfigurator} from "src/ProposalTypesConfigurator.sol";
import {IOptimismGovernor} from "src/interfaces/IOptimismGovernor.sol";
import {AlligatorOPV5} from "src/alligator/AlligatorOP_V5.sol";
import {ApprovalVotingModule} from "src/modules/ApprovalVotingModule.sol";

contract UpgradeOptimismGovernorToV6Script is Script {
    // Test environment addresses
    TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(0x6E17cdef2F7c1598AD9DfA9A8acCF84B1303f43f));
    ProposalTypesConfigurator proposalTypesConfigurator =
        ProposalTypesConfigurator(payable(0x54c943f19c2E983926E2d8c060eF3a956a653aA7));
    ApprovalVotingModule module = ApprovalVotingModule(0xdd0229D72a414DC821DEc66f3Cc4eF6dB2C7b7df);
    VotableSupplyOracle votableSupplyOracle = VotableSupplyOracle(0x1b7CA7437748375302bAA8954A2447fC3FBE44CC);
    AlligatorOPV5 alligatorV5 = AlligatorOPV5(0xD89eb37D3e643aab97258C62BcF704CD00761af6);

    function run() public 
    // returns (
    //     OptimismGovernorV6_Manageable implementation,
    //     VotableSupplyOracle votableSupplyOracle,
    //     ProposalTypesConfigurator proposalTypesConfigurator,
    //     AlligatorOPV5 alligator,
    //     ApprovalVotingModule module
    // )
    {
        // address deployer = vm.rememberKey(vm.envUint("DEPLOYER_KEY"));
        address deployer = vm.rememberKey(vm.envUint("MANAGER_KEY"));

        vm.startBroadcast(deployer);
        // Pt. 1 Deploy contracts
        // votableSupplyOracle = new VotableSupplyOracle(deployer, 0);
        // proposalTypesConfigurator = new ProposalTypesConfigurator(IOptimismGovernor(address(proxy)));
        // alligator = new AlligatorOPV5();

        // Pt. 2 (opt.) Approve module -- MANAGER
        // module = new ApprovalVotingModule();
        // address prevManager = OptimismGovernorV5(payable(proxy)).manager();
        // OptimismGovernorV6_Manageable(payable(proxy))._setManager(deployer);
        // OptimismGovernorV5(payable(proxy)).setModuleApproval(0xdd0229D72a414DC821DEc66f3Cc4eF6dB2C7b7df, true);
        // OptimismGovernorV6_Manageable(payable(proxy))._setManager(prevManager);

        // Pt. 3 Set proposal types -- MANAGER
        // address prevManager = OptimismGovernorV5(payable(proxy)).manager();
        // OptimismGovernorV6_Manageable(payable(proxy))._setManager(deployer);
        // proposalTypesConfigurator.setProposalType(0, 3000, 5000, "Default");
        // OptimismGovernorV6_Manageable(payable(proxy))._setManager(prevManager);

        // Pt. 4 Set addresses in code
        // Set addresses in `OptimismGovernorV6`
        // (only on test env) Set correct governor address in `Alligator`

        // Pt. 5 Upgrade governor
        // implementation = new OptimismGovernorV6_Manageable();
        // proxy.upgradeTo(address(implementation));

        vm.stopBroadcast();
    }
}
