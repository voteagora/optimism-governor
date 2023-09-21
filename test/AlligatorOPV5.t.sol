// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./AlligatorOP.t.sol";
import {SubdelegationRules as SubdelegationRulesV3} from "src/structs/RulesV3.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AlligatorOPV5} from "src/alligator/AlligatorOP_V5.sol";
import {IAlligatorOPV5} from "src/interfaces/IAlligatorOPV5.sol";

contract AlligatorOPV5Test is AlligatorOPTest {
    function setUp() public virtual override {
        SetupAlligatorOP.setUp();
        alligatorAlt = address(new AlligatorOPV5());
        bytes memory initData = abi.encodeCall(AlligatorOPV5(alligator).initialize, address(this));
        alligator = address(new ERC1967Proxy(alligatorAlt, initData));
        alligatorAlt = alligator;

        proxy1 = _proxyAddress(address(this), baseRules, baseRulesHash);
        proxy2 = _proxyAddress(address(Utils.alice), baseRules, baseRulesHash);
        proxy3 = _proxyAddress(address(Utils.bob), baseRules, baseRulesHash);

        _postSetup();
    }

    /*//////////////////////////////////////////////////////////////
                               OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function testCreate() public override {}

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _proxyAddress(address proxyOwner, BaseRules memory, bytes32)
        internal
        view
        override
        returns (address computedAddress)
    {
        return IAlligatorOPV5(alligator).proxyAddress(proxyOwner);
    }

    function _create(address proxyOwner, BaseRules memory baseRules_, bytes32 baseRulesHash_)
        internal
        view
        override
        returns (address computedAddress)
    {
        return _proxyAddress(proxyOwner, baseRules_, baseRulesHash_);
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
        IAlligatorOPV5(alligator).subDelegate(to, rules);
    }

    function _castVote(BaseRules memory, bytes32, address[] memory authority, uint256 propId, uint8 support)
        internal
        virtual
        override
    {
        IAlligatorOPV5(alligator).castVote(authority, propId, support);
    }

    function _castVoteWithReason(
        BaseRules memory,
        bytes32,
        address[] memory authority,
        uint256 propId,
        uint8 support,
        string memory reason
    ) internal virtual override {
        IAlligatorOPV5(alligator).castVoteWithReason(authority, propId, support, reason);
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
        IAlligatorOPV5(alligator).castVoteWithReasonAndParams(authority, propId, support, reason, params);
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
        IAlligatorOPV5(alligator).castVoteWithReasonAndParamsBatched(authorities, propId, support, reason, params);
    }
}
