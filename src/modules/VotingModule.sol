// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

abstract contract VotingModule {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotGovernor();
    error InvalidVoteType();
    error ExistingProposal();
    error InvalidParams();
    error VoteAlreadyCast();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    function _onlyGovernor(address governor) internal view {
        if (msg.sender != governor) revert NotGovernor();
    }

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function propose(uint256 proposalId, bytes memory proposalData) external virtual;

    function _afterExecute(uint256 proposalId, bytes memory proposalData) external virtual {}

    function _countVote(uint256 proposalId, address account, uint8 support, uint256 weight, bytes memory params)
        external
        virtual;

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function hasVoted(uint256 proposalId, address account) external view virtual returns (bool);

    function _formatExecuteParams(uint256 proposalId, bytes memory proposalData)
        external
        virtual
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas);

    function _quorumReached(uint256 proposalId, uint256 quorum) external view virtual returns (bool);

    function _voteSucceeded(uint256 proposalId) external view virtual returns (bool);

    function COUNTING_MODE() external pure virtual returns (string memory);

    function PROPOSAL_DATA_ENCODING() external pure virtual returns (string memory);

    function VOTE_PARAMS_ENCODING() external pure virtual returns (string memory);
}
