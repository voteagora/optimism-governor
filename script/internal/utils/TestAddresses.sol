// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {VotableSupplyOracle} from "src/VotableSupplyOracle.sol";
import {ProposalTypesConfigurator} from "src/ProposalTypesConfigurator.sol";
import {AlligatorOPV5} from "src/alligator/AlligatorOP_V5.sol";
import {ApprovalVotingModule} from "src/modules/ApprovalVotingModule.sol";
import {IOptimismGovernor} from "src/interfaces/IOptimismGovernor.sol";
import {OptimismGovernorV6_Manageable} from "../../contracts/OptimismGovernorV6_Manageable.sol";

contract TestAddresses {
    OptimismGovernorV6_Manageable governor =
        OptimismGovernorV6_Manageable(payable(0x6E17cdef2F7c1598AD9DfA9A8acCF84B1303f43f));

    ProposalTypesConfigurator proposalTypesConfigurator =
        ProposalTypesConfigurator(payable(0x54c943f19c2E983926E2d8c060eF3a956a653aA7));

    ApprovalVotingModule module = ApprovalVotingModule(0xdd0229D72a414DC821DEc66f3Cc4eF6dB2C7b7df);

    VotableSupplyOracle votableSupplyOracle = VotableSupplyOracle(0x1b7CA7437748375302bAA8954A2447fC3FBE44CC);

    AlligatorOPV5 alligatorV5 = AlligatorOPV5(0xD89eb37D3e643aab97258C62BcF704CD00761af6);
}
