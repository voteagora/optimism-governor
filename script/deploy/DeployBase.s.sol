// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {OptimismGovernor} from "src/OptimismGovernor.sol";
import {VotableSupplyOracle} from "src/VotableSupplyOracle.sol";
import {IProposalTypesConfigurator, ProposalTypesConfigurator} from "src/ProposalTypesConfigurator.sol";
import {GovernanceToken} from "src/GovernanceToken.sol";
import {ApprovalVotingModule} from "src/modules/ApprovalVotingModule.sol";
import {OptimisticModule_SocialSignalling} from "src/modules/OptimisticModule.sol";
import {AlligatorOP} from "src/alligator/AlligatorOP.sol";
import {AlligatorOP} from "src/alligator/AlligatorOP.sol";
import {IVotingToken} from "src/interfaces/IVotingToken.sol";
import {IVotableSupplyOracle} from "src/interfaces/IVotableSupplyOracle.sol";

import {Timelock, TimelockControllerUpgradeable} from "test/mocks/TimelockMock.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

abstract contract DeployBase is Script {
    GovernanceToken token;
    VotableSupplyOracle votableSupplyOracle;
    ProposalTypesConfigurator proposalTypesConfigurator;
    Timelock timelock;
    OptimismGovernor governor;

    address governorManager;

    constructor(address _governorManager) {
        governorManager = _governorManager;
    }

    function setup() internal {
        vm.startBroadcast();

        // Read caller information.
        (, address deployer,) = vm.readCallers();

        address proxyAdmin = deployer; // Semantics

        // Deploy Token
        token = new GovernanceToken();

        // Deploy Oracle
        votableSupplyOracle = new VotableSupplyOracle(deployer, 0);

        // Deploy ProposalTypesConfigurator
        proposalTypesConfigurator = new ProposalTypesConfigurator();

        // Deploy Alligator
        AlligatorOP alligatorImplementation = new AlligatorOP();

        address governorProxyAddress = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 4); // proxy deploy
        address alligator = address(
            new ERC1967Proxy(
                address(alligatorImplementation),
                abi.encodeWithSelector(AlligatorOP(alligatorImplementation).initialize.selector, deployer, address(token), address(governorProxyAddress))
            )
        );

        // Deploy timelock
        timelock = Timelock(payable(new TransparentUpgradeableProxy(address(new Timelock()), governorManager, "")));

        // Deploy governor impl
        address governorImplementation = address(new OptimismGovernor());

        // Deploy Governor
        address governorProxy = address(
            new TransparentUpgradeableProxy(
                governorImplementation,
                proxyAdmin,
                abi.encodeCall(
                    OptimismGovernor.initialize,
                    (
                        IVotingToken(address(token)),
                        IVotableSupplyOracle(address(votableSupplyOracle)),
                        governorManager,
                        address(alligator),
                        timelock,
                        IProposalTypesConfigurator(proposalTypesConfigurator),
                        new IProposalTypesConfigurator.ProposalType[](0)
                    )
                )
            )
        );

        assert(governorProxy == governorProxyAddress);

        governor = OptimismGovernor(payable(governorProxy));

        // Configuration for gov & alligator
        ApprovalVotingModule approvalModule = new ApprovalVotingModule(address(governor));
        OptimisticModule_SocialSignalling optimisticModule = new OptimisticModule_SocialSignalling(address(governor));

        timelock.initialize(2 days, governorProxy, governorManager);
        // governor.setModuleApproval(address(approvalModule), true);
        // governor.setModuleApproval(address(optimisticModule), true);

        // proposalTypesConfigurator.setProposalType(0, 3_000, 5_000, "Default", "Lorem Ipsum", address(0));
        // proposalTypesConfigurator.setProposalType(1, 5_000, 7_000, "Alt - Approval", "Lorem Ipsum", address(approvalModule));
        // proposalTypesConfigurator.setProposalType(2, 0, 0, "Optimistic", "Lorem Ipsum", address(optimisticModule));

        // Mint and set total supply
        // token.mint ...
        // votableSupplyOracle._updateVotableSupply(token.totalSupply());

        vm.stopBroadcast();
    }

    // Exclude from coverage report
    function test() public virtual {}
}
