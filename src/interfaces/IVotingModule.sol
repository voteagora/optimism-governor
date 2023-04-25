// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVotingModule {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function propose(uint256 proposalId, bytes memory proposalData) external returns (uint256);

    function castVote(uint256 proposalId, address account, uint8 support, string memory reason, bytes memory params)
        external
        returns (uint256);

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function hasVoted(uint256 proposalId, address account) external view returns (bool);

    function quorumReached(uint256 proposalId, uint256 quorum) external view returns (bool);

    function voteSucceeded(uint256 proposalId) external view returns (bool);

    function COUNTING_MODE() external pure returns (string memory);
}
