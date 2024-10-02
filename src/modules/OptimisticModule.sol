// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IGovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IProposalTypesConfigurator} from "src/interfaces/IProposalTypesConfigurator.sol";
import {IOptimismGovernor} from "src/interfaces/IOptimismGovernor.sol";
import {VotingModule} from "src/modules/VotingModule.sol";

enum VoteType {
    Against,
    For,
    Abstain
}

struct ProposalSettings {
    uint248 againstThreshold;
    bool isRelativeToVotableSupply;
}

struct Proposal {
    address governor;
    ProposalSettings settings;
}

contract OptimisticModule_SocialSignalling is VotingModule {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error WrongProposalId();
    error NotOptimisticProposalType();

    /*//////////////////////////////////////////////////////////////
                           IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    uint16 public constant PERCENT_DIVISOR = 10_000;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 proposalId => Proposal) public proposals;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _governor) VotingModule(_governor) {}

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * Validate proposal is optimistic and save settings for a new proposal.
     *
     * @param proposalId The id of the proposal.
     * @param proposalData The proposal data encoded as `PROPOSAL_DATA_ENCODING`.
     */
    function propose(uint256 proposalId, bytes memory proposalData, bytes32 descriptionHash) external override {
        _onlyGovernor();
        if (proposalId != uint256(keccak256(abi.encode(msg.sender, address(this), proposalData, descriptionHash)))) {
            revert WrongProposalId();
        }

        if (proposals[proposalId].governor != address(0)) {
            revert ExistingProposal();
        }

        ProposalSettings memory proposalSettings = abi.decode(proposalData, (ProposalSettings));

        uint8 proposalTypeId = IOptimismGovernor(msg.sender).getProposalType(proposalId);
        IProposalTypesConfigurator proposalConfigurator =
            IProposalTypesConfigurator(IOptimismGovernor(msg.sender).PROPOSAL_TYPES_CONFIGURATOR());
        IProposalTypesConfigurator.ProposalType memory proposalType = proposalConfigurator.proposalTypes(proposalTypeId);

        if (proposalType.quorum != 0 || proposalType.approvalThreshold != 0) {
            revert NotOptimisticProposalType();
        }
        if (
            proposalSettings.againstThreshold == 0
                || (proposalSettings.isRelativeToVotableSupply && proposalSettings.againstThreshold > PERCENT_DIVISOR)
        ) {
            revert InvalidParams();
        }

        proposals[proposalId].governor = msg.sender;
        proposals[proposalId].settings = proposalSettings;
    }

    /**
     * Counting logic is skipped.
     */
    function _countVote(uint256, address, uint8, uint256, bytes memory) external virtual override {}

    /**
     * Format executeParams for a governor, given `proposalId` and `proposalData`.
     * Returns empty `targets`, `values` and `calldatas`.
     *
     * @return targets The targets of the proposal.
     * @return values The values of the proposal.
     * @return calldatas The calldatas of the proposal.
     */
    function _formatExecuteParams(uint256, bytes memory)
        public
        pure
        override
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](0);
        values = new uint256[](0);
        calldatas = new bytes[](0);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Return true if `againstVotes` is lower than `againstThreshold`.
     * Used by governor in `_voteSucceeded`. See {Governor-_voteSucceeded}.
     *
     * @param proposalId The id of the proposal.
     */
    function _voteSucceeded(uint256 proposalId) external view override returns (bool) {
        Proposal memory proposal = proposals[proposalId];
        (uint256 againstVotes,,) = IOptimismGovernor(proposal.governor).proposalVotes(proposalId);

        uint256 againstThreshold = proposal.settings.againstThreshold;
        if (proposal.settings.isRelativeToVotableSupply) {
            uint256 snapshotBlock = IGovernorUpgradeable(proposal.governor).proposalSnapshot(proposalId);
            IVotesUpgradeable token = IOptimismGovernor(proposal.governor).token();
            againstThreshold = (token.getPastTotalSupply(snapshotBlock) * againstThreshold) / PERCENT_DIVISOR;
        }

        return againstVotes < againstThreshold;
    }

    /**
     * Defines the encoding for the expected `proposalData` in `propose`.
     * Encoding: `(ProposalSettings)`
     *
     * @dev Can be used by clients to interact with modules programmatically without prior knowledge
     * on expected types.
     */
    function PROPOSAL_DATA_ENCODING() external pure virtual override returns (string memory) {
        return "((uint248 againstThreshold,bool isRelativeToVotableSupply) proposalSettings)";
    }

    /**
     * Defines the encoding for the expected `params` in `_countVote`.
     *
     * @dev Can be used by clients to interact with modules programmatically without prior knowledge
     * on expected types.
     */
    function VOTE_PARAMS_ENCODING() external pure virtual override returns (string memory) {
        return "";
    }

    /**
     * @dev See {IGovernor-COUNTING_MODE}.
     *
     * - `support=bravo`: Supports vote options 0 = Against, 1 = For, 2 = Abstain, as in `GovernorBravo`.
     * - `quorum=for,abstain`: Against, For and Abstain votes are counted towards quorum.
     */
    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "support=bravo&quorum=against,for,abstain";
    }

    /**
     * Module version.
     */
    function version() public pure returns (uint256) {
        return 1;
    }
}
