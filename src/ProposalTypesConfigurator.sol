// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IProposalTypesConfigurator} from "./interfaces/IProposalTypesConfigurator.sol";
import {IOptimismGovernor} from "./interfaces/IOptimismGovernor.sol";

/**
 * Contract that stores proposalTypes for the Optimism Governor.
 */
contract ProposalTypesConfigurator is IProposalTypesConfigurator {
    /*//////////////////////////////////////////////////////////////
                           IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    IOptimismGovernor public governor;
    uint16 public constant PERCENT_DIVISOR = 10_000;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint8 proposalTypeId => ProposalType) internal _proposalTypes;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyManagerOrTimelock() {
        if (msg.sender != governor.manager() && msg.sender != governor.timelock()) {
            revert NotManagerOrTimelock();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the contract with the governor and proposal types.
     * @param _governor Address of the governor contract.
     * @param _proposalTypesInit Array of ProposalType structs to initialize the contract with.
     */
    function initialize(address _governor, ProposalType[] calldata _proposalTypesInit) external {
        if (address(governor) != address(0)) revert AlreadyInit();
        governor = IOptimismGovernor(_governor);
        for (uint8 i = 0; i < _proposalTypesInit.length; i++) {
            _setProposalType(
                i,
                _proposalTypesInit[i].quorum,
                _proposalTypesInit[i].approvalThreshold,
                _proposalTypesInit[i].name,
                _proposalTypesInit[i].description,
                _proposalTypesInit[i].module
            );
        }
    }

    /**
     * @notice Get the parameters for a proposal type.
     * @param proposalTypeId Id of the proposal type.
     * @return ProposalType struct of of the proposal type.
     */
    function proposalTypes(uint8 proposalTypeId) external view override returns (ProposalType memory) {
        return _proposalTypes[proposalTypeId];
    }

    /**
     * @notice Set the parameters for a proposal type. Only callable by the admin or timelock.
     * @param proposalTypeId Id of the proposal type
     * @param quorum Quorum percentage, scaled by `PERCENT_DIVISOR`
     * @param approvalThreshold Approval threshold percentage, scaled by `PERCENT_DIVISOR`
     * @param name Name of the proposal type
     * @param description Describes the proposal type
     * @param module Address of module that can only use this proposal type
     */
    function setProposalType(
        uint8 proposalTypeId,
        uint16 quorum,
        uint16 approvalThreshold,
        string calldata name,
        string calldata description,
        address module
    ) external override onlyManagerOrTimelock {
        _setProposalType(proposalTypeId, quorum, approvalThreshold, name, description, module);
    }

    function _setProposalType(
        uint8 proposalTypeId,
        uint16 quorum,
        uint16 approvalThreshold,
        string calldata name,
        string calldata description,
        address module
    ) internal {
        if (quorum > PERCENT_DIVISOR) revert InvalidQuorum();
        if (approvalThreshold > PERCENT_DIVISOR) {
            revert InvalidApprovalThreshold();
        }

        _proposalTypes[proposalTypeId] = ProposalType(quorum, approvalThreshold, name, description, module);

        emit ProposalTypeSet(proposalTypeId, quorum, approvalThreshold, name, description);
    }
}
