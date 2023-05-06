// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UpgradeScripts} from "upgrade-scripts/UpgradeScripts.sol";
import {OptimismGovernorV2} from "../src/OptimismGovernorV2.sol";
import {OptimismGovernorV5} from "../src/OptimismGovernorV5.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {OptimismGovernorV4Mock} from "./mocks/OptimismGovernorV4Mock.sol";
import {OptimismGovernorV5Mock} from "./mocks/OptimismGovernorV5Mock.sol";

contract OptimismGovernorV5UpgradeTest is Test, UpgradeScripts {
    address op = 0x4200000000000000000000000000000000000042;
    address admin = makeAddr("admin");
    address manager = makeAddr("manager");

    OptimismGovernorV5 internal governor;

    function setUpUpgradeScripts() internal override {
        UPGRADE_SCRIPTS_BYPASS = true;
        UPGRADE_SCRIPTS_BYPASS_SAFETY = true; // disable to run safety checks
    }

    function setUp() public {
        OptimismGovernorV5 implementation = new OptimismGovernorV5();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            admin,
            abi.encodeCall(OptimismGovernorV2.initialize, (IVotesUpgradeable(op), manager))
        );
        governor = OptimismGovernorV5(payable(address(proxy)));
    }

    function testUpgrade() public {
        address implementationV4 = setUpContract("OptimismGovernorV4Mock");
        address implementationV5 = setUpContract("OptimismGovernorV5Mock");
        upgradeSafetyChecks("OptimismGovernorV5Mock", implementationV4, implementationV5);
    }
}
