// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

abstract contract VotingModule {
    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    function _onlyGovernor(address governor) internal view {
        require(msg.sender == governor, "Only the governor can call this function");
    }

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function propose(uint256 proposalId, bytes memory proposalData) external virtual;

    function _countVote(uint256 proposalId, address account, uint8 support, uint256 weight, bytes memory params)
        external
        virtual;

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function hasVoted(uint256 proposalId, address account) external view virtual returns (bool);

    function _formatExecuteParams(uint256 proposalId, bytes memory proposalData)
        external
        view
        virtual
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas);

    function _quorumReached(uint256 proposalId, uint256 quorum) external view virtual returns (bool);

    function _voteSucceeded(uint256 proposalId) external view virtual returns (bool);

    function COUNTING_MODE() external pure virtual returns (string memory);
}
