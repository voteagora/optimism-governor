// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./AlligatorOP.t.sol";
import {SubdelegationRules as SubdelegationRulesV3} from "src/structs/RulesV3.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AlligatorOPV3} from "src/alligator/AlligatorOP_V3.sol";
import {IAlligatorOPV3} from "src/interfaces/IAlligatorOPV3.sol";

contract AlligatorOPV3Test is AlligatorOPTest {
    function setUp() public virtual override {
        SetupAlligatorOP.setUp();

        alligator = address(new AlligatorOPV3(address(governor), address(op), address(this)));

        proxy1 = _create(address(this), baseRules, baseRulesHash);
        proxy2 = _create(address(Utils.alice), baseRules, baseRulesHash);
        proxy3 = _create(address(Utils.bob), baseRules, baseRulesHash);

        _postSetup();
    }

    function _proxyAddress(address proxyOwner, BaseRules memory, bytes32)
        internal
        view
        override
        returns (address computedAddress)
    {
        return IAlligatorOPV3(alligator).proxyAddress(proxyOwner);
    }

    function _create(address proxyOwner, BaseRules memory, bytes32)
        internal
        override
        returns (address computedAddress)
    {
        return IAlligatorOPV3(alligator).create(proxyOwner);
    }

    function _subdelegate(address, BaseRules memory, address to, SubdelegationRules memory subDelegateRules)
        internal
        override
    {
        SubdelegationRulesV3 memory rules = SubdelegationRulesV3(
            subDelegateRules.baseRules.maxRedelegations,
            subDelegateRules.baseRules.blocksBeforeVoteCloses,
            subDelegateRules.baseRules.notValidBefore,
            subDelegateRules.baseRules.notValidAfter,
            subDelegateRules.baseRules.customRule,
            subDelegateRules.allowanceType,
            subDelegateRules.allowance
        );
        IAlligatorOPV3(alligator).subDelegate(to, rules);
    }

    function _castVote(BaseRules memory, bytes32, address[] memory authority, uint256 propId, uint8 support)
        internal
        virtual
        override
    {
        IAlligatorOPV3(alligator).castVote(authority, propId, support);
    }

    function _castVoteWithReason(
        BaseRules memory,
        bytes32,
        address[] memory authority,
        uint256 propId,
        uint8 support,
        string memory reason
    ) internal virtual override {
        IAlligatorOPV3(alligator).castVoteWithReason(authority, propId, support, reason);
    }

    function _castVoteWithReasonAndParams(
        BaseRules memory,
        bytes32,
        address[] memory authority,
        uint256 propId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal virtual override {
        IAlligatorOPV3(alligator).castVoteWithReasonAndParams(authority, propId, support, reason, params);
    }

    function _castVoteWithReasonAndParamsBatched(
        BaseRules[] memory,
        bytes32[] memory,
        address[][] memory authorities,
        uint256 propId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal virtual override {
        IAlligatorOPV3(alligator).castVoteWithReasonAndParamsBatched(authorities, propId, support, reason, params);
    }
}
