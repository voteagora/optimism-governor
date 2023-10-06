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

        alligatorAlt = address(new AlligatorOPV3(address(governor), address(op), address(this)));
        vm.etch(alligator, alligatorAlt.code);

        proxy1 = _create(address(this), baseRules, baseRulesHash);
        proxy2 = _create(address(Utils.alice), baseRules, baseRulesHash);
        proxy3 = _create(address(Utils.bob), baseRules, baseRulesHash);

        _postSetup();
    }

    /*//////////////////////////////////////////////////////////////
                               OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function testSubdelegate() public virtual override {
        _subdelegate(address(this), baseRules, Utils.alice, subdelegationRules);

        (
            uint8 maxRedelegations,
            uint16 blocksBeforeVoteCloses,
            uint32 notValidBefore,
            uint32 notValidAfter,
            address customRule,
            AllowanceType allowanceType,
            uint256 allowance
        ) = AlligatorOPV3(alligator).subdelegations(address(this), Utils.alice);

        BaseRules memory baseRulesSet =
            BaseRules(maxRedelegations, notValidBefore, notValidAfter, blocksBeforeVoteCloses, customRule);

        subdelegateAssertions(baseRulesSet, allowanceType, allowance, subdelegationRules);
    }

    function testSubdelegateBatched() public virtual override {
        address[] memory targets = new address[](2);
        targets[0] = address(Utils.bob);
        targets[1] = address(Utils.alice);

        _subdelegateBatched(address(this), baseRules, targets, subdelegationRules);

        for (uint256 i = 0; i < targets.length; i++) {
            (
                uint8 maxRedelegations,
                uint16 blocksBeforeVoteCloses,
                uint32 notValidBefore,
                uint32 notValidAfter,
                address customRule,
                AllowanceType allowanceType,
                uint256 allowance
            ) = AlligatorOPV3(alligator).subdelegations(address(this), targets[i]);

            BaseRules memory baseRulesSet =
                BaseRules(maxRedelegations, notValidBefore, notValidAfter, blocksBeforeVoteCloses, customRule);

            subdelegateAssertions(baseRulesSet, allowanceType, allowance, subdelegationRules);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

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

    function _subdelegate(address, BaseRules memory, address to, SubdelegationRules memory subdelegateRules)
        internal
        override
    {
        SubdelegationRulesV3 memory rules = SubdelegationRulesV3(
            subdelegateRules.baseRules.maxRedelegations,
            subdelegateRules.baseRules.blocksBeforeVoteCloses,
            subdelegateRules.baseRules.notValidBefore,
            subdelegateRules.baseRules.notValidAfter,
            subdelegateRules.baseRules.customRule,
            subdelegateRules.allowanceType,
            subdelegateRules.allowance
        );
        IAlligatorOPV3(alligator).subdelegate(to, rules);
    }

    function _subdelegateBatched(
        address,
        BaseRules memory,
        address[] memory targets,
        SubdelegationRules memory subdelegateRules
    ) internal virtual override {
        SubdelegationRulesV3 memory rules = SubdelegationRulesV3(
            subdelegateRules.baseRules.maxRedelegations,
            subdelegateRules.baseRules.blocksBeforeVoteCloses,
            subdelegateRules.baseRules.notValidBefore,
            subdelegateRules.baseRules.notValidAfter,
            subdelegateRules.baseRules.customRule,
            subdelegateRules.allowanceType,
            subdelegateRules.allowance
        );
        IAlligatorOPV3(alligator).subdelegateBatched(targets, rules);
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

    function _castVoteBySig(
        BaseRules memory,
        bytes32,
        address[] memory authority,
        uint256 propId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal virtual override {
        IAlligatorOPV3(alligator).castVoteBySig(authority, propId, support, v, r, s);
    }

    function _castVoteWithReasonAndParamsBySig(
        BaseRules memory,
        bytes32,
        address[] memory authority,
        uint256 propId,
        uint8 support,
        string memory reason,
        bytes memory params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal virtual override {
        IAlligatorOPV3(alligator).castVoteWithReasonAndParamsBySig(authority, propId, support, reason, params, v, r, s);
    }
}
