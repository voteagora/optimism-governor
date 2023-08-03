// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IAlligatorOP} from "../interfaces/IAlligatorOP.sol";

// Proxy implementation that handles gas refunds from governor
contract Proxy {
    address internal immutable alligator;
    address internal immutable governor;

    // Rules
    uint256 internal immutable maxRedelegations;
    uint256 internal immutable notValidBefore;
    uint256 internal immutable notValidAfter;
    uint256 internal immutable blocksBeforeVoteCloses;
    address internal immutable customRule;

    constructor(
        address _governor,
        uint256 _maxRedelegations,
        uint256 _notValidBefore,
        uint256 _notValidAfter,
        uint256 _blocksBeforeVoteCloses,
        address _customRule
    ) {
        alligator = msg.sender;
        governor = _governor;

        maxRedelegations = _maxRedelegations;
        notValidBefore = _notValidBefore;
        notValidAfter = _notValidAfter;
        blocksBeforeVoteCloses = _blocksBeforeVoteCloses;
        customRule = _customRule;
    }

    fallback() external payable {
        require(msg.sender == alligator);
        address addr = governor;

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := call(gas(), addr, callvalue(), 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    // If funds are received from the governor, send them back to the caller.
    receive() external payable {
        require(msg.sender == governor);
        (bool success,) = payable(tx.origin).call{value: msg.value}("");
        require(success);
    }
}
