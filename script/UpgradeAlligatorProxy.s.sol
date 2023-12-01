// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AlligatorOPV5} from "src/alligator/AlligatorOP_V5.sol";

contract UpgradeAlligatorProxyScript is Script {
    // TODO: Add addresses
    address newAlligatorImpl = address(0);
    AlligatorOPV5 proxy = AlligatorOPV5(payable(address(1)));

    function run() public {
        address deployer = vm.rememberKey(vm.envUint("DEPLOYER_KEY"));

        vm.startBroadcast(deployer);

        proxy.upgradeTo(newAlligatorImpl);

        vm.stopBroadcast();
    }
}
