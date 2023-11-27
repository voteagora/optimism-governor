// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {Helpers} from "./utils/Helpers.sol";
import {SubdelegationRules, AllowanceType} from "src/structs/RulesV3.sol";
import { AlligatorProxy } from "src/alligator/AlligatorProxy.sol";

contract AlligatorGetProxyAddressScript is Helpers {
    function run() public {
      console.logBytes(type(AlligatorProxy).creationCode);

      address endpoint = address(
          uint160(
              uint256(
                  keccak256(
                      abi.encodePacked(
                          bytes1(0xff),
                          address(0xD89eb37D3e643aab97258C62BcF704CD00761af6),
                          bytes32(uint256(uint160(address(0x924A0468961f09aB3c3A457382C9D06f48cff6aA)))), // salt
                          keccak256(abi.encodePacked(type(AlligatorProxy).creationCode, abi.encode(address(0x6E17cdef2F7c1598AD9DfA9A8acCF84B1303f43f))))
                      )
                  )
              )
          )
      );

      console.logAddress(endpoint);
    }
}
