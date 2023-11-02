// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IProposalTypesConfigurator {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidQuorum();
    error InvalidApprovalThreshold();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProposalTypeSet(uint256 indexed proposalTypeId, uint16 quorum, uint16 approvalThreshold, string name);

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct ProposalType {
        uint16 quorum;
        uint16 approvalThreshold;
        string name;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function proposalTypes(uint256 proposalTypeId) external view returns (ProposalType memory);

    function setProposalType(uint256 proposalTypeId, uint16 quorum, uint16 approvalThreshold, string memory name)
        external;
}
