// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ProposalOption, ProposalSettings, PassingCriteria} from "../src/modules/ApprovalVotingModule.sol";
import {OptimismGovernorV5} from "../src/OptimismGovernorV5.sol";
import {VotingModule} from "../src/modules/VotingModule.sol";

contract TestProposeWithModuleScript is Script {
    address receiver1 = makeAddr("receiver1");
    address receiver2 = makeAddr("receiver2");
    address internal op = 0x4200000000000000000000000000000000000042;
    OptimismGovernorV5 governor = OptimismGovernorV5(payable(0x6E17cdef2F7c1598AD9DfA9A8acCF84B1303f43f));
    VotingModule approvalVotingModule = VotingModule(0x54A8fCBBf05ac14bEf782a2060A8C752C7CC13a5);

    function run() public {
        address deployer = vm.rememberKey(vm.envUint("MANAGER_KEY"));

        bytes memory proposalData = _formatProposalData(true, false);
        string memory description = "# Approval Voting Test 1 /n/n Hello op";

        vm.startBroadcast(deployer);

        governor.proposeWithModule(approvalVotingModule, proposalData, description);

        vm.stopBroadcast();
    }

    function _formatProposalData(bool budgetExceeded, bool isBudgetOp)
        internal
        view
        returns (bytes memory proposalData)
    {
        address[] memory targets1 = new address[](1);
        uint256[] memory values1 = new uint256[](1);
        bytes[] memory calldatas1 = new bytes[](1);
        // Send 0.01 ether to receiver1
        targets1[0] = receiver1;
        values1[0] = budgetExceeded ? 0.6 ether : 0.01 ether;

        address[] memory targets2 = new address[](2);
        uint256[] memory values2 = new uint256[](2);
        bytes[] memory calldatas2 = new bytes[](2);
        // Transfer 100 OP tokens to receiver2
        targets2[0] = op;
        calldatas2[0] = abi.encodeCall(IERC20.transfer, (receiver1, budgetExceeded ? 6e17 : 100));
        // Send 0.01 ether to receiver2, and emit call to test calls to targets different than budgetTokens are ignored
        targets2[1] = receiver2;
        values2[1] = budgetExceeded ? 0.6 ether : 0.01 ether;
        calldatas2[1] = calldatas2[0];

        ProposalOption[] memory options = new ProposalOption[](3);
        options[0] = ProposalOption(targets1, values1, calldatas1, "option 1");
        options[1] = ProposalOption(targets2, values2, calldatas2, "option 2");

        address[] memory targets3 = new address[](1);
        uint256[] memory values3 = new uint256[](1);
        bytes[] memory calldatas3 = new bytes[](1);
        targets3[0] = op;
        calldatas3[0] = abi.encodeCall(IERC20.transferFrom, (address(governor), receiver1, budgetExceeded ? 6e17 : 100));

        options[2] = ProposalOption(targets3, values3, calldatas3, "option 3");
        ProposalSettings memory settings = ProposalSettings({
            maxApprovals: 2,
            criteria: uint8(PassingCriteria.TopChoices),
            criteriaValue: 2,
            budgetToken: isBudgetOp ? op : address(0),
            budgetAmount: 1e18
        });

        proposalData = abi.encode(options, settings);
    }
}
