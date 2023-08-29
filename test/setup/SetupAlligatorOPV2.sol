// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/forge-std/src/Test.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";
import "src/alligator/AlligatorOPV2.sol";
import {IAlligatorOPV2} from "src/interfaces/IAlligatorOPV2.sol";
import {OptimismGovernorV6} from "src/OptimismGovernorV6.sol";
import {OptimismGovernorV2} from "src/OptimismGovernorV2.sol";
import {OptimismGovernorV6Mock} from "../mocks/OptimismGovernorV6Mock.sol";
import "../utils/Addresses.sol";
import {GovernanceToken as OptimismToken} from "src/lib/OptimismToken.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
// import {IGovernorMock} from "../mock/IGovernorMock.sol";

abstract contract SetupAlligatorOPV2 is Test {
    // =============================================================
    //                             ERRORS
    // =============================================================

    error BadSignature();
    error NullVotingPower();
    error ZeroVotesToCast();
    error NotDelegated(address from, address to);
    error TooManyRedelegations(address from, address to);
    error NotValidYet(address from, address to, uint256 willBeValidFrom);
    error NotValidAnymore(address from, address to, uint256 wasValidUntil);
    error TooEarly(address from, address to, uint256 blocksBeforeVoteCloses);
    error InvalidCustomRule(address from, address to, address customRule);
    error AlreadyVoted(address voter, uint256 proposalId);

    // =============================================================
    //                             EVENTS
    // =============================================================

    event ProxyDeployed(address indexed owner, BaseRules proxyRules, address proxy);
    event SubDelegation(address indexed from, address indexed to, SubdelegationRules subdelegationRules);
    event SubDelegations(address indexed from, address[] to, SubdelegationRules subdelegationRules);
    event ProxySubdelegation(
        address indexed proxy, address indexed from, address indexed to, SubdelegationRules subdelegationRules
    );
    event ProxySubdelegations(
        address indexed proxy, address indexed from, address[] to, SubdelegationRules subdelegationRules
    );
    event VoteCast(
        address indexed proxy, address indexed voter, address[] authority, uint256 proposalId, uint8 support
    );
    event VotesCast(
        address[] proxies, address indexed voter, address[][] authorities, uint256 proposalId, uint8 support
    );

    // =============================================================
    //                       IMMUTABLE STORAGE
    // =============================================================

    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    bytes32 internal constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

    // =============================================================
    //                            STORAGE
    // =============================================================

    OptimismToken internal op = new OptimismToken();
    IAlligatorOPV2 internal alligator;
    OptimismGovernorV6Mock internal governor;
    address internal proxy1;
    address internal proxy2;
    address internal proxy3;
    BaseRules internal baseRules = BaseRules(
        255, // Max redelegations
        0,
        0,
        0,
        address(0)
    );
    bytes32 baseRulesHash = keccak256(abi.encode(baseRules));
    SubdelegationRules internal subdelegationRules = SubdelegationRules({
        baseRules: baseRules,
        allowanceType: AllowanceType.Relative,
        allowance: 5e4 // 50%
            // allowance: 1e5 // 100%
    });

    address admin = makeAddr("admin");
    address manager = makeAddr("manager");
    string description = "a nice description";
    address voter = makeAddr("voter");
    address altVoter = makeAddr("altVoter");
    address altVoter2 = makeAddr("altVoter2");
    uint256 proposalId;

    // =============================================================
    //                             SETUP
    // =============================================================

    function setUp() public virtual {
        governor = new OptimismGovernorV6Mock();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(governor),
            admin,
            abi.encodeCall(OptimismGovernorV2.initialize, (IVotesUpgradeable(address(op)), manager))
        );
        governor = OptimismGovernorV6Mock(payable(proxy));

        alligator = new AlligatorOPV2(address(governor), address(op), address(this));
        proxy1 = alligator.create(address(this), baseRules);
        proxy2 = alligator.create(address(Utils.alice), baseRules);
        proxy3 = alligator.create(address(Utils.bob), baseRules);

        vm.startPrank(op.owner());
        op.mint(address(this), 1e18);
        op.mint(voter, 1e18);
        op.mint(altVoter, 1e20);
        op.mint(altVoter2, 1e18);
        vm.stopPrank();

        vm.prank(address(this));
        op.delegate(address(this));
        vm.prank(voter);
        op.delegate(proxy1);
        vm.prank(altVoter);
        op.delegate(proxy2);
        vm.prank(altVoter2);
        op.delegate(proxy3);

        proposalId = _propose("Test");
    }

    function _propose(string memory propDescription) internal returns (uint256 propId) {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        vm.prank(manager);
        propId = governor.propose(targets, values, calldatas, propDescription);
        vm.roll(block.number + 10);
    }

    string private checkpointLabel;
    uint256 private checkpointGasLeft = 1; // Start the slot warm.

    function startMeasuringGas(string memory label) internal virtual {
        checkpointLabel = label;

        checkpointGasLeft = gasleft();
    }

    function stopMeasuringGas() internal virtual {
        uint256 checkpointGasLeft2 = gasleft();

        // Subtract 100 to account for the warm SLOAD in startMeasuringGas.
        uint256 gasDelta = checkpointGasLeft - checkpointGasLeft2 - 100;

        emit log_named_uint(string(abi.encodePacked(checkpointLabel, " Gas")), gasDelta);
    }
}

interface DelegateToken is IERC721 {
    function delegate(address delegatee) external;
}
