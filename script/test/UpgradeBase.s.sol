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

abstract contract UpgradeBase is Script {
    ProxyAdmin proxyAdmin;
    OptimismGovernor governor;
    AlligatorOP alligator;
    VotableSupplyOracle oracle;
    ProposalTypesConfigurator ptc;
    Timelock timelock;
    address owner;

    constructor(address _proxyAdmin, address _owner, address _governor, address _alligator, address _oracle, address _ptc, address _timelock) {

        if (_proxyAdmin != address(0)) {
            proxyAdmin = ProxyAdmin(_proxyAdmin);
        }

        owner = _owner;

        governor = OptimismGovernor(payable(_governor));
        alligator = AlligatorOP(_alligator);
        oracle = VotableSupplyOracle(_oracle);
        ptc = ProposalTypesConfigurator(_ptc);
        timelock = Timelock(payable(_timelock));
    }

    function setup() internal {
        vm.startBroadcast();

        // Read caller information.
        (, address deployer,) = vm.readCallers();

        // Deploy new governor impl
        address governorImplementation = address(new OptimismGovernor());
        TransparentUpgradeableProxy govProxy = TransparentUpgradeableProxy(payable(governor));

        if (owner == address(0)) {
            assert(deployer == proxyAdmin.owner());
            proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(governor)), governorImplementation);
            assert(proxyAdmin.getProxyImplementation(govProxy) == governorImplementation);
        }

        else {
            govProxy.upgradeTo(governorImplementation);
        }

        /*
        governor.reinitialize(
            address(alligator), // Alligator
            address(oracle), // VotableSupplyOracle
            address(ptc), // ProposalTypesConfigurator
            timelock // Timelock
            /* address authorizedProposer
        );
        */

        vm.stopBroadcast();
    }

    // Exclude from coverage report
    function test() public virtual {}
}
