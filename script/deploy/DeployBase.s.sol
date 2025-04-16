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
import {IVotingToken} from "src/interfaces/IVotingToken.sol";
import {IVotableSupplyOracle} from "src/interfaces/IVotableSupplyOracle.sol";

import {Timelock, TimelockControllerUpgradeable} from "test/mocks/TimelockMock.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

abstract contract DeployBase is Script {
    ProxyAdmin proxyAdmin;
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

        // Deploy Token
        token = new GovernanceToken();

        // Deploy ProxyAdmin
        proxyAdmin = new ProxyAdmin();

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
        timelock = Timelock(payable(new TransparentUpgradeableProxy(address(new Timelock()), address(proxyAdmin), "")));

        // Deploy governor impl
        address governorImplementation = address(new OptimismGovernor());

        // Deploy Governor
        address governorProxy = address(
            new TransparentUpgradeableProxy(
                governorImplementation,
                address(proxyAdmin),
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
        governor.setModuleApproval(address(approvalModule), true);
        governor.setModuleApproval(address(optimisticModule), true);

        proposalTypesConfigurator.setProposalType(0, 3_000, 5_000, "Default", "Lorem Ipsum", address(0));
        proposalTypesConfigurator.setProposalType(1, 5_000, 7_000, "Alt - Approval", "Lorem Ipsum", address(approvalModule));
        proposalTypesConfigurator.setProposalType(2, 0, 0, "Optimistic", "Lorem Ipsum", address(optimisticModule));

        // Mint and set total supply
         address[11] memory holders = [
            0x1d671d1B191323A38490972D58354971E5c1cd2A,
            0x648BFC4dB7e43e799a84d0f607aF0b4298F932DB,
            0xab499F5784Bc91AB9452a69915959AF20326D159,
            0xFdFC6E1BbEc01288447222fC8F1AEE55a7C72b7B,
            0xAce36342FfB271DFB8a844e028A0ead5aD51af20,
            0xC950b9F32259860f4731D318CB5a28B2dB892f88,
            0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            0x603F5A389d893624A648424aD58a33205F8fC59c,
            0xcC0B26236AFa80673b0859312a7eC16d2b72C1ea,
            0x3D1F084A0580d48db8108E2a3260b699f9343833,
            deployer
        ];

        for (uint8 i = 0; i < holders.length; i++) {
            token.mint(holders[i], 100_000 ether);
        }

        votableSupplyOracle._updateVotableSupply(token.totalSupply());

        vm.stopBroadcast();
    }

    // Exclude from coverage report
    function test() public virtual {}
}
