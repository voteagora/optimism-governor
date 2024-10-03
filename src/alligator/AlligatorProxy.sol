// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IAlligatorOP} from "../interfaces/IAlligatorOP.sol";

contract AlligatorProxy {
    address internal immutable alligator;
    address internal immutable governor;

    constructor(address _governor) {
        alligator = msg.sender;
        governor = _governor;
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
