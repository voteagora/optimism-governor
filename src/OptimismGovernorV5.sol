// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {GovernorUpgradeableV2} from "./lib/v2/GovernorUpgradeableV2.sol";
import {GovernorCountingSimpleUpgradeableV2} from "./lib/v2/GovernorCountingSimpleUpgradeableV2.sol";
import {GovernorVotesQuorumFractionUpgradeableV2} from "./lib/v2/GovernorVotesQuorumFractionUpgradeableV2.sol";
import {GovernorVotesUpgradeableV2} from "./lib/v2/GovernorVotesUpgradeableV2.sol";
import {GovernorSettingsUpgradeableV2} from "./lib/v2/GovernorSettingsUpgradeableV2.sol";
import {IGovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {TimersUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/TimersUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {VotingModule} from "./modules/VotingModule.sol";

/**
 * Introduces support for voting modules.
 */
contract OptimismGovernorV5 is
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
    event ProposalDeadlineUpdated(uint256 proposalId, uint64 deadline);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public manager;
    mapping(address => bool approved) public approvedModules;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * Create a new proposal with a custom voting module. See {IGovernor-propose}.
     *
     * @param module The address of the voting module to use for this proposal.
     * @param proposalData The proposal data to pass to the voting module.
     * @param description A human readable description of the proposal.
     */
    function proposeWithModule(VotingModule module, bytes memory proposalData, string memory description)
        public
        onlyManager
        returns (uint256)
    {
        require(
            getVotes(_msgSender(), block.number - 1) >= proposalThreshold(),
            "Governor: proposer votes below proposal threshold"
        );
        require(approvedModules[address(module)], "Governor: module not approved");

        bytes32 descriptionHash = keccak256(bytes(description));

        uint256 proposalId = hashProposalWithModule(address(module), proposalData, descriptionHash);

        ProposalCore storage proposal = _proposals[proposalId];
        require(proposal.voteStart.isUnset(), "Governor: proposal already exists");

        uint64 snapshot = block.number.toUint64() + votingDelay().toUint64();
        uint64 deadline = snapshot + votingPeriod().toUint64();

        proposal.voteStart.setDeadline(snapshot);
        proposal.voteEnd.setDeadline(deadline);
        proposal.votingModule = address(module);

        module.propose(proposalId, proposalData, descriptionHash);

        emit ProposalCreated(proposalId, _msgSender(), address(module), proposalData, snapshot, deadline, description);

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
        module._afterExecute(proposalId, proposalData);

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
        override
        returns (uint256)
    {
        ProposalCore memory proposal = _proposals[proposalId];
        require(state(proposalId) == ProposalState.Active, "Governor: vote not currently active");

        uint256 weight = _getVotes(account, proposal.voteStart.getDeadline(), params);

        _countVote(proposalId, account, support, weight, params);

        if (proposal.votingModule != address(0)) {
            VotingModule(proposal.votingModule)._countVote(proposalId, account, support, weight, params);
        }

        if (params.length == 0) {
            emit VoteCast(account, proposalId, support, weight, reason);
        } else {
            emit VoteCastWithParams(account, proposalId, support, weight, reason, params);
        }

        return weight;
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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
     * @dev Updated `_voteSucceeded` to add custom success conditions defined in the voting module. See {Governor-_voteSucceeded}.
     */
    function _voteSucceeded(uint256 proposalId)
        internal
        view
        virtual
        override(GovernorCountingSimpleUpgradeableV2, GovernorUpgradeableV2)
        returns (bool)
    {
        address votingModule = _proposals[proposalId].votingModule;
        if (votingModule != address(0)) {
            if (!VotingModule(votingModule)._voteSucceeded(proposalId)) return false;
        }

        return super._voteSucceeded(proposalId);
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

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override onlyManager returns (uint256) {
        return super.propose(targets, values, calldatas, description);
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

    function _quorumReached(uint256 proposalId)
        internal
        view
        virtual
        override(GovernorCountingSimpleUpgradeableV2, GovernorUpgradeableV2)
        returns (bool)
    {
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = proposalVotes(proposalId);

        return quorum(proposalSnapshot(proposalId)) <= againstVotes + forVotes + abstainVotes;
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
