// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {GovernorUpgradeableV2} from "./lib/openzeppelin/v2/GovernorUpgradeableV2.sol";
import {GovernorCountingSimpleUpgradeableV2} from "./lib/openzeppelin/v2/GovernorCountingSimpleUpgradeableV2.sol";
import {GovernorVotesQuorumFractionUpgradeableV2} from
    "./lib/openzeppelin/v2/GovernorVotesQuorumFractionUpgradeableV2.sol";
import {GovernorVotesUpgradeableV2} from "./lib/openzeppelin/v2/GovernorVotesUpgradeableV2.sol";
import {GovernorSettingsUpgradeableV2} from "./lib/openzeppelin/v2/GovernorSettingsUpgradeableV2.sol";
import {IGovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {TimersUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/TimersUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {VotingModule} from "./modules/VotingModule.sol";
import {IVotableSupplyOracle} from "./interfaces/IVotableSupplyOracle.sol";
import {IProposalTypesConfigurator} from "./interfaces/IProposalTypesConfigurator.sol";

/**
 * Introduces support for voting modules.
 */
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

    /**
     * Emitted when a proposal with module is created.
     */
    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address votingModule,
        bytes proposalData,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );
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
    event ProposalDeadlineUpdated(uint256 proposalId, uint64 deadline);
    event ProposalTypeUpdated(uint256 indexed proposalId, uint8 proposalType);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidProposalType(uint8 proposalType);
    error InvalidProposalId();

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public manager;
    mapping(address module => bool approved) public approvedModules;

    uint256 private constant GOVERNOR_VERSION = 2;

    // Max value of `quorum` and `approvalThreshold` in `ProposalType`
    uint16 public constant PERCENT_DIVISOR = 10_000;

    // TODO: Before deploying, set correct addresses
    address public constant ALLIGATOR = 0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9;

    IVotableSupplyOracle public constant VOTABLE_SUPPLY_ORACLE =
        IVotableSupplyOracle(0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b);

    IProposalTypesConfigurator public constant PROPOSAL_TYPES_CONFIGURATOR =
        IProposalTypesConfigurator(0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264);

    /**
     * Total number of `votes` that `account` has cast for `proposalId`.
     * @dev Replaces non-quantitative `_proposalVotes.hasVoted` to add support for partial voting.
     */
    mapping(uint256 proposalId => mapping(address account => uint256 votes)) public weightCast;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                               ALLIGATOR
    //////////////////////////////////////////////////////////////*/

    modifier onlyAlligator() {
        if (msg.sender != ALLIGATOR) revert("Unauthorized");
        _;
    }

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
            revert("GovernorVotingSimple: invalid value for enum VoteType");
        }

        address votingModule = _proposals[proposalId].votingModule;

        if (votingModule != address(0)) {
            VotingModule(votingModule)._countVote(proposalId, voter, support, votes, params);
        }

        /// @dev `voter` is emitted in the event instead of `proxy`
        emit VoteCastWithParams(voter, proposalId, support, votes, reason, params);
    }

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Allows manager to modify the proposalType of a proposal, in case it was set incorrectly.
     */
    function editProposalType(uint256 proposalId, uint8 proposalType) external onlyManager {
        if (proposalSnapshot(proposalId) == 0) revert InvalidProposalId();

        // Revert if `proposalType` is unset
        if (bytes(PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalType).name).length == 0) {
            revert InvalidProposalType(proposalType);
        }

        _proposals[proposalId].proposalType = proposalType;

        emit ProposalTypeUpdated(proposalId, proposalType);
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
        require(status == ProposalState.Succeeded, "Governor: proposal not successful");
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
     * Cancel a proposal with a custom voting module. See {IGovernor-_cancel}.
     *
     * @param module The address of the voting module to use for this proposal.
     * @param proposalData The proposal data to pass to the voting module.
     * @param descriptionHash The hash of the proposal description.
     */
    function cancelWithModule(VotingModule module, bytes memory proposalData, bytes32 descriptionHash)
        public
        virtual
        onlyManager
        returns (uint256)
    {
        uint256 proposalId = hashProposalWithModule(address(module), proposalData, descriptionHash);
        ProposalState status = state(proposalId);

        require(status != ProposalState.Canceled && status != ProposalState.Executed, "Governor: proposal not active");
        _proposals[proposalId].canceled = true;

        emit ProposalCanceled(proposalId);

        return proposalId;
    }

    /**
     * Approve or reject a voting module. Only the manager can call this function.
     *
     * @param module The address of the voting module to approve or reject.
     * @param approved Whether to approve or reject the voting module.
     */
    function setModuleApproval(address module, bool approved) public onlyManager {
        approvedModules[module] = approved;
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

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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
     * COUNTING_MODE with added `params=modules` options to indicate support for external voting modules. See {IGovernor-COUNTING_MODE}.
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
        return GOVERNOR_VERSION;
    }

    /**
     * @dev Updated `_voteSucceeded` to add custom success conditions defined in the voting module. See {Governor-_voteSucceeded}.
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
            if (!VotingModule(votingModule)._voteSucceeded(proposalId)) return false;
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

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                                   V2
    //////////////////////////////////////////////////////////////*/

    modifier onlyManager() {
        require(msg.sender == manager, "Only the manager can call this function");
        _;
    }

    function _execute(
        uint256, /* proposalId */
        address[] memory, /* targets */
        uint256[] memory, /* values */
        bytes[] memory, /* calldatas */
        bytes32 /*descriptionHash*/
    ) internal view override onlyManager {
        // Execution is skipped
    }

    /**
     * @dev Updated version in which `proposalType` is set and checked.
     */
    function proposeWithModule(
        VotingModule module,
        bytes memory proposalData,
        string memory description,
        uint8 proposalType
    ) public virtual onlyManager returns (uint256 proposalId) {
        require(
            getVotes(_msgSender(), block.number - 1) >= proposalThreshold(),
            "Governor: proposer votes below proposal threshold"
        );
        require(approvedModules[address(module)], "Governor: module not approved");

        // Revert if `proposalType` is unset
        if (bytes(PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalType).name).length == 0) {
            revert InvalidProposalType(proposalType);
        }

        bytes32 descriptionHash = keccak256(bytes(description));

        proposalId = hashProposalWithModule(address(module), proposalData, descriptionHash);

        ProposalCore storage proposal = _proposals[proposalId];
        require(proposal.voteStart.isUnset(), "Governor: proposal already exists");

        uint64 snapshot = block.number.toUint64() + votingDelay().toUint64();
        uint64 deadline = snapshot + votingPeriod().toUint64();

        proposal.voteStart.setDeadline(snapshot);
        proposal.voteEnd.setDeadline(deadline);
        proposal.votingModule = address(module);
        proposal.proposalType = proposalType;

        module.propose(proposalId, proposalData, descriptionHash);

        emit ProposalCreated(
            proposalId, _msgSender(), address(module), proposalData, snapshot, deadline, description, proposalType
        );
    }

    /**
     * @dev Updated version of `propose` in which `proposalType` is set and checked.
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint8 proposalType
    ) public virtual onlyManager returns (uint256 proposalId) {
        require(
            getVotes(_msgSender(), block.number - 1) >= proposalThreshold(),
            "Governor: proposer votes below proposal threshold"
        );
        require(targets.length == values.length, "Governor: invalid proposal length");
        require(targets.length == calldatas.length, "Governor: invalid proposal length");
        require(targets.length > 0, "Governor: empty proposal");

        // Revert if `proposalType` is unset
        if (bytes(PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalType).name).length == 0) {
            revert InvalidProposalType(proposalType);
        }

        proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));

        ProposalCore storage proposal = _proposals[proposalId];
        require(proposal.voteStart.isUnset(), "Governor: proposal already exists");

        uint64 snapshot = block.number.toUint64() + votingDelay().toUint64();
        uint64 deadline = snapshot + votingPeriod().toUint64();

        proposal.voteStart.setDeadline(snapshot);
        proposal.voteEnd.setDeadline(deadline);
        proposal.proposalType = proposalType;

        emit ProposalCreated(
            proposalId,
            _msgSender(),
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

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override onlyManager returns (uint256) {
        return propose(targets, values, calldatas, description, 0);
    }

    function proposeWithModule(VotingModule module, bytes memory proposalData, string memory description)
        public
        virtual
        returns (uint256)
    {
        return proposeWithModule(module, proposalData, description, 0);
    }

    function proposalThreshold()
        public
        view
        override(GovernorSettingsUpgradeableV2, GovernorUpgradeableV2)
        returns (uint256)
    {
        return GovernorSettingsUpgradeableV2.proposalThreshold();
    }

    function quorumDenominator() public view virtual override returns (uint256) {
        // Configurable to 3 decimal points of percentage
        return 100_000;
    }

    /**
     * Returns the quorum for a `proposalId`, in terms of number of votes: `supply * numerator / denominator`.
     *
     * @dev Based on `votableSupply` by default, but falls back to `totalSupply` if not available.
     * @dev Supply is calculated at the proposal snapshot block
     * @dev Quorum value is derived from `PROPOSAL_TYPES_CONFIGURATOR`
     */
    function quorum(uint256 proposalId)
        public
        view
        virtual
        override(GovernorVotesQuorumFractionUpgradeableV2, IGovernorUpgradeable)
        returns (uint256)
    {
        uint256 snapshotBlock = proposalSnapshot(proposalId);
        uint256 supply = votableSupply(snapshotBlock);

        // Fallback to total supply if votable supply was unset at `snapshotBlock`
        if (supply == 0) {
            return token.getPastTotalSupply(snapshotBlock) * quorumNumerator(snapshotBlock) / quorumDenominator();
        }

        uint256 proposalTypeId = _proposals[proposalId].proposalType;

        return (supply * PROPOSAL_TYPES_CONFIGURATOR.proposalTypes(proposalTypeId).quorum) / PERCENT_DIVISOR;
    }

    function getProposalType(uint256 proposalId) external view returns (uint8) {
        return _proposals[proposalId].proposalType;
    }

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

    function setProposalDeadline(uint256 proposalId, uint64 deadline) public onlyManager {
        _proposals[proposalId].voteEnd.setDeadline(deadline);
        emit ProposalDeadlineUpdated(proposalId, deadline);
    }

    function setVotingDelay(uint256 newVotingDelay) public override onlyManager {
        _setVotingDelay(newVotingDelay);
    }

    function setVotingPeriod(uint256 newVotingPeriod) public override onlyManager {
        _setVotingPeriod(newVotingPeriod);
    }

    function setProposalThreshold(uint256 newProposalThreshold) public override onlyManager {
        _setProposalThreshold(newProposalThreshold);
    }

    function updateQuorumNumerator(uint256 newQuorumNumerator) external override onlyManager {
        _updateQuorumNumerator(newQuorumNumerator);
    }

    /*//////////////////////////////////////////////////////////////
                                   V3
    //////////////////////////////////////////////////////////////*/

    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public onlyManager returns (uint256) {
        return _cancel(targets, values, calldatas, descriptionHash);
    }
}
