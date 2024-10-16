// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {GovernorUpgradeableV2} from "./lib/openzeppelin/v2/GovernorUpgradeableV2.sol";
import {GovernorCountingSimpleUpgradeableV2} from "./lib/openzeppelin/v2/GovernorCountingSimpleUpgradeableV2.sol";
import {GovernorVotesQuorumFractionUpgradeableV2} from
    "./lib/openzeppelin/v2/GovernorVotesQuorumFractionUpgradeableV2.sol";
import {GovernorVotesUpgradeableV2} from "./lib/openzeppelin/v2/GovernorVotesUpgradeableV2.sol";
import {GovernorSettingsUpgradeableV2} from "./lib/openzeppelin/v2/GovernorSettingsUpgradeableV2.sol";
import {GovernorTimelockControlUpgradeableV2} from "./lib/openzeppelin/v2/GovernorTimelockControlUpgradeableV2.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {IGovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";
import {TimersUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/TimersUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {VotingModule} from "./modules/VotingModule.sol";
import {IVotableSupplyOracle} from "./interfaces/IVotableSupplyOracle.sol";
import {IProposalTypesConfigurator} from "./interfaces/IProposalTypesConfigurator.sol";
import {IVotingToken} from "./interfaces/IVotingToken.sol";
import {TimelockControllerUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {IGovernorTimelockUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/extensions/IGovernorTimelockUpgradeable.sol";

contract OptimismGovernor is
    Initializable,
    GovernorUpgradeableV2,
    GovernorCountingSimpleUpgradeableV2,
    GovernorVotesUpgradeableV2,
    GovernorVotesQuorumFractionUpgradeableV2,
    GovernorSettingsUpgradeableV2
{
    /*//////////////////////////////////////////////////////////////
                               LIBRARIES
    //////////////////////////////////////////////////////////////*/

    using SafeCastUpgradeable for uint256;
    using TimersUpgradeable for TimersUpgradeable.BlockNumber;

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
    event ProposalTypeUpdated(uint256 indexed proposalId, uint8 proposalType);
    event ManagerSet(address indexed oldManager, address indexed newManager);
    event ProposalDeadlineUpdated(uint256 proposalId, uint64 deadline);
    event TimelockChange(address oldTimelock, address newTimelock);
    event ProposalQueued(uint256 proposalId, uint256 eta);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidProposalType(uint8 proposalType);
    error InvalidProposalId();
    error InvalidRelayTarget(address target);
    error InvalidProposalLength();
    error InvalidEmptyProposal();
    error InvalidVotesBelowThreshold();
    error InvalidProposalExists();
    error InvalidVoteType();
    error NotManagerOrTimelock();
    error NotAlligator();

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Max value of `quorum` and `approvalThreshold` in `ProposalType`
    uint16 public constant PERCENT_DIVISOR = 10_000;

    /// @notice Manager address
    address public manager;

    /// @notice Approved modules
    mapping(address module => bool approved) public approvedModules;

    /// @notice Total number of `votes` that `account` has cast for `proposalId`.
    /// @dev Replaces non-quantitative `_proposalVotes.hasVoted` to add support for partial voting.
    mapping(uint256 proposalId => mapping(address account => uint256 votes)) public weightCast;

    /// @notice Alligator address
    address public alligator;

    /// @notice Votable supply oracle
    IVotableSupplyOracle public VOTABLE_SUPPLY_ORACLE;

    /// @notice Proposal types configurator
    IProposalTypesConfigurator public PROPOSAL_TYPES_CONFIGURATOR;

    /// @notice Timelock controller
    TimelockControllerUpgradeable internal _timelock;

    /// @notice Timelock ids
    mapping(uint256 => bytes32) internal _timelockIds;

    /// @notice Block number to check if proposal is previous or after upgrade
    uint256 internal _upgradeBlock;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyManagerOrTimelock() {
        address sender = _msgSender();
        if (sender != manager && sender != timelock()) revert NotManagerOrTimelock();
        _;
    }

    modifier onlyAlligator() {
        if (_msgSender() != alligator) revert NotAlligator();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the governor with the given parameters.
     * @param _votingToken The governance token used for voting.
     * @param _votableSupplyOracle The votable supply oracle.
     * @param _manager The manager address.
     * @param _alligator The alligator contract.
     * @param _timelockAddress The governance timelock.
     * @param _proposalTypesConfigurator Proposal types configurator contract.
     * @param _proposalTypes Initial proposal types to set.
     */
    function initialize(
        IVotingToken _votingToken,
        IVotableSupplyOracle _votableSupplyOracle,
        address _manager,
        address _alligator,
        TimelockControllerUpgradeable _timelockAddress,
        IProposalTypesConfigurator _proposalTypesConfigurator,
        IProposalTypesConfigurator.ProposalType[] calldata _proposalTypes
    ) public initializer {
        __Governor_init("Optimism");
        __GovernorCountingSimple_init();
        __GovernorVotes_init(_votingToken);
        __GovernorSettings_init({initialVotingDelay: 6575, initialVotingPeriod: 46027, initialProposalThreshold: 0});

        PROPOSAL_TYPES_CONFIGURATOR = _proposalTypesConfigurator;
        VOTABLE_SUPPLY_ORACLE = _votableSupplyOracle;
        manager = _manager;
        alligator = _alligator;
        _timelock = _timelockAddress;

        PROPOSAL_TYPES_CONFIGURATOR.initialize(address(this), _proposalTypes);
    }

    /**
     * @notice Reinitializes the contract with updated parameters.
     * @param _alligator The new address of the alligator contract.
     * @param _votableSupplyOracle The new address of the votable supply oracle.
     * @param _proposalTypesConfigurator The new address of the proposal types configurator.
     */
    function reinitialize(address _alligator, address _votableSupplyOracle, address _proposalTypesConfigurator)
        public
        reinitializer(uint8(VERSION()))
    {
        alligator = _alligator;
        VOTABLE_SUPPLY_ORACLE = IVotableSupplyOracle(_votableSupplyOracle);
        PROPOSAL_TYPES_CONFIGURATOR = IProposalTypesConfigurator(_proposalTypesConfigurator);
        _upgradeBlock = block.number;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Count `votes` for `account` on `proposalId` and update `weightCast`.
     * Reverts if `votes` exceeds the remaining weight of `account` on `proposalId`.
     *
     * @param proposalId The id of the proposal to vote on
     * @param account The address for which to count votes for, the proxy
     * @param votes The number of votes to count
     * @param accountVotes The total number of votes delegated to `account`
     */
    function increaseWeightCast(uint256 proposalId, address account, uint256 votes, uint256 accountVotes)
        external
        onlyAlligator
    {
        require((weightCast[proposalId][account] += votes) <= accountVotes, "Governor: total weight exceeded");
    }

    /**
     * @dev Cast a vote assuming `alligator` is sending the correct voting power, has recorded weight cast
     * for proxy addresses and has done the necessary checks.
     *
     * @param proposalId The id of the proposal to vote on
     * @param voter The address who cast the vote on behalf of the proxy
     * @param support The support of the vote, `0` for against and `1` for for
     * @param reason The reason given for the vote by the voter
     * @param votes The number of votes to count
     * @param params The params for the vote
     */
    function castVoteFromAlligator(
        uint256 proposalId,
        address voter,
        uint8 support,
        string memory reason,
        uint256 votes,
        bytes calldata params
    ) external onlyAlligator {
        require(state(proposalId) == ProposalState.Active, "Governor: vote not currently active");

        // Skip `totalWeight` check and count `votes`
        ProposalVote storage proposalVote = _proposalVotes[proposalId];

        if (!proposalVote.hasVoted[voter]) {
            proposalVote.hasVoted[voter] = true;
            votes += _getVotes(voter, _proposals[proposalId].voteStart.getDeadline(), "");
        }

        if (support == uint8(VoteType.Against)) {
            proposalVote.againstVotes += votes;
        } else if (support == uint8(VoteType.For)) {
            proposalVote.forVotes += votes;
        } else if (support == uint8(VoteType.Abstain)) {
            proposalVote.abstainVotes += votes;
        } else {
            revert InvalidVoteType();
        }

        address votingModule = _proposals[proposalId].votingModule;

        if (votingModule != address(0)) {
            VotingModule(votingModule)._countVote(proposalId, voter, support, votes, params);
        }

        /// @dev `voter` is emitted in the event instead of `proxy`
        emit VoteCastWithParams(voter, proposalId, support, votes, reason, params);
    }

    /**
     * @dev Allows manager to modify the proposalType of a proposal, in case it was set incorrectly.
     */
    function editProposalType(uint256 proposalId, uint8 proposalType) external onlyManagerOrTimelock {
        if (proposalSnapshot(proposalId) == 0) revert InvalidProposalId();

        // Revert if `proposalType` is unset or the proposal has a different voting module
        if (
            bytes(PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalType).name).length == 0
                || PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalType).module != _proposals[proposalId].votingModule
        ) {
            revert InvalidProposalType(proposalType);
        }

        _proposals[proposalId].proposalType = proposalType;

        emit ProposalTypeUpdated(proposalId, proposalType);
    }

    /**
     * Approve or reject a voting module. Only the manager can call this function.
     *
     * @param module The address of the voting module to approve or reject.
     * @param approved Whether to approve or reject the voting module.
     */
    function setModuleApproval(address module, bool approved) external onlyManagerOrTimelock {
        approvedModules[module] = approved;
    }

    /**
     * @notice Set the manager address. Only the manager or timelock can call this function.
     * @param _newManager The new manager address.
     */
    function setManager(address _newManager) external onlyManagerOrTimelock {
        emit ManagerSet(manager, _newManager);
        manager = _newManager;
    }

    /**
     * @dev Public endpoint to update the underlying timelock instance. Restricted to the timelock itself, so updates
     * must be proposed, scheduled, and executed through governance proposals.
     *
     * CAUTION: It is not recommended to change the timelock while there are other queued governance proposals.
     */
    function updateTimelock(TimelockControllerUpgradeable newTimelock) external virtual onlyGovernance {
        emit TimelockChange(address(_timelock), address(newTimelock));
        _timelock = newTimelock;
    }

    /**
     * @inheritdoc GovernorUpgradeableV2
     */
    function relay(address target, uint256 value, bytes calldata data)
        external
        payable
        virtual
        override(GovernorUpgradeableV2)
        onlyGovernance
    {
        if (approvedModules[target]) revert InvalidRelayTarget(target);
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        AddressUpgradeable.verifyCallResult(success, returndata, "Governor: relay reverted without message");
    }

    /**
     * @notice Returns the proposal type of a proposal.
     * @param proposalId The id of the proposal.
     */
    function getProposalType(uint256 proposalId) external view returns (uint8) {
        return _proposals[proposalId].proposalType;
    }

    /*//////////////////////////////////////////////////////////////
                             PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc GovernorUpgradeableV2
     * @dev Updated version in which default `proposalType` is set to 0.
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override(GovernorUpgradeableV2) returns (uint256) {
        return propose(targets, values, calldatas, description, 0);
    }

    /**
     * @notice Propose a new proposal. Only the manager or an address with votes above the proposal threshold can propose.
     * See {IGovernor-propose}.
     * @dev Updated version of `propose` in which `proposalType` is set and checked.
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint8 proposalType
    ) public virtual returns (uint256 proposalId) {
        address proposer = _msgSender();
        if (proposer != manager && getVotes(proposer, block.number - 1) < proposalThreshold()) {
            revert InvalidVotesBelowThreshold();
        }

        if (targets.length != values.length) revert InvalidProposalLength();
        if (targets.length != calldatas.length) revert InvalidProposalLength();
        if (targets.length == 0) revert InvalidEmptyProposal();

        // Revert if `proposalType` is unset or requires module
        if (
            bytes(PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalType).name).length == 0
                || PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalType).module != address(0)
        ) {
            revert InvalidProposalType(proposalType);
        }

        proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));

        ProposalCore storage proposal = _proposals[proposalId];
        if (!proposal.voteStart.isUnset()) revert InvalidProposalExists();

        uint64 snapshot = block.number.toUint64() + votingDelay().toUint64();
        uint64 deadline = snapshot + votingPeriod().toUint64();

        proposal.voteStart.setDeadline(snapshot);
        proposal.voteEnd.setDeadline(deadline);
        proposal.proposalType = proposalType;
        proposal.proposer = proposer;

        emit ProposalCreated(
            proposalId,
            proposer,
            targets,
            values,
            new string[](targets.length),
            calldatas,
            snapshot,
            deadline,
            description,
            proposalType
        );
    }

    /**
     * @notice Propose a new proposal using a custom voting module. Only the manager or an address with votes above the
     * proposal threshold can propose.
     * @param module The address of the voting module to use for this proposal.
     * @param proposalData The proposal data to pass to the voting module.
     * @param description The description of the proposal.
     * @param proposalType The type of the proposal.
     * @dev Updated version in which `proposalType` is set and checked.
     * @return proposalId The id of the proposal.
     */
    function proposeWithModule(
        VotingModule module,
        bytes memory proposalData,
        string memory description,
        uint8 proposalType
    ) public virtual returns (uint256 proposalId) {
        address proposer = _msgSender();
        if (proposer != manager) {
            if (getVotes(proposer, block.number - 1) < proposalThreshold()) revert InvalidVotesBelowThreshold();
        }

        require(approvedModules[address(module)], "Governor: module not approved");

        // Revert if `proposalType` is unset or doesn't match module
        if (
            bytes(PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalType).name).length == 0
                || PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalType).module != address(module)
        ) {
            revert InvalidProposalType(proposalType);
        }

        bytes32 descriptionHash = keccak256(bytes(description));

        proposalId = hashProposalWithModule(address(module), proposalData, descriptionHash);

        ProposalCore storage proposal = _proposals[proposalId];
        if (!proposal.voteStart.isUnset()) revert InvalidProposalExists();

        uint64 snapshot = block.number.toUint64() + votingDelay().toUint64();
        uint64 deadline = snapshot + votingPeriod().toUint64();

        proposal.voteStart.setDeadline(snapshot);
        proposal.voteEnd.setDeadline(deadline);
        proposal.votingModule = address(module);
        proposal.proposalType = proposalType;
        proposal.proposer = proposer;

        module.propose(proposalId, proposalData, descriptionHash);

        emit ProposalCreated(
            proposalId, proposer, address(module), proposalData, snapshot, deadline, description, proposalType
        );
    }

    function queue(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
        public
        returns (uint256)
    {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);

        require(state(proposalId) == ProposalState.Succeeded, "Governor: proposal not successful");

        uint256 delay = _timelock.getMinDelay();
        _timelockIds[proposalId] = _timelock.hashOperationBatch(targets, values, calldatas, 0, descriptionHash);
        _timelock.scheduleBatch(targets, values, calldatas, 0, descriptionHash, delay);

        emit ProposalQueued(proposalId, block.timestamp + delay);

        return proposalId;
    }

    /**
     * @notice Queue a proposal with a custom voting module. See {GovernorTimelockControlUpgradeableV2-queue}.
     */
    function queueWithModule(VotingModule module, bytes memory proposalData, bytes32 descriptionHash)
        public
        returns (uint256)
    {
        uint256 proposalId = hashProposalWithModule(address(module), proposalData, descriptionHash);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            module._formatExecuteParams(proposalId, proposalData);

        require(state(proposalId) == ProposalState.Succeeded, "Governor: proposal not successful");

        uint256 delay = _timelock.getMinDelay();
        _timelockIds[proposalId] = _timelock.hashOperationBatch(targets, values, calldatas, 0, descriptionHash);
        _timelock.scheduleBatch(targets, values, calldatas, 0, descriptionHash, delay);

        emit ProposalQueued(proposalId, block.timestamp + delay);

        return proposalId;
    }

    /**
     * @inheritdoc GovernorUpgradeableV2
     */
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable override(GovernorUpgradeableV2) returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);

        require(state(proposalId) == ProposalState.Queued, "Governor: proposal not queued");
        _proposals[proposalId].executed = true;

        emit ProposalExecuted(proposalId);

        _beforeExecute(proposalId, targets, values, calldatas, descriptionHash);
        _execute(proposalId, targets, values, calldatas, descriptionHash);
        _afterExecute(proposalId, targets, values, calldatas, descriptionHash);

        return proposalId;
    }

    /**
     * Executes a proposal via a custom voting module. See {IGovernor-execute}.
     *
     * @param module The address of the voting module to use for this proposal.
     * @param proposalData The proposal data to pass to the voting module.
     * @param descriptionHash The hash of the proposal description.
     */
    function executeWithModule(VotingModule module, bytes memory proposalData, bytes32 descriptionHash)
        public
        payable
        virtual
        returns (uint256)
    {
        uint256 proposalId = hashProposalWithModule(address(module), proposalData, descriptionHash);

        ProposalState status = state(proposalId);
        require(status == ProposalState.Queued, "Governor: proposal not queued");
        _proposals[proposalId].executed = true;

        emit ProposalExecuted(proposalId);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            module._formatExecuteParams(proposalId, proposalData);

        _beforeExecute(proposalId, targets, values, calldatas, descriptionHash);
        _execute(proposalId, targets, values, calldatas, descriptionHash);
        _afterExecute(proposalId, targets, values, calldatas, descriptionHash);

        return proposalId;
    }

    /**
     * @notice Cancels a proposal. Only the manager, governor timelock, or proposer can cancel.
     * @param targets Array of target addresses for proposal calls
     * @param values Array of ETH values for proposal calls
     * @param calldatas Array of calldata for proposal calls
     * @param descriptionHash Hash of proposal description
     * @return proposalId The id of the canceled proposal
     */
    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public returns (uint256 proposalId) {
        proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        _cancel(proposalId);
    }

    /**
     * @notice Cancel a proposal with a custom voting module. See {GovernorUpgradeableV2-_cancel}.
     * @param module The address of the voting module to use for this proposal.
     * @param proposalData The proposal data to pass to the voting module.
     * @param descriptionHash The hash of the proposal description.
     * @return proposalId The id of the proposal.
     */
    function cancelWithModule(VotingModule module, bytes memory proposalData, bytes32 descriptionHash)
        public
        virtual
        returns (uint256 proposalId)
    {
        proposalId = hashProposalWithModule(address(module), proposalData, descriptionHash);
        _cancel(proposalId);
    }

    /**
     * @notice Internal function to cancel a proposal based on a proposal ID.
     * @dev This function is called by both `cancel` and `cancelWithModule`
     * @param proposalId The id of the proposal to cancel
     */
    function _cancel(uint256 proposalId) internal {
        address sender = _msgSender();
        require(
            sender == manager || sender == timelock() || sender == _proposals[proposalId].proposer,
            "Governor: only manager, governor timelock, or proposer can cancel"
        );

        // GovernorUpgradeableV2._cancel
        ProposalState status = state(proposalId);

        require(
            status != ProposalState.Canceled && status != ProposalState.Expired && status != ProposalState.Executed,
            "Governor: proposal not active"
        );
        _proposals[proposalId].canceled = true;

        emit ProposalCanceled(proposalId);

        // GovernorTimelockControlUpgradeableV2._cancel
        if (_timelockIds[proposalId] != 0) {
            _timelock.cancel(_timelockIds[proposalId]);
            delete _timelockIds[proposalId];
        }
    }

    function setProposalDeadline(uint256 proposalId, uint64 deadline) public onlyManagerOrTimelock {
        _proposals[proposalId].voteEnd.setDeadline(deadline);
        emit ProposalDeadlineUpdated(proposalId, deadline);
    }

    function setVotingDelay(uint256 newVotingDelay) public override onlyManagerOrTimelock {
        _setVotingDelay(newVotingDelay);
    }

    function setVotingPeriod(uint256 newVotingPeriod) public override onlyManagerOrTimelock {
        _setVotingPeriod(newVotingPeriod);
    }

    function setProposalThreshold(uint256 newProposalThreshold) public override onlyManagerOrTimelock {
        _setProposalThreshold(newProposalThreshold);
    }

    /**
     * Returns the quorum for a `proposalId`, in terms of number of votes: `supply * numerator / denominator`.
     *
     * @dev Based on `votableSupply` by default, but falls back to `totalSupply` if not available.
     * @dev Supply is calculated at the proposal snapshot block
     * @dev Quorum value is derived from `PROPOSAL_TYPES_CONFIGURATOR`
     */
    function quorum(uint256 proposalId) public view virtual override(IGovernorUpgradeable) returns (uint256) {
        uint256 snapshotBlock = proposalSnapshot(proposalId);
        uint256 supply = votableSupply(snapshotBlock);

        // Fallback to total supply if votable supply was unset at `snapshotBlock`
        if (supply == 0) {
            supply = token.getPastTotalSupply(snapshotBlock);
        }

        return (supply * PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(_proposals[proposalId].proposalType).quorum)
            / PERCENT_DIVISOR;
    }

    /**
     * Calculate `proposalId` hashing similarly to `hashProposal` but based on `module` and `proposalData`.
     * See {IGovernor-hashProposal}.
     *
     * @param module The address of the voting module to use for this proposal.
     * @param proposalData The proposal data to pass to the voting module.
     * @param descriptionHash The hash of the proposal description.
     * @return The id of the proposal.
     */
    function hashProposalWithModule(address module, bytes memory proposalData, bytes32 descriptionHash)
        public
        view
        virtual
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(address(this), module, proposalData, descriptionHash)));
    }

    function proposalThreshold()
        public
        view
        override(GovernorSettingsUpgradeableV2, GovernorUpgradeableV2)
        returns (uint256)
    {
        return GovernorSettingsUpgradeableV2.proposalThreshold();
    }

    function state(uint256 proposalId) public view virtual override(GovernorUpgradeableV2) returns (ProposalState) {
        ProposalState status = super.state(proposalId);

        if (status != ProposalState.Succeeded) {
            return status;
        } else if (_upgradeBlock != 0 && block.number >= _upgradeBlock) {
            // Mark successful proposals before upgrade as executed to prevent them from being queued and executed.
            return ProposalState.Executed;
        }

        // core tracks execution, so we just have to check if successful proposal have been queued.
        bytes32 queueid = _timelockIds[proposalId];
        if (queueid == bytes32(0)) {
            return status;
        } else if (_timelock.isOperationDone(queueid)) {
            return ProposalState.Executed;
        } else if (_timelock.isOperationPending(queueid)) {
            return ProposalState.Queued;
        } else {
            return ProposalState.Canceled;
        }
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(GovernorUpgradeableV2) returns (bool) {
        return interfaceId == type(IGovernorTimelockUpgradeable).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Public accessor to check the address of the timelock
     */
    function timelock() public view virtual returns (address) {
        return address(_timelock);
    }

    /**
     * @dev Public accessor to check the eta of a queued proposal
     */
    function proposalEta(uint256 proposalId) public view virtual returns (uint256) {
        uint256 eta = _timelock.getTimestamp(_timelockIds[proposalId]);
        return eta == 1 ? 0 : eta; // _DONE_TIMESTAMP (1) should be replaced with a 0 value
    }

    /**
     * Add support for `weightCast` to check if `account` has voted on `proposalId`.
     */
    function hasVoted(uint256 proposalId, address account)
        public
        view
        virtual
        override(GovernorCountingSimpleUpgradeableV2, IGovernorUpgradeable)
        returns (bool)
    {
        return weightCast[proposalId][account] != 0 || _proposalVotes[proposalId].hasVoted[account];
    }

    /**
     * @dev Returns the votable supply for the current block number.
     */
    function votableSupply() public view virtual returns (uint256) {
        return VOTABLE_SUPPLY_ORACLE.votableSupply();
    }

    /**
     * @dev Returns the votable supply for `blockNumber`.
     */
    function votableSupply(uint256 blockNumber) public view virtual returns (uint256) {
        return VOTABLE_SUPPLY_ORACLE.votableSupply(blockNumber);
    }

    /**
     * @dev See {IGovernor-COUNTING_MODE}.
     * Params encoding:
     * - modules = custom external params depending on module used
     */
    function COUNTING_MODE()
        public
        pure
        virtual
        override(GovernorCountingSimpleUpgradeableV2, IGovernorUpgradeable)
        returns (string memory)
    {
        return "support=bravo&quorum=against,for,abstain&params=modules";
    }

    /**
     * @dev Returns the current version of the governor.
     */
    function VERSION() public pure virtual returns (uint256) {
        return 4;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeableV2) returns (uint256) {
        uint256 proposalId = super._cancel(targets, values, calldatas, descriptionHash);

        if (_timelockIds[proposalId] != 0) {
            _timelock.cancel(_timelockIds[proposalId]);
            delete _timelockIds[proposalId];
        }

        return proposalId;
    }

    function _execute(
        uint256,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeableV2) {
        _timelock.executeBatch{value: msg.value}(targets, values, calldatas, 0, descriptionHash);
    }

    /**
     * @dev Updated internal vote casting mechanism which delegates counting logic to voting module,
     * in addition to executing standard `_countVote`. See {IGovernor-_castVote}.
     */
    function _castVote(uint256 proposalId, address account, uint8 support, string memory reason, bytes memory params)
        internal
        virtual
        override
        returns (uint256 weight)
    {
        require(state(proposalId) == ProposalState.Active, "Governor: vote not currently active");

        weight = _getVotes(account, _proposals[proposalId].voteStart.getDeadline(), "");

        _countVote(proposalId, account, support, weight, params);

        address votingModule = _proposals[proposalId].votingModule;

        if (votingModule != address(0)) {
            VotingModule(votingModule)._countVote(proposalId, account, support, weight, params);
        }

        if (params.length == 0) {
            emit VoteCast(account, proposalId, support, weight, reason);
        } else {
            emit VoteCastWithParams(account, proposalId, support, weight, reason, params);
        }
    }

    function _executor() internal view override(GovernorUpgradeableV2) returns (address) {
        return address(_timelock);
    }

    /**
     * @dev Updated version in which quorum is based on `proposalId` instead of snapshot block.
     */
    function _quorumReached(uint256 proposalId)
        internal
        view
        virtual
        override(GovernorCountingSimpleUpgradeableV2, GovernorUpgradeableV2)
        returns (bool)
    {
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = proposalVotes(proposalId);

        return quorum(proposalId) <= againstVotes + forVotes + abstainVotes;
    }

    /**
     * @dev Added logic based on approval voting threshold to determine if vote has succeeded.
     */
    function _voteSucceeded(uint256 proposalId)
        internal
        view
        virtual
        override(GovernorCountingSimpleUpgradeableV2, GovernorUpgradeableV2)
        returns (bool voteSucceeded)
    {
        ProposalCore storage proposal = _proposals[proposalId];

        address votingModule = proposal.votingModule;
        if (votingModule != address(0)) {
            if (!VotingModule(votingModule)._voteSucceeded(proposalId)) {
                return false;
            }
        }

        uint256 approvalThreshold = PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposal.proposalType).approvalThreshold;

        if (approvalThreshold == 0) return true;

        ProposalVote storage proposalVote = _proposalVotes[proposalId];
        uint256 forVotes = proposalVote.forVotes;
        uint256 totalVotes = forVotes + proposalVote.againstVotes;

        if (totalVotes != 0) {
            voteSucceeded = (forVotes * PERCENT_DIVISOR) / totalVotes >= approvalThreshold;
        }
    }
}
