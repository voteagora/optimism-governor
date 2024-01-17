// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AlligatorOPV5} from "src/alligator/AlligatorOP_V5.sol";

contract UpgradeAlligatorProxyScript is Script {
    address newAlligatorImpl = 0x47f22fFb5Af39abbBfF74D869ec63573dAcbF481;
    AlligatorOPV5 proxy = AlligatorOPV5(payable(0x7f08F3095530B67CdF8466B7a923607944136Df0));

    function run() public {
        address deployer = vm.rememberKey(vm.envUint("DEPLOYER_KEY"));

        vm.startBroadcast(deployer);

        proxy.upgradeTo(newAlligatorImpl);

        vm.stopBroadcast();
    }
}
