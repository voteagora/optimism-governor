// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../src/OptimismGovernorV5.sol";

// Expose internal functions for testing and add execution logic
contract OptimismGovernorV5ExecuteMock is OptimismGovernorV5 {
    function quorumReached(uint256 proposalId) public view returns (bool) {
        return _quorumReached(proposalId);
    }

    function voteSucceeded(uint256 proposalId) public view returns (bool) {
        return _voteSucceeded(proposalId);
    }

    function execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external {
        return GovernorUpgradeableV2._execute(proposalId, targets, values, calldatas, descriptionHash);
    }
}
