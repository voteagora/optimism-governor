// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IProposalTypesConfigurator} from "./interfaces/IProposalTypesConfigurator.sol";
import {IOptimismGovernor} from "./interfaces/IOptimismGovernor.sol";

/**
 * Contract that stores proposalTypes for Optimism Governor.
 */
contract ProposalTypesConfigurator is IProposalTypesConfigurator {
    /*//////////////////////////////////////////////////////////////
                           IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    IOptimismGovernor public immutable governor;
    uint16 public constant PERCENT_DIVISOR = 10_000;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 proposalTypeId => ProposalType) internal _proposalTypes;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyManager() {
        require(msg.sender == governor.manager(), "Only the manager can call this function");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(IOptimismGovernor governor_) {
        governor = governor_;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function proposalTypes(uint256 proposalTypeId) external view override returns (ProposalType memory) {
        return _proposalTypes[proposalTypeId];
    }

    /**
     * @dev Set the parameters for a proposal type. Only callable by the manager.
     *
     * @param proposalTypeId Id of the proposal type
     * @param quorum Quorum percentage, scaled by `PERCENT_DIVISOR`
     * @param approvalThreshold Approval threshold percentage, scaled by `PERCENT_DIVISOR`
     * @param name Name of the proposal type
     */
    function setProposalType(uint256 proposalTypeId, uint16 quorum, uint16 approvalThreshold, string memory name)
        external
        override
        onlyManager
    {
        if (quorum > PERCENT_DIVISOR) revert InvalidQuorum();
        if (approvalThreshold > PERCENT_DIVISOR) revert InvalidApprovalThreshold();

        _proposalTypes[proposalTypeId] = ProposalType(quorum, approvalThreshold, name);

        emit ProposalTypeSet(proposalTypeId, quorum, approvalThreshold, name);
    }
}
