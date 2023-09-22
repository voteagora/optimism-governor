// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {OptimismGovernorV6} from "src/OptimismGovernorV6.sol";
import {VotableSupplyOracle} from "src/VotableSupplyOracle.sol";
import {ProposalTypesConfigurator} from "src/ProposalTypesConfigurator.sol";
import {IOptimismGovernor} from "src/interfaces/IOptimismGovernor.sol";
import {AlligatorOPV5} from "src/alligator/AlligatorOP_V5.sol";

contract DeployOptimismGovernorV6Script is Script {
    function run()
        public
        returns (
            OptimismGovernorV6 governor,
            VotableSupplyOracle votableSupplyOracle,
            ProposalTypesConfigurator proposalTypesConfigurator,
            AlligatorOPV5 alligator
        )
    {
        address deployer = vm.rememberKey(vm.envUint("DEPLOYER_KEY"));

        vm.startBroadcast(deployer);

        governor = new OptimismGovernorV6();
        votableSupplyOracle = new VotableSupplyOracle(deployer, 0);
        proposalTypesConfigurator = new ProposalTypesConfigurator(IOptimismGovernor(address(governor)));
        alligator = new AlligatorOPV5();

        vm.stopBroadcast();
    }
}
