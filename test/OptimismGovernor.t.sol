// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IGovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";
import {Timelock, TimelockControllerUpgradeable} from "test/mocks/TimelockMock.sol";
import {TokenMock} from "test/mocks/TokenMock.sol";
import {VotingModule} from "src/modules/VotingModule.sol";
import {ProposalTypesConfigurator, IProposalTypesConfigurator} from "src/ProposalTypesConfigurator.sol";
import {
    ApprovalVotingModule,
    ProposalOption,
    ProposalSettings,
    PassingCriteria
} from "src/modules/ApprovalVotingModule.sol";
import {
    OptimisticModule_SocialSignalling as OptimisticModule,
    ProposalSettings as OptimisticProposalSettings
} from "src/modules/OptimisticModule.sol";
import {OptimismGovernorMock, OptimismGovernor} from "test/mocks/OptimismGovernorMock.sol";
import {ApprovalVotingModuleMock} from "test/mocks/ApprovalVotingModuleMock.sol";
import {VoteType} from "test/ApprovalVotingModule.t.sol";
import {ExecutionTargetFake} from "test/fakes/ExecutionTargetFake.sol";
import {IVotingToken} from "src/interfaces/IVotingToken.sol";
import {IVotableSupplyOracle} from "src/interfaces/IVotableSupplyOracle.sol";
import {VotableSupplyOracle} from "src/VotableSupplyOracle.sol";

enum ProposalState {
    Pending,
    Active,
    Canceled,
    Defeated,
    Succeeded,
    Queued,
    Expired,
    Executed
}

contract OptimismGovernorTest is Test {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description,
        uint8 proposalType
    );
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address indexed votingModule,
        bytes proposalData,
        uint256 startBlock,
        uint256 endBlock,
        string description,
        uint8 proposalType
    );

    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address votingModule,
        bytes proposalData,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );

    event VoteCastWithParams(
        address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason, bytes params
    );

    event ProposalCanceled(uint256 proposalId);
    event ProposalExecuted(uint256 proposalId);
    event ProposalTypeUpdated(uint256 indexed proposalId, uint8 proposalType);
    event ManagerSet(address indexed oldManager, address indexed newManager);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidProposalType(uint8 proposalType);
    error InvalidProposalId();
    error InvalidProposedTxForType();
    error InvalidProposalLength();
    error InvalidEmptyProposal();
    error InvalidVotesBelowThreshold();
    error InvalidProposalExists();
    error NotManagerOrTimelock();

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address deployer = makeAddr("deployer");
    ProposalTypesConfigurator public proposalTypesConfigurator;
    VotableSupplyOracle internal votableSupplyOracle;
    Timelock public timelock;
    ExecutionTargetFake public targetFake;
    address internal proxyAdmin = makeAddr("proxyAdmin");
    address internal manager = makeAddr("manager");
    address internal minter = makeAddr("minter");
    string description = "a nice description";
    // helper to keep track of proposal types
    uint256 proposalTypesIndex = 1;
    uint256 timelockDelay;

    TokenMock internal govToken;
    address public implementation;
    address internal governorProxy;
    OptimismGovernorMock public governor;
    ApprovalVotingModuleMock internal module;
    OptimisticModule internal optimisticModule;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        vm.startPrank(deployer);

        // Deploy token
        govToken = new TokenMock(minter);

        // Deploy Proposal Types Configurator
        proposalTypesConfigurator = new ProposalTypesConfigurator();

        // Deploy votable supply oracle
        votableSupplyOracle = new VotableSupplyOracle(address(this), 0);

        // Deploy timelock
        timelock = Timelock(payable(new TransparentUpgradeableProxy(address(new Timelock()), proxyAdmin, "")));

        // Deploy governor impl
        implementation = address(new OptimismGovernorMock());

        // Deploy governor proxy
        governorProxy = address(
            new TransparentUpgradeableProxy(
                implementation,
                proxyAdmin,
                abi.encodeCall(
                    OptimismGovernor.initialize,
                    (
                        IVotingToken(address(govToken)),
                        IVotableSupplyOracle(address(votableSupplyOracle)),
                        manager,
                        address(0),
                        timelock,
                        IProposalTypesConfigurator(proposalTypesConfigurator),
                        new IProposalTypesConfigurator.ProposalType[](0)
                    )
                )
            )
        );
        governor = OptimismGovernorMock(payable(governorProxy));

        // Initialize timelock
        timelockDelay = 2 days;
        timelock.initialize(timelockDelay, governorProxy, manager);
        vm.stopPrank();

        // Deploy modules
        module = new ApprovalVotingModuleMock(address(governor));
        optimisticModule = new OptimisticModule(address(governor));

        // do manager stuff
        vm.startPrank(manager);
        governor.setModuleApproval(address(module), true);
        governor.setModuleApproval(address(optimisticModule), true);
        proposalTypesConfigurator.setProposalType(0, 3_000, 5_000, "Default", "Lorem Ipsum", address(0));
        proposalTypesConfigurator.setProposalType(1, 5_000, 7_000, "Alt", "Lorem Ipsum", address(module));
        proposalTypesConfigurator.setProposalType(2, 0, 0, "Optimistic", "Lorem Ipsum", address(optimisticModule));
        vm.stopPrank();
        targetFake = new ExecutionTargetFake();
    }

    /**
     * @notice Generates the scope key defined as the contract address combined with the function selector
     * @param contractAddress Address of the contract to be enforced by the scope
     * @param selector A byte4 function selector on the contract to be enforced by the scope
     */
    function _pack(address contractAddress, bytes4 selector) internal pure returns (bytes24 result) {
        bytes20 left = bytes20(contractAddress);
        assembly ("memory-safe") {
            left := and(left, shl(96, not(0)))
            selector := and(selector, shl(224, not(0)))
            result := or(left, shr(160, selector))
        }
    }

    function _formatProposalData(uint256 _proposalTargetCalldata) public virtual returns (bytes memory proposalData) {
        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");

        address[] memory targets1 = new address[](1);
        uint256[] memory values1 = new uint256[](1);
        bytes[] memory calldatas1 = new bytes[](1);
        // Call executeCallback and send 0.01 ether to receiver1
        vm.deal(address(timelock), 0.01 ether);
        targets1[0] = receiver1;
        values1[0] = 0.01 ether;
        calldatas1[0] = abi.encodeWithSelector(this.executeCallback.selector);

        address[] memory targets2 = new address[](2);
        uint256[] memory values2 = new uint256[](2);
        bytes[] memory calldatas2 = new bytes[](2);
        // Send 0.01 ether to receiver2
        targets2[0] = receiver2;
        values2[0] = 0.01 ether;
        // Call SetNumber on ExecutionTargetFake
        targets2[1] = address(targetFake);
        calldatas2[1] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        ProposalOption[] memory options = new ProposalOption[](2);
        options[0] = ProposalOption(0, targets1, values1, calldatas1, "option 1");
        options[1] = ProposalOption(0, targets2, values2, calldatas2, "option 2");
        ProposalSettings memory settings = ProposalSettings({
            maxApprovals: 1,
            criteria: uint8(PassingCriteria.TopChoices),
            criteriaValue: 1,
            budgetToken: address(0),
            budgetAmount: 1 ether
        });

        return abi.encode(options, settings);
    }

    function executeCallback() public payable virtual {}

    function _assumeZeroBalance(address _actor) public view {
        vm.assume(_actor != address(module));
    }

    function _mintAndDelegate(address _actor, uint256 _amount) internal {
        vm.assume(_actor != address(0));
        vm.assume(_actor != proxyAdmin);
        vm.prank(minter);
        govToken.mint(_actor, _amount);
        vm.prank(_actor);
        govToken.delegate(_actor);
    }

    function _managerOrTimelock(uint256 _actorSeed) internal view returns (address) {
        if (_actorSeed % 2 == 1) return manager;
        else return governor.timelock();
    }

    function _createValidProposal() internal returns (uint256) {
        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.startPrank(manager);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);
        // ProposalThreshold is not set, so it defaults to 0.
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        vm.stopPrank();
        return proposalId;
    }
}

contract Initialize is OptimismGovernorTest {
    function testFuzz_InitializesState(address _token, address _manager, address _timelock) public virtual {
        ProposalTypesConfigurator _proposalTypesConfigurator = new ProposalTypesConfigurator();
        IProposalTypesConfigurator.ProposalType[] memory _proposalTypes =
            new IProposalTypesConfigurator.ProposalType[](4);
        _proposalTypes[0] = IProposalTypesConfigurator.ProposalType(1_500, 9_000, "Default", "Lorem Ipsum", address(0));
        _proposalTypes[1] = IProposalTypesConfigurator.ProposalType(3_500, 7_000, "Alt", "Lorem Ipsum", address(0));
        _proposalTypes[2] = IProposalTypesConfigurator.ProposalType(7_500, 3_100, "Whatever", "Lorem Ipsum", address(0));
        _proposalTypes[3] =
            IProposalTypesConfigurator.ProposalType(0, 0, "Optimistic", "Lorem Ipsum", address(optimisticModule));
        OptimismGovernor _governor = OptimismGovernor(
            payable(
                new TransparentUpgradeableProxy(
                    implementation,
                    proxyAdmin,
                    abi.encodeCall(
                        OptimismGovernor.initialize,
                        (
                            IVotingToken(_token),
                            IVotableSupplyOracle(address(0)),
                            _manager,
                            address(0),
                            TimelockControllerUpgradeable(payable(_timelock)),
                            IProposalTypesConfigurator(address(_proposalTypesConfigurator)),
                            _proposalTypes
                        )
                    )
                )
            )
        );
        assertEq(address(_governor.token()), _token);
        assertEq(_governor.manager(), _manager);
        assertEq(_governor.timelock(), address(_timelock));
        assertEq(_proposalTypesConfigurator.proposalTypes(0), _proposalTypes[0]);
        assertEq(_proposalTypesConfigurator.proposalTypes(1), _proposalTypes[1]);
        assertEq(_proposalTypesConfigurator.proposalTypes(2), _proposalTypes[2]);
        assertEq(_proposalTypesConfigurator.proposalTypes(3), _proposalTypes[3]);
    }

    function assertEq(
        IProposalTypesConfigurator.ProposalType memory a,
        IProposalTypesConfigurator.ProposalType memory b
    ) internal pure {
        assertEq(a.quorum, b.quorum);
        assertEq(a.approvalThreshold, b.approvalThreshold);
        assertEq(a.name, b.name);
    }
}

contract Propose is OptimismGovernorTest {
    function testFuzz_CreatesProposalWhenThresholdIsMet(
        address _actor,
        uint256 _proposalThreshold,
        uint256 _actorBalance
    ) public virtual {
        _actor = manager;
        _proposalThreshold = bound(_proposalThreshold, 0, type(uint208).max);
        _actorBalance = bound(_actorBalance, _proposalThreshold, type(uint208).max);
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(manager);
        governor.setProposalThreshold(_proposalThreshold);

        // Give actor enough tokens to meet proposal threshold.
        vm.prank(minter);
        govToken.mint(_actor, _actorBalance);
        vm.startPrank(_actor);
        govToken.delegate(_actor);
        vm.roll(vm.getBlockNumber() + 1);

        uint256 proposalId;
        proposalId = governor.propose(targets, values, calldatas, "Test", 0);
        vm.stopPrank();
        assertGt(governor.proposalSnapshot(proposalId), 0);
    }

    function testFuzz_CreatesProposalAsManager(uint256 _proposalThreshold) public virtual {
        _proposalThreshold = bound(_proposalThreshold, 0, type(uint208).max);
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(manager);
        governor.setProposalThreshold(_proposalThreshold);

        uint256 proposalId;
        vm.prank(manager);
        proposalId = governor.propose(targets, values, calldatas, "Test", 0);
        assertGt(governor.proposalSnapshot(proposalId), 0);
    }

    function testRevert_WithType_InvalidProposalType() public virtual {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);
        uint8 invalidPropType = 3;

        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(InvalidProposalType.selector, invalidPropType));
        governor.propose(targets, values, calldatas, "Test", invalidPropType);
    }

    function testRevert_proposalAlreadyCreated() public virtual {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.startPrank(manager);
        governor.propose(targets, values, calldatas, "Test", 0);

        vm.expectRevert(InvalidProposalExists.selector);
        governor.propose(targets, values, calldatas, "Test", 0);
        vm.stopPrank();
    }
}

contract ProposeWithModule is OptimismGovernorTest {
    function testFuzz_CreatesProposalWhenProposalThresholdMet(
        address _actor,
        uint256 _proposalThreshold,
        uint256 _actorBalance
    ) public virtual {
        _actor = manager;
        _proposalThreshold = bound(_proposalThreshold, 0, type(uint208).max);
        _actorBalance = bound(_actorBalance, _proposalThreshold, type(uint208).max);
        uint8 _proposalType = 1;

        vm.prank(manager);
        governor.setProposalThreshold(_proposalThreshold);

        // Give actor enough tokens to meet proposal threshold.
        vm.prank(minter);
        govToken.mint(_actor, _actorBalance);
        vm.startPrank(_actor);
        govToken.delegate(_actor);
        vm.roll(vm.getBlockNumber() + 1);

        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        bytes memory proposalData = _formatProposalData(0);
        uint256 proposalId =
            governor.hashProposalWithModule(address(module), proposalData, keccak256(bytes(description)));

        vm.expectEmit();
        emit ProposalCreated(
            proposalId, _actor, address(module), proposalData, snapshot, deadline, description, _proposalType
        );
        if (_proposalType > 0) {
            governor.proposeWithModule(VotingModule(module), proposalData, description, _proposalType);
        } else {
            governor.proposeWithModule(VotingModule(module), proposalData, description, 0);
        }
        vm.stopPrank();

        assertEq(governor.proposals(proposalId).proposalType, _proposalType);
        assertEq(governor.proposalSnapshot(proposalId), snapshot);
        assertEq(governor.proposalDeadline(proposalId), deadline);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernorUpgradeable.ProposalState.Pending));
    }

    function testFuzz_CreatesProposalWhenManager(uint256 _proposalThreshold) public virtual {
        _proposalThreshold = bound(_proposalThreshold, 0, type(uint208).max);
        vm.prank(manager);
        governor.setProposalThreshold(_proposalThreshold);
        uint8 _proposalType = 1;
        vm.startPrank(manager);

        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        bytes memory proposalData = _formatProposalData(0);
        uint256 proposalId =
            governor.hashProposalWithModule(address(module), proposalData, keccak256(bytes(description)));

        vm.expectEmit();
        emit ProposalCreated(
            proposalId, manager, address(module), proposalData, snapshot, deadline, description, _proposalType
        );
        if (_proposalType > 0) {
            governor.proposeWithModule(VotingModule(module), proposalData, description, _proposalType);
        } else {
            governor.proposeWithModule(VotingModule(module), proposalData, description, 1);
        }
        vm.stopPrank();

        assertEq(governor.proposals(proposalId).proposalType, _proposalType);
        assertEq(governor.proposalSnapshot(proposalId), snapshot);
        assertEq(governor.proposalDeadline(proposalId), deadline);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernorUpgradeable.ProposalState.Pending));
    }

    function test_RevertIf_InvalidProposalType() public virtual {
        bytes memory proposalData = _formatProposalData(0);
        uint8 invalidPropType = 3;

        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(InvalidProposalType.selector, invalidPropType));
        governor.proposeWithModule(VotingModule(module), proposalData, description, invalidPropType);
    }

    function test_ProposalTypeModuleAddress() public virtual {
        bytes memory proposalData = _formatProposalData(2);

        vm.startPrank(manager);
        vm.expectRevert(abi.encodeWithSelector(InvalidProposalType.selector, 2));
        governor.proposeWithModule(VotingModule(module), proposalData, description, 2);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        vm.expectRevert(abi.encodeWithSelector(InvalidProposalType.selector, 2));
        governor.propose(targets, values, calldatas, "", 2);

        governor.proposeWithModule(VotingModule(optimisticModule), proposalData, description, 2);
        vm.stopPrank();
    }

    function test_RevertIf_ProposalAlreadyCreated() public virtual {
        bytes memory proposalData = _formatProposalData(0);

        vm.startPrank(manager);
        governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.expectRevert(InvalidProposalExists.selector);
        governor.proposeWithModule(VotingModule(module), proposalData, description, 1);
        vm.stopPrank();
    }

    function test_RevertIf_ModuleNotApproved() public virtual {
        bytes memory proposalData = _formatProposalData(0);
        address module_ = makeAddr("module");

        vm.prank(manager);
        vm.expectRevert("Governor: module not approved");
        governor.proposeWithModule(VotingModule(module_), proposalData, description, 0);
    }
}

contract ProposeWithOptimisticModule is OptimismGovernorTest {
    function testFuzz_CreatesAProposalSuccessfully(address _actor) public {
        _actor = manager;
        bytes memory proposalData = abi.encode(OptimisticProposalSettings(1200, false));
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        uint256 proposalId =
            governor.hashProposalWithModule(address(optimisticModule), proposalData, keccak256(bytes(description)));

        vm.expectEmit();
        emit ProposalCreated(
            proposalId, _actor, address(optimisticModule), proposalData, snapshot, deadline, description, 2
        );
        vm.prank(_actor);
        governor.proposeWithModule(optimisticModule, proposalData, description, 2);

        assertEq(governor.proposals(proposalId).proposalType, 2);
        assertEq(governor.proposalSnapshot(proposalId), snapshot);
        assertEq(governor.proposalDeadline(proposalId), deadline);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernorUpgradeable.ProposalState.Pending));
    }

    function testFuzz_ProposalSucceedsWithoutAbsoluteVotes(address _actor, uint256 _elapsedAfterQueuing) public {
        _actor = manager;
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, 1, type(uint16).max);

        bytes memory proposalData = abi.encode(OptimisticProposalSettings(1200, false));
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        uint256 proposalId =
            governor.hashProposalWithModule(address(optimisticModule), proposalData, keccak256(bytes(description)));

        vm.expectEmit();
        emit ProposalCreated(
            proposalId, _actor, address(optimisticModule), proposalData, snapshot, deadline, description, 2
        );
        vm.prank(_actor);
        governor.proposeWithModule(optimisticModule, proposalData, description, 2);

        vm.roll(deadline + _elapsedAfterQueuing);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernorUpgradeable.ProposalState.Succeeded));
    }

    function testFuzz_ProposalSucceedsWithSomeAbsoluteVotes(
        address _actor,
        address _actorFor,
        address _actorAgainst,
        uint256 _elapsedAfterQueuing,
        uint256 _againstThreshold,
        uint256 _forAmount,
        uint256 _againstAmount
    ) public {
        _actor = manager;
        vm.assume(_actorFor != proxyAdmin && _actorAgainst != proxyAdmin);
        vm.assume(_actorFor != address(0) && _actorAgainst != address(0));
        vm.assume(_actorFor != _actorAgainst);
        _againstThreshold = bound(_againstThreshold, 1, type(uint208).max);
        _forAmount = bound(_forAmount, 0, type(uint208).max - _againstThreshold);
        _againstAmount = bound(_againstAmount, 0, _againstThreshold - 1);
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, 1, type(uint16).max);

        vm.startPrank(minter);
        govToken.mint(_actorFor, _forAmount);
        govToken.mint(_actorAgainst, _againstAmount);
        vm.stopPrank();

        vm.prank(_actorFor);
        govToken.delegate(_actorFor);
        vm.prank(_actorAgainst);
        govToken.delegate(_actorAgainst);

        bytes memory proposalData = abi.encode(OptimisticProposalSettings(uint248(_againstThreshold), false));
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        uint256 proposalId =
            governor.hashProposalWithModule(address(optimisticModule), proposalData, keccak256(bytes(description)));

        vm.expectEmit();
        emit ProposalCreated(
            proposalId, _actor, address(optimisticModule), proposalData, snapshot, deadline, description, 2
        );
        vm.prank(_actor);
        governor.proposeWithModule(optimisticModule, proposalData, description, 2);
        vm.roll(block.number + snapshot);

        vm.prank(_actorFor);
        governor.castVote(proposalId, 1);
        vm.prank(_actorAgainst);
        governor.castVote(proposalId, 0);

        vm.roll(deadline + _elapsedAfterQueuing);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernorUpgradeable.ProposalState.Succeeded));
    }

    function testFuzz_ProposalFailsWithSomeAbsoluteVotes(
        address _actor,
        address _actorFor,
        address _actorAgainst,
        uint256 _elapsedAfterQueuing,
        uint256 _againstThreshold,
        uint256 _totalMintAmount,
        uint256 _forAmount,
        uint256 _againstAmount
    ) public {
        _actor = manager;
        vm.assume(_actorFor != proxyAdmin && _actorAgainst != proxyAdmin);
        vm.assume(_actorFor != address(0) && _actorAgainst != address(0));
        vm.assume(_actorFor != _actorAgainst);
        _totalMintAmount = bound(_totalMintAmount, 1, type(uint208).max);
        _againstThreshold = bound(_againstThreshold, 1, _totalMintAmount);
        _againstAmount = bound(_againstAmount, _againstThreshold, _totalMintAmount);
        _forAmount = bound(_forAmount, 0, _totalMintAmount - _againstAmount);
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, 1, type(uint16).max);

        // Mint
        vm.startPrank(minter);
        govToken.mint(_actorFor, _forAmount);
        govToken.mint(_actorAgainst, _againstAmount);
        vm.stopPrank();
        // Delegate
        vm.prank(_actorFor);
        govToken.delegate(_actorFor);
        vm.prank(_actorAgainst);
        govToken.delegate(_actorAgainst);

        bytes memory proposalData = abi.encode(OptimisticProposalSettings(uint248(_againstThreshold), false));
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();

        vm.prank(_actor);
        uint256 proposalId = governor.proposeWithModule(optimisticModule, proposalData, description, 2);
        vm.roll(snapshot + 1);

        // Vote
        vm.prank(_actorFor);
        governor.castVote(proposalId, uint8(VoteType.For));
        vm.prank(_actorAgainst);
        governor.castVote(proposalId, uint8(VoteType.Against));

        vm.roll(deadline + _elapsedAfterQueuing);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernorUpgradeable.ProposalState.Defeated));
    }

    function testFuzz_ProposalSucceedsWithoutRelativeVotes(
        address _actor,
        uint256 _elapsedAfterQueuing,
        uint256 _againstThresholdPercentage
    ) public {
        _actor = manager;
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, 1, type(uint16).max);
        _againstThresholdPercentage = bound(_againstThresholdPercentage, 1, optimisticModule.PERCENT_DIVISOR());
        bytes memory proposalData = abi.encode(OptimisticProposalSettings(uint248(_againstThresholdPercentage), true));
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        uint256 proposalId =
            governor.hashProposalWithModule(address(optimisticModule), proposalData, keccak256(bytes(description)));
        vm.prank(minter);
        // In Optimistic Proposal Settings, if isRelativeToVotableSupply is set to true, the total supply of the token cannot be 0.
        govToken.mint(address(_actor), 1e30);

        vm.expectEmit();
        emit ProposalCreated(
            proposalId, _actor, address(optimisticModule), proposalData, snapshot, deadline, description, 2
        );
        vm.prank(_actor);
        governor.proposeWithModule(optimisticModule, proposalData, description, 2);

        vm.roll(deadline + _elapsedAfterQueuing);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernorUpgradeable.ProposalState.Succeeded));
    }

    function testFuzz_ProposalSucceedsWithSomeRelativeVotes(
        address _actor,
        address _actorFor,
        address _actorAgainst,
        uint256 _againstThresholdPercentage,
        uint256 _totalMintAmount,
        uint256 _forAmount,
        uint256 _againstAmount,
        uint256 _elapsedAfterQueuing
    ) public {
        _actor = manager;
        vm.assume(_actorFor != proxyAdmin && _actorAgainst != proxyAdmin);
        vm.assume(_actor != address(0) && _actorFor != address(0) && _actorAgainst != address(0));
        vm.assume(_actor != _actorFor && _actorFor != _actorAgainst && _actorAgainst != _actor);
        _totalMintAmount = bound(_totalMintAmount, 1e4, type(uint208).max);
        _againstThresholdPercentage = bound(_againstThresholdPercentage, 1, optimisticModule.PERCENT_DIVISOR());
        uint256 _againstThreshold =
            _totalMintAmount * _againstThresholdPercentage / (optimisticModule.PERCENT_DIVISOR());
        _againstAmount = bound(_againstAmount, 0, _againstThreshold - 1);
        _forAmount = bound(_forAmount, 0, _totalMintAmount - _againstAmount);
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, 1, type(uint16).max);

        vm.startPrank(minter);
        govToken.mint(_actorFor, _forAmount);
        govToken.mint(_actorAgainst, _againstAmount);
        govToken.mint(_actor, _totalMintAmount - _forAmount - _againstAmount);
        vm.stopPrank();

        vm.prank(_actorFor);
        govToken.delegate(_actorFor);
        vm.prank(_actorAgainst);
        govToken.delegate(_actorAgainst);

        bytes memory proposalData = abi.encode(OptimisticProposalSettings(uint248(_againstThresholdPercentage), true));
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();

        vm.prank(_actor);
        uint256 proposalId = governor.proposeWithModule(optimisticModule, proposalData, description, 2);
        vm.roll(snapshot + 1);

        vm.prank(_actorFor);
        governor.castVote(proposalId, uint8(VoteType.For));
        vm.prank(_actorAgainst);
        governor.castVote(proposalId, uint8(VoteType.Against));

        vm.roll(deadline + _elapsedAfterQueuing);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernorUpgradeable.ProposalState.Succeeded));
    }

    function testFuzz_ProposalFailsWithSomeRelativeVotes(
        address _actor,
        address _actorFor,
        address _actorAgainst,
        uint256 _againstThresholdPercentage,
        uint256 _totalMintAmount,
        uint256 _forAmount,
        uint256 _againstAmount,
        uint256 _elapsedAfterQueuing
    ) public {
        _actor = manager;
        vm.assume(_actorFor != proxyAdmin && _actorAgainst != proxyAdmin);
        vm.assume(_actor != address(0) && _actorFor != address(0) && _actorAgainst != address(0));
        vm.assume(_actorFor != _actorAgainst);
        _totalMintAmount = bound(_totalMintAmount, 1e4, type(uint208).max);
        _againstThresholdPercentage = bound(_againstThresholdPercentage, 1, optimisticModule.PERCENT_DIVISOR());
        uint256 _againstThreshold =
            _totalMintAmount * _againstThresholdPercentage / (optimisticModule.PERCENT_DIVISOR());
        _againstAmount = bound(_againstAmount, _againstThreshold, _totalMintAmount);
        _forAmount = bound(_forAmount, 0, _totalMintAmount - _againstAmount);
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, 1, type(uint16).max);

        vm.startPrank(minter);
        govToken.mint(_actorFor, _forAmount);
        govToken.mint(_actorAgainst, _againstAmount);
        govToken.mint(_actor, _totalMintAmount - _forAmount - _againstAmount);
        vm.stopPrank();

        vm.prank(_actorFor);
        govToken.delegate(_actorFor);
        vm.prank(_actorAgainst);
        govToken.delegate(_actorAgainst);

        bytes memory proposalData = abi.encode(OptimisticProposalSettings(uint248(_againstThresholdPercentage), true));
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();

        vm.prank(_actor);
        uint256 proposalId = governor.proposeWithModule(optimisticModule, proposalData, description, 2);
        vm.roll(snapshot + 1);

        vm.prank(_actorFor);
        governor.castVote(proposalId, uint8(VoteType.For));
        vm.prank(_actorAgainst);
        governor.castVote(proposalId, uint8(VoteType.Against));

        vm.roll(deadline + _elapsedAfterQueuing);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernorUpgradeable.ProposalState.Defeated));
    }
}

contract Queue is OptimismGovernorTest {
    // TODO: test that non-passing proposals can't be queued (aka voting period over)
    function testFuzz_QueuesASucceedingProposalWhenManager(
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing
    ) public {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(manager);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);
        vm.stopPrank();
        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 14);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Succeeded));
        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));
    }

    function testFuzz_QueuesASucceededProposal(
        address _actor,
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing
    ) public {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.assume(_actor != proxyAdmin);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(manager);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);
        vm.stopPrank();
        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 14);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Succeeded));
        vm.prank(_actor);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));
    }

    function testFuzz_RevertIf_QueuesAProposalBeforeItSucceeds(
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing
    ) public {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(manager);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);
        vm.stopPrank();
        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Pending));
        vm.prank(manager);
        vm.expectRevert("Governor: proposal not successful");
        governor.queue(targets, values, calldatas, keccak256("Test"));
    }

    function testFuzz_RevertIf_ProposalAlreadyQueued(uint256 _proposalTargetCalldata, uint256 _elapsedAfterQueuing)
        public
    {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(manager);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);

        vm.stopPrank();
        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 14);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Succeeded));
        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));

        vm.prank(manager);
        vm.expectRevert("Governor: proposal not successful");
        governor.queue(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));
    }
}

contract QueueWithModule is OptimismGovernorTest {
    function testFuzz_QueuesAProposalWhenItSucceedsByAManager(
        address _voter,
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing
    ) public {
        _mintAndDelegate(_voter, 100e18);
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        bytes memory proposalData = _formatProposalData(_proposalTargetCalldata);
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        string memory reason = "a nice reason";
        vm.deal(address(manager), 100 ether);

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.roll(snapshot + 1);

        // Vote for option 1
        uint256[] memory optionVotes = new uint256[](1);
        optionVotes[0] = 1;
        bytes memory params = abi.encode(optionVotes);

        _mintAndDelegate(_voter, 100e18);
        vm.prank(_voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        vm.roll(deadline + 1);

        vm.prank(manager);
        governor.queueWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        vm.warp(block.timestamp + _elapsedAfterQueuing);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));
    }

    function testFuzz_QueuesASucceededProposal(
        address _actor,
        address _voter,
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing
    ) public {
        vm.assume(_actor != proxyAdmin);
        _mintAndDelegate(_voter, 100e18);
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        bytes memory proposalData = _formatProposalData(_proposalTargetCalldata);
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        string memory reason = "a nice reason";
        vm.deal(address(manager), 100 ether);

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.roll(snapshot + 1);

        // Vote for option 1
        uint256[] memory optionVotes = new uint256[](1);
        optionVotes[0] = 1;
        bytes memory params = abi.encode(optionVotes);

        _mintAndDelegate(_voter, 100e18);
        vm.prank(_voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        vm.roll(deadline + 1);

        vm.prank(_actor);
        governor.queueWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        vm.warp(block.timestamp + _elapsedAfterQueuing);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));
    }

    function testFuzz_RevertIf_QueuesAProposalBeforeItSucceeds(
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing
    ) public {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        bytes memory proposalData = _formatProposalData(_proposalTargetCalldata);
        vm.deal(address(manager), 100 ether);

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Pending));
        vm.prank(manager);
        vm.expectRevert("Governor: proposal not successful");
        governor.queueWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
    }

    function testFuzz_RevertIf_ProposalAlreadyQueued(
        address _voter,
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing
    ) public {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        _mintAndDelegate(_voter, 100e18);
        bytes memory proposalData = _formatProposalData(_proposalTargetCalldata);
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        string memory reason = "a nice reason";
        vm.deal(address(manager), 100 ether);

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.roll(snapshot + 1);

        // Vote for option 1
        uint256[] memory optionVotes = new uint256[](1);
        optionVotes[0] = 1;
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        vm.roll(deadline + 1);

        vm.prank(manager);
        governor.queueWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));

        vm.prank(manager);
        vm.expectRevert("Governor: proposal not successful");
        governor.queueWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
    }
}

contract QueueWithOptimisticModule is OptimismGovernorTest {
    function testFuzz_RevertIf_QueuesAProposalSuccessfully(address _actor) public {
        _actor = manager;
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        bytes memory proposalData = abi.encode(OptimisticProposalSettings(1200, false));

        vm.startPrank(_actor);
        uint256 proposalId = governor.proposeWithModule(optimisticModule, proposalData, description, 2);
        vm.roll(deadline + 1);
        vm.expectRevert(OptimisticModule.OptimisticModuleOnlySignal.selector);
        governor.queueWithModule(optimisticModule, proposalData, keccak256(bytes(description)));
    }
}

contract Execute is OptimismGovernorTest {
    function testFuzz_ExecutesAProposalWhenManager(uint256 _proposalTargetCalldata, uint256 _elapsedAfterQueuing)
        public
        virtual
    {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(manager);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);

        vm.stopPrank();
        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 1);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + 14);

        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        vm.prank(manager);
        governor.execute(targets, values, calldatas, keccak256("Test"));

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Executed));
        assertEq(targetFake.number(), _proposalTargetCalldata);
    }

    function testFuzz_RevertIf_ExecutesAProposalAsAnyUser(
        address _actor,
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing
    ) public virtual {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.assume(_actor != proxyAdmin);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(manager);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);

        vm.stopPrank();
        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 1);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + 14);

        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        vm.expectRevert(NotManagerOrTimelock.selector);
        vm.prank(_actor);
        governor.execute(targets, values, calldatas, keccak256("Test"));

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));
    }

    function testFuzz_RevertIf_ProposalNotQueued(uint256 _proposalTargetCalldata) public {
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(manager);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);

        vm.stopPrank();
        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 1);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + 14);

        vm.expectRevert("Governor: proposal not queued");
        vm.prank(manager);
        governor.execute(targets, values, calldatas, keccak256("Test"));
    }

    function testFuzz_RevertIf_ProposalQueuedButNotReady(uint256 _proposalTargetCalldata, uint256 _elapsedAfterQueuing)
        public
    {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, 0, timelock.getMinDelay() - 1);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(manager);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);

        vm.stopPrank();
        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 1);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + 14);

        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        vm.expectRevert("TimelockController: operation is not ready");
        vm.prank(manager);
        governor.execute(targets, values, calldatas, keccak256("Test"));
    }

    function testFuzz_RevertIf_ProposalNotSuccessful(uint256 _proposalTargetCalldata) public {
        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(manager);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);

        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        vm.roll(block.number + 15);

        assertEq(uint8(governor.state(proposalId)), uint8(ProposalState.Defeated));

        vm.expectRevert("Governor: proposal not queued");
        governor.execute(targets, values, calldatas, keccak256("Test"));
    }

    function testFuzz_RevertIf_ProposalAlreadyExecuted(uint256 _proposalTargetCalldata, uint256 _elapsedAfterQueuing)
        public
    {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(manager);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);

        vm.stopPrank();
        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 1);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + 14);

        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        vm.prank(manager);
        governor.execute(targets, values, calldatas, keccak256("Test"));

        vm.expectRevert("Governor: proposal not queued");
        vm.prank(manager);
        governor.execute(targets, values, calldatas, keccak256("Test"));
    }
}

contract ExecuteWithModule is OptimismGovernorTest {
    function testFuzz_ExecuteSuccessfulProposalAsManager(
        address _voter,
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing
    ) public virtual {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        _mintAndDelegate(_voter, 100e18);
        bytes memory proposalData = _formatProposalData(_proposalTargetCalldata);
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        string memory reason = "a nice reason";
        vm.deal(address(manager), 100 ether);

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.roll(snapshot + 1);

        // Vote for option 1
        uint256[] memory optionVotes = new uint256[](1);
        optionVotes[0] = 1;
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        vm.roll(deadline + 1);

        vm.prank(manager);
        governor.queueWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        vm.prank(manager);
        vm.expectEmit();
        emit ProposalExecuted(proposalId);
        governor.executeWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        assertEq(uint8(governor.state(proposalId)), uint8(ProposalState.Executed));
        assertEq(targetFake.number(), _proposalTargetCalldata);
    }

    function testFuzz_ExecuteSuccessfulProposalAsAnyActor(
        address _actor,
        address _voter,
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing
    ) public virtual {
        vm.assume(_actor != proxyAdmin);
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        _mintAndDelegate(_voter, 100e18);
        bytes memory proposalData = _formatProposalData(_proposalTargetCalldata);
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        string memory reason = "a nice reason";
        vm.deal(address(manager), 100 ether);

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.roll(snapshot + 1);

        // Vote for option 1
        uint256[] memory optionVotes = new uint256[](1);
        optionVotes[0] = 1;
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        vm.roll(deadline + 1);

        vm.prank(manager);
        governor.queueWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        vm.prank(manager);
        vm.expectEmit();
        emit ProposalExecuted(proposalId);
        governor.executeWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        assertEq(uint8(governor.state(proposalId)), uint8(ProposalState.Executed));
        assertEq(targetFake.number(), _proposalTargetCalldata);
    }

    function testFuzz_RevertIf_ProposalNotQueued(address _voter, uint256 _proposalTargetCalldata) public {
        _mintAndDelegate(_voter, 100e18);
        bytes memory proposalData = _formatProposalData(_proposalTargetCalldata);
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        string memory reason = "a nice reason";
        vm.deal(address(manager), 100 ether);

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.roll(snapshot + 1);

        // Vote for option 1
        uint256[] memory optionVotes = new uint256[](1);
        optionVotes[0] = 1;
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        vm.roll(deadline + 1);

        vm.expectRevert("Governor: proposal not queued");
        vm.prank(manager);
        governor.executeWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
    }

    function testFuzz_RevertIf_ProposalQueuedButNotReady(
        address _voter,
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing
    ) public {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, 0, timelock.getMinDelay() - 1);
        _mintAndDelegate(_voter, 100e18);
        bytes memory proposalData = _formatProposalData(_proposalTargetCalldata);
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        string memory reason = "a nice reason";
        vm.deal(address(manager), 100 ether);

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.roll(snapshot + 1);

        // Vote for option 1
        uint256[] memory optionVotes = new uint256[](1);
        optionVotes[0] = 1;
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        vm.roll(deadline + 1);

        vm.prank(manager);
        governor.queueWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        vm.expectRevert("TimelockController: operation is not ready");
        vm.prank(manager);
        governor.executeWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
    }

    function test_RevertIf_ProposalNotSuccessful() public virtual {
        bytes memory proposalData = _formatProposalData(0);
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.roll(deadline + 1);

        assertEq(uint8(governor.state(proposalId)), uint8(ProposalState.Defeated));

        vm.prank(manager);
        vm.expectRevert("Governor: proposal not queued");
        governor.executeWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
    }

    function testFuzz_RevertIf_ProposalAlreadyExecuted(
        address _voter,
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing
    ) public {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        _mintAndDelegate(_voter, 100e18);
        bytes memory proposalData = _formatProposalData(_proposalTargetCalldata);
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        string memory reason = "a nice reason";
        vm.deal(address(manager), 100 ether);

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.roll(snapshot + 1);

        // Vote for option 1
        uint256[] memory optionVotes = new uint256[](1);
        optionVotes[0] = 1;
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        vm.roll(deadline + 1);

        vm.prank(manager);
        governor.queueWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        vm.prank(manager);
        governor.executeWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));

        vm.expectRevert("Governor: proposal not queued");
        vm.prank(manager);
        governor.executeWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
    }
}

contract ExecuteWithOptimisticModule is OptimismGovernorTest {
    function testFuzz_RevertIf_ExecutesAProposalSuccessfully(uint256 _elapsedAfterQueuing) public {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        bytes memory proposalData = abi.encode(OptimisticProposalSettings(1200, false));

        vm.startPrank(manager);
        uint256 proposalId = governor.proposeWithModule(optimisticModule, proposalData, description, 2);
        vm.roll(deadline + 1);
        vm.expectRevert();
        governor.executeWithModule(optimisticModule, proposalData, keccak256(bytes(description)));
    }
}

contract Cancel is OptimismGovernorTest {
    function testFuzz_CancelProposalAfterSucceedingButBeforeQueuing(
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing,
        uint256 _actorSeed
    ) public virtual {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(manager);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);

        vm.stopPrank();
        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 14);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Succeeded));

        vm.expectEmit();
        emit ProposalCanceled(proposalId);
        vm.prank(_managerOrTimelock(_actorSeed));
        governor.cancel(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
    }

    function testFuzz_CancelProposalAfterQueuing(
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing,
        uint256 _actorSeed
    ) public virtual {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(manager);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);

        vm.stopPrank();
        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 14);

        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));
        vm.expectEmit();
        emit ProposalCanceled(proposalId);
        vm.prank(_managerOrTimelock(_actorSeed));
        governor.cancel(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
    }

    function test_CancelsProposalBeforeVoteEnd(uint256 _actorSeed) public virtual {
        vm.prank(minter);
        govToken.mint(address(this), 1000);
        govToken.delegate(address(this));

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.startPrank(manager);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);

        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        vm.stopPrank();

        vm.expectEmit();
        emit ProposalCanceled(proposalId);
        vm.prank(_managerOrTimelock(_actorSeed));
        governor.cancel(targets, values, calldatas, keccak256("Test"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
    }

    function testFuzz_RevertIf_CancelProposalAfterExecution(
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing,
        uint256 _actorSeed
    ) public virtual {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(targetFake);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ExecutionTargetFake.setNumber.selector, _proposalTargetCalldata);

        vm.startPrank(manager);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);

        vm.stopPrank();
        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 14);

        vm.startPrank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);
        governor.execute(targets, values, calldatas, keccak256("Test"));
        vm.stopPrank();

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Executed));
        vm.prank(_managerOrTimelock(_actorSeed));
        vm.expectRevert("Governor: proposal not active");
        governor.cancel(targets, values, calldatas, keccak256("Test"));
    }

    function test_RevertIf_ProposalDoesntExist(uint256 _actorSeed) public virtual {
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(_managerOrTimelock(_actorSeed));
        vm.expectRevert("Governor: unknown proposal id");
        governor.cancel(targets, values, calldatas, keccak256("Test"));
    }
}

contract CancelWithModule is OptimismGovernorTest {
    function testFuzz_CancelProposalAfterSucceedingButBeforeQueuing(
        address _voter,
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing,
        uint256 _actorSeed
    ) public virtual {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        _mintAndDelegate(_voter, 100e18);
        bytes memory proposalData = _formatProposalData(_proposalTargetCalldata);
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        string memory reason = "a nice reason";
        vm.deal(address(manager), 100 ether);

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.roll(snapshot + 1);

        // Vote for option 1
        uint256[] memory optionVotes = new uint256[](1);
        optionVotes[0] = 1;
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        vm.roll(deadline + 1);

        vm.expectEmit();
        emit ProposalCanceled(proposalId);
        vm.prank(_managerOrTimelock(_actorSeed));
        governor.cancelWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
    }

    function testFuzz_CancelProposalAfterQueuing(
        address _voter,
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing,
        uint256 _actorSeed
    ) public virtual {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        _mintAndDelegate(_voter, 100e18);
        bytes memory proposalData = _formatProposalData(_proposalTargetCalldata);
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        string memory reason = "a nice reason";
        vm.deal(address(manager), 100 ether);

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.roll(snapshot + 1);

        // Vote for option 1
        uint256[] memory optionVotes = new uint256[](1);
        optionVotes[0] = 1;
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        vm.roll(deadline + 1);

        vm.prank(manager);
        governor.queueWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Queued));
        vm.expectEmit();
        emit ProposalCanceled(proposalId);
        vm.prank(_managerOrTimelock(_actorSeed));
        governor.cancelWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
    }

    function test_CancelsProposalBeforeVoteEnd(uint256 _actorSeed) public virtual {
        bytes memory proposalData = _formatProposalData(0);

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.expectEmit();
        emit ProposalCanceled(proposalId);
        vm.prank(_managerOrTimelock(_actorSeed));
        governor.cancelWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));

        assertEq(uint8(governor.state(proposalId)), uint8(ProposalState.Canceled));
    }

    function testFuzz_RevertIf_CancelProposalAfterExecution(
        address _voter,
        uint256 _proposalTargetCalldata,
        uint256 _elapsedAfterQueuing,
        uint256 _actorSeed
    ) public virtual {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        _mintAndDelegate(_voter, 100e18);
        bytes memory proposalData = _formatProposalData(_proposalTargetCalldata);
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        string memory reason = "a nice reason";
        vm.deal(address(manager), 100 ether);

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.roll(snapshot + 1);

        // Vote for option 1
        uint256[] memory optionVotes = new uint256[](1);
        optionVotes[0] = 1;
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        vm.roll(deadline + 1);

        vm.prank(manager);
        governor.queueWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        vm.prank(manager);
        vm.expectEmit();
        emit ProposalExecuted(proposalId);
        governor.executeWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        assertEq(uint8(governor.state(proposalId)), uint8(ProposalState.Executed));
        assertEq(targetFake.number(), _proposalTargetCalldata);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Executed));

        vm.prank(_managerOrTimelock(_actorSeed));
        vm.expectRevert("Governor: proposal not active");
        governor.cancelWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
    }

    function testFuzz_RevertIf_ProposalDoesntExist(bytes memory proposalData, uint256 _actorSeed) public virtual {
        vm.prank(_managerOrTimelock(_actorSeed));
        vm.expectRevert("Governor: unknown proposal id");
        governor.cancelWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
    }

    function test_RevertIf_proposalNotActive() public virtual {
        bytes memory proposalData = _formatProposalData(0);

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);
        vm.startPrank(manager);
        governor.cancelWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));

        vm.expectRevert("Governor: proposal not active");
        governor.cancelWithModule(VotingModule(module), proposalData, keccak256(bytes(description)));
        vm.stopPrank();
        assertEq(uint8(governor.state(proposalId)), uint8(ProposalState.Canceled));
    }
}

contract CancelWithOptimisticModule is OptimismGovernorTest {
    function testFuzz_CancelsAProposalSuccessfully(uint256 _elapsedAfterQueuing, uint256 _actorSeed) public {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 deadline = snapshot + governor.votingPeriod();
        bytes memory proposalData = abi.encode(OptimisticProposalSettings(1200, false));
        vm.prank(_managerOrTimelock(_actorSeed));
        uint256 proposalId = governor.proposeWithModule(optimisticModule, proposalData, description, 2);
        vm.roll(deadline + 1);

        vm.expectEmit();
        emit ProposalCanceled(proposalId);
        vm.prank(_managerOrTimelock(_actorSeed));
        governor.cancelWithModule(optimisticModule, proposalData, keccak256(bytes(description)));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Canceled));
    }
}

contract UpdateTimelock is OptimismGovernorTest {
    function testFuzz_UpdateTimelock(uint256 _elapsedAfterQueuing, address _newTimelock) public {
        _elapsedAfterQueuing = bound(_elapsedAfterQueuing, timelockDelay, type(uint208).max);
        vm.prank(minter);
        govToken.mint(address(this), 1e30);
        govToken.delegate(address(this));
        vm.deal(address(manager), 100 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(governor);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(governor.updateTimelock.selector, address(_newTimelock));

        vm.startPrank(manager);
        governor.setVotingDelay(0);
        governor.setVotingPeriod(14);

        vm.stopPrank();
        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + 1);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + 14);

        vm.prank(manager);
        governor.queue(targets, values, calldatas, keccak256("Test"));
        vm.warp(block.timestamp + _elapsedAfterQueuing);

        vm.prank(manager);
        governor.execute(targets, values, calldatas, keccak256("Test"));
        assertEq(governor.timelock(), address(_newTimelock));
    }

    function testFuzz_RevertIf_NotTimelock(address _actor, address _newTimelock) public {
        vm.assume(_actor != governor.timelock() && _actor != proxyAdmin);
        vm.prank(_actor);
        vm.expectRevert("Governor: onlyGovernance");
        governor.updateTimelock(TimelockControllerUpgradeable(payable(_newTimelock)));
    }
}

contract Quorum is OptimismGovernorTest {
    function test_CorrectlyCalculatesQuorum(address _voter, uint208 _amount) public virtual {
        _mintAndDelegate(_voter, _amount);
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.roll(block.number + governor.votingDelay() + 1);

        uint256 supply = govToken.totalSupply();
        uint256 quorum = governor.quorum(proposalId);
        assertEq(quorum, (supply * 3) / 10);
    }
}

contract QuorumReached is OptimismGovernorTest {
    function test_CorrectlyReturnsQuorumStatus(address _voter, address _voter2) public virtual {
        vm.assume(_voter != _voter2);
        _mintAndDelegate(_voter, 30e18);
        _mintAndDelegate(_voter2, 100e18);
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        uint256 snapshot = block.number + governor.votingDelay();
        vm.roll(snapshot + 1);

        assertFalse(governor.quorumReached(proposalId));

        vm.prank(_voter);
        governor.castVote(proposalId, 1);

        assertFalse(governor.quorumReached(proposalId));

        vm.prank(_voter2);
        governor.castVote(proposalId, 1);

        assertTrue(governor.quorumReached(proposalId));
    }
}

contract CastVote is OptimismGovernorTest {
    function testFuzz_VoteSucceeded(address _voter, address _voter2) public virtual {
        vm.assume(_voter != _voter2);
        _mintAndDelegate(_voter, 100e18);
        _mintAndDelegate(_voter2, 100e18);
        vm.prank(manager);
        proposalTypesConfigurator.setProposalType(0, 3_000, 9_910, "Default", "Lorem Ipsum", address(0));
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        uint256 snapshot = block.number + governor.votingDelay();
        vm.roll(snapshot + 1);

        vm.prank(_voter);
        governor.castVote(proposalId, 1);
        vm.prank(_voter2);
        governor.castVote(proposalId, 0);

        assertFalse(governor.voteSucceeded(proposalId));

        vm.prank(manager);
        proposalId = governor.propose(targets, values, calldatas, "Test2");

        snapshot = block.number + governor.votingDelay();
        vm.roll(snapshot + 1);

        vm.prank(_voter);
        governor.castVote(proposalId, 1);

        assertTrue(governor.voteSucceeded(proposalId));
    }
}

contract CastVoteWithReasonAndParams is OptimismGovernorTest {
    function test_CastVoteWithModule(address _voter, address _voter2) public virtual {
        vm.assume(_voter != _voter2);
        _mintAndDelegate(_voter, 1e18);
        _mintAndDelegate(_voter2, 1e20);
        bytes memory proposalData = _formatProposalData(0);
        uint256 snapshot = block.number + governor.votingDelay();
        uint256 weight = govToken.getVotes(_voter);
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.roll(snapshot + 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        vm.expectEmit(true, false, false, true);
        emit VoteCastWithParams(_voter, proposalId, uint8(VoteType.For), weight, reason, params);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        weight = govToken.getVotes(_voter2);
        vm.prank(_voter2);
        vm.expectEmit(true, false, false, true);
        emit VoteCastWithParams(_voter2, proposalId, uint8(VoteType.Against), weight, reason, params);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.Against), reason, params);

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);

        assertEq(againstVotes, 1e20);
        assertEq(forVotes, 1e18);
        assertEq(abstainVotes, 0);
        assertFalse(governor.voteSucceeded(proposalId));
        assertEq(module._proposals(proposalId).optionVotes[0], 1e18);
        assertEq(module._proposals(proposalId).optionVotes[1], 0);
        assertTrue(governor.hasVoted(proposalId, _voter));
        assertEq(module.getAccountTotalVotes(proposalId, _voter), optionVotes.length);
        assertTrue(governor.hasVoted(proposalId, _voter2));
        assertEq(module.getAccountTotalVotes(proposalId, _voter2), 0);
    }

    function test_RevertIf_voteNotActive(address _voter) public virtual {
        _mintAndDelegate(_voter, 100e18);
        bytes memory proposalData = _formatProposalData(0);
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        vm.expectRevert("Governor: vote not currently active");
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);
    }

    function test_HasVoted(address _voter) public virtual {
        _mintAndDelegate(_voter, 100e18);
        bytes memory proposalData = _formatProposalData(0);
        uint256 snapshot = block.number + governor.votingDelay();
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.roll(snapshot + 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        assertTrue(governor.hasVoted(proposalId, _voter));
    }
}

contract EditProposalType is OptimismGovernorTest {
    function testFuzz_EditProposalTypeByManagerOrTimelock(uint256 _actorSeed) public virtual {
        vm.startPrank(_managerOrTimelock(_actorSeed));
        proposalTypesConfigurator.setProposalType(0, 3_000, 9_910, "Default", "Lorem Ipsum", address(0));
        proposalTypesConfigurator.setProposalType(1, 3_000, 9_910, "Default 2", "Lorem Ipsum 2", address(0));

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        assertEq(governor.proposals(proposalId).proposalType, 0);

        vm.expectEmit();
        emit ProposalTypeUpdated(proposalId, 1);
        governor.editProposalType(proposalId, 1);

        assertEq(governor.proposals(proposalId).proposalType, 1);

        vm.stopPrank();
    }

    function test_RevertIf_NotManagerOrTimelock(address _actor) public virtual {
        vm.assume(_actor != manager && _actor != governor.timelock() && _actor != proxyAdmin);
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        vm.prank(manager);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        vm.expectRevert(NotManagerOrTimelock.selector);
        vm.prank(_actor);
        governor.editProposalType(proposalId, 1);
    }

    function testFuzz_RevertIf_InvalidProposalId(uint256 _actorSeed) public virtual {
        bytes memory proposalData = _formatProposalData(0);
        uint256 proposalId =
            governor.hashProposalWithModule(address(module), proposalData, keccak256(bytes(description)));

        vm.prank(_managerOrTimelock(_actorSeed));
        vm.expectRevert(InvalidProposalId.selector);
        governor.editProposalType(proposalId, 1);
    }

    function testFuzz_RevertIf_InvalidProposalType(uint256 _actorSeed) public virtual {
        vm.startPrank(manager);

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(this.executeCallback.selector);

        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        assertEq(governor.proposals(proposalId).proposalType, 0);
        vm.stopPrank();
        vm.prank(_managerOrTimelock(_actorSeed));
        vm.expectRevert(abi.encodeWithSelector(InvalidProposalType.selector, 3));
        governor.editProposalType(proposalId, 3);
    }
}

contract VoteSucceeded is OptimismGovernorTest {
    function test_QuorumReachedAndVoteSucceeded(address _voter) public virtual {
        _mintAndDelegate(_voter, 100e18);
        bytes memory proposalData = _formatProposalData(0);
        uint256 snapshot = block.number + governor.votingDelay();
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.roll(snapshot + 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        assertTrue(governor.quorum(proposalId) != 0);
        assertTrue(governor.quorumReached(proposalId));
        assertTrue(governor.voteSucceeded(proposalId));
    }

    function test_VoteNotSucceeded(address _voter, address _voter2) public virtual {
        vm.assume(_voter != _voter2);
        _mintAndDelegate(_voter, 100e18);
        _mintAndDelegate(_voter2, 200e18);
        bytes memory proposalData = _formatProposalData(0);
        uint256 snapshot = block.number + governor.votingDelay();
        string memory reason = "a nice reason";

        vm.prank(manager);
        uint256 proposalId = governor.proposeWithModule(VotingModule(module), proposalData, description, 1);

        vm.roll(snapshot + 1);

        // Vote for option 0
        uint256[] memory optionVotes = new uint256[](1);
        bytes memory params = abi.encode(optionVotes);

        vm.prank(_voter);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.For), reason, params);

        vm.prank(_voter2);
        governor.castVoteWithReasonAndParams(proposalId, uint8(VoteType.Against), reason, "");

        assertTrue(governor.quorum(proposalId) != 0);
        assertFalse(governor.voteSucceeded(proposalId));
    }
}

contract SetModuleApproval is OptimismGovernorTest {
    function testFuzz_TogglesModuleApproval(address _module, uint256 _actorSeed) public {
        vm.assume(_module != address(module) && _module != address(optimisticModule));
        assertEq(governor.approvedModules(address(_module)), false);

        vm.startPrank(_managerOrTimelock(_actorSeed));
        governor.setModuleApproval(address(_module), true);
        assertEq(governor.approvedModules(address(_module)), true);

        governor.setModuleApproval(address(_module), false);
        assertEq(governor.approvedModules(address(_module)), false);
        vm.stopPrank();
    }

    function test_RevertIf_NotManagerOrTimelock(address _actor, address _module) public {
        vm.assume(_actor != manager && _actor != governor.timelock() && _actor != proxyAdmin);
        vm.prank(_actor);
        vm.expectRevert(NotManagerOrTimelock.selector);
        governor.setModuleApproval(_module, true);
    }
}

contract SetProposalDeadline is OptimismGovernorTest {
    function testFuzz_SetsProposalDeadlineAsManagerOrTimelock(uint64 _proposalDeadline, uint256 _actorSeed) public {
        uint256 proposalId = _createValidProposal();
        vm.prank(_managerOrTimelock(_actorSeed));
        governor.setProposalDeadline(proposalId, _proposalDeadline);
        assertEq(governor.proposalDeadline(proposalId), _proposalDeadline);
    }

    function testFuzz_RevertIf_NotManagerOrTimelock(address _actor, uint64 _proposalDeadline) public {
        vm.assume(_actor != manager && _actor != governor.timelock() && _actor != proxyAdmin);
        uint256 proposalId = _createValidProposal();
        vm.prank(_actor);
        vm.expectRevert(NotManagerOrTimelock.selector);
        governor.setProposalDeadline(proposalId, _proposalDeadline);
    }
}

contract SetVotingDelay is OptimismGovernorTest {
    function testFuzz_SetsVotingDelayWhenManagerOrTimelock(uint256 _votingDelay, uint256 _actorSeed) public {
        vm.prank(_managerOrTimelock(_actorSeed));
        governor.setVotingDelay(_votingDelay);
        assertEq(governor.votingDelay(), _votingDelay);
    }

    function testFuzz_RevertIf_NotManagerOrTimelock(address _actor, uint256 _votingDelay) public {
        vm.assume(_actor != manager && _actor != governor.timelock() && _actor != proxyAdmin);
        vm.expectRevert(NotManagerOrTimelock.selector);
        vm.prank(_actor);
        governor.setVotingDelay(_votingDelay);
    }
}

contract SetVotingPeriod is OptimismGovernorTest {
    function testFuzz_SetsVotingPeriodAsManagerOrTimelock(uint256 _votingPeriod, uint256 _actorSeed) public {
        _votingPeriod = bound(_votingPeriod, 1, type(uint256).max);
        vm.prank(_managerOrTimelock(_actorSeed));
        governor.setVotingPeriod(_votingPeriod);
        assertEq(governor.votingPeriod(), _votingPeriod);
    }

    function testFuzz_RevertIf_NotManagerOrTimelock(address _actor, uint256 _votingPeriod) public {
        vm.assume(_actor != manager && _actor != governor.timelock() && _actor != proxyAdmin);
        vm.expectRevert(NotManagerOrTimelock.selector);
        vm.prank(_actor);
        governor.setVotingPeriod(_votingPeriod);
    }
}

contract SetProposalThreshold is OptimismGovernorTest {
    function testFuzz_SetsProposalThresholdAsManagerOrTimelock(uint256 _proposalThreshold, uint256 _actorSeed) public {
        vm.prank(_managerOrTimelock(_actorSeed));
        governor.setProposalThreshold(_proposalThreshold);
        assertEq(governor.proposalThreshold(), _proposalThreshold);
    }

    function testFuzz_RevertIf_NotManagerOrTimelock(address _actor, uint256 _proposalThreshold) public {
        vm.assume(_actor != manager && _actor != governor.timelock() && _actor != proxyAdmin);
        vm.expectRevert(NotManagerOrTimelock.selector);
        vm.prank(_actor);
        governor.setProposalThreshold(_proposalThreshold);
    }
}

contract SetManager is OptimismGovernorTest {
    function testFuzz_SetsNewManager(address _newManager, uint256 _actorSeed) public {
        vm.prank(_managerOrTimelock(_actorSeed));
        vm.expectEmit();
        emit ManagerSet(manager, _newManager);
        governor.setManager(_newManager);
        assertEq(governor.manager(), _newManager);
    }

    function testFuzz_RevertIf_NotManager(address _actor, address _newManager) public {
        vm.assume(_actor != manager && _actor != governor.timelock() && _actor != proxyAdmin);
        vm.prank(_actor);
        vm.expectRevert(NotManagerOrTimelock.selector);
        governor.setManager(_newManager);
    }
}

contract UpgradeTo is OptimismGovernorTest {
    function test_UpgradesToNewImplementationAddress() public {
        address _newImplementation = address(new OptimismGovernor());
        vm.startPrank(proxyAdmin);
        TransparentUpgradeableProxy(payable(governorProxy)).upgradeTo(_newImplementation);
        assertEq(TransparentUpgradeableProxy(payable(governorProxy)).implementation(), _newImplementation);
        vm.stopPrank();
    }

    function testFuzz_RevertIf_NotProxyAdmin(address _actor) public {
        vm.assume(_actor != proxyAdmin);
        address _newImplementation = address(new OptimismGovernor());
        vm.prank(_actor);
        vm.expectRevert(bytes(""));
        TransparentUpgradeableProxy(payable(governorProxy)).upgradeTo(_newImplementation);
    }
}

contract UpgradeToLive is OptimismGovernorTest {
    OptimismGovernor governorProxyOP = OptimismGovernor(payable(0xcDF27F107725988f2261Ce2256bDfCdE8B382B10));
    address proxyAdminOP = 0x2501c477D0A35545a387Aa4A3EEe4292A9a8B3F0;

    function setUp() public override {
        vm.createSelectFork(vm.rpcUrl("https://mainnet.optimism.io"));
    }

    function test_UpgradesToNewImplementationAddress() public {
        // https://vote.optimism.io/proposals/61005589785236655268631485340221675868668620091725777228538771284249388228706
        assertEq(
            uint8(governorProxyOP.state(61005589785236655268631485340221675868668620091725777228538771284249388228706)),
            uint8(ProposalState.Succeeded)
        );

        IProposalTypesConfigurator.ProposalType[] memory proposalTypes =
            new IProposalTypesConfigurator.ProposalType[](1);
        proposalTypes[0] = IProposalTypesConfigurator.ProposalType({
            quorum: 3000,
            approvalThreshold: 5100,
            name: "Default",
            description: "Default",
            module: address(0)
        });

        address _newImplementation = address(new OptimismGovernor());
        ProposalTypesConfigurator _newProposalTypesConfigurator = new ProposalTypesConfigurator();
        _newProposalTypesConfigurator.initialize(address(governorProxyOP), proposalTypes);

        vm.startPrank(proxyAdminOP);
        TransparentUpgradeableProxy(payable(address(governorProxyOP))).upgradeToAndCall(
            _newImplementation,
            abi.encodeWithSelector(
                OptimismGovernor.reinitialize.selector,
                0x7f08F3095530B67CdF8466B7a923607944136Df0,
                0x1b7CA7437748375302bAA8954A2447fC3FBE44CC,
                _newProposalTypesConfigurator
            )
        );
        assertEq(TransparentUpgradeableProxy(payable(address(governorProxyOP))).implementation(), _newImplementation);
        vm.stopPrank();
        assertEq(governorProxyOP.VERSION(), 4);
        assertEq(address(governorProxyOP.alligator()), 0x7f08F3095530B67CdF8466B7a923607944136Df0);
        assertEq(address(governorProxyOP.VOTABLE_SUPPLY_ORACLE()), 0x1b7CA7437748375302bAA8954A2447fC3FBE44CC);
        assertEq(address(governorProxyOP.PROPOSAL_TYPES_CONFIGURATOR()), address(_newProposalTypesConfigurator));
        assertEq(address(governorProxyOP.token()), 0x4200000000000000000000000000000000000042);

        // https://vote.optimism.io/proposals/61005589785236655268631485340221675868668620091725777228538771284249388228706
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) =
            governorProxyOP.proposalVotes(61005589785236655268631485340221675868668620091725777228538771284249388228706);
        assertEq(againstVotes, 0);
        assertEq(forVotes, 35737530126676264762561269);
        assertEq(abstainVotes, 5861007290433212512380436);

        assertEq(
            uint8(governorProxyOP.state(61005589785236655268631485340221675868668620091725777228538771284249388228706)),
            uint8(ProposalState.Executed)
        );

        // https://vote.optimism.io/proposals/105090569675606228680479820654354019470447822380910214626164858605991232311940
        (againstVotes, forVotes, abstainVotes) = governorProxyOP.proposalVotes(
            105090569675606228680479820654354019470447822380910214626164858605991232311940
        );
        assertEq(againstVotes, 29821545007390871389189952);
        assertEq(forVotes, 17007275354046121960170029);
        assertEq(abstainVotes, 3487066530234316527174422);

        assertEq(
            uint8(governorProxyOP.state(105090569675606228680479820654354019470447822380910214626164858605991232311940)),
            uint8(ProposalState.Defeated)
        );
    }

    function testFuzz_RevertIf_NotProxyAdmin(address _actor) public {
        vm.assume(_actor != proxyAdminOP);
        address _newImplementation = address(new OptimismGovernor());
        vm.prank(_actor);
        vm.expectRevert(bytes(""));
        TransparentUpgradeableProxy(payable(address(governorProxyOP))).upgradeTo(_newImplementation);
    }
}
