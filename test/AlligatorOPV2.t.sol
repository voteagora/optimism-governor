// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./AlligatorOP.t.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AlligatorOPV2} from "src/alligator/AlligatorOP_V2.sol";
import {IAlligatorOPV2} from "src/interfaces/IAlligatorOPV2.sol";

contract AlligatorOPV2Test is AlligatorOPTest {
    function setUp() public virtual override {
        SetupAlligatorOP.setUp();

        alligator = address(new AlligatorOPV2(address(governor), address(op), address(this)));

        proxy1 = _create(address(this), baseRules, baseRulesHash);
        proxy2 = _create(address(Utils.alice), baseRules, baseRulesHash);
        proxy3 = _create(address(Utils.bob), baseRules, baseRulesHash);

        _postSetup();
    }

    function _proxyAddress(address proxyOwner, BaseRules memory, bytes32 rulesHash)
        internal
        view
        override
        returns (address computedAddress)
    {
        return IAlligatorOPV2(alligator).proxyAddress(proxyOwner, rulesHash);
    }

    function _create(address proxyOwner, BaseRules memory rules, bytes32)
        internal
        override
        returns (address computedAddress)
    {
        return IAlligatorOPV2(alligator).create(proxyOwner, rules);
    }

    function _castVote(BaseRules memory, bytes32 rulesHash, address[] memory authority, uint256 propId, uint8 support)
        internal
        virtual
        override
    {
        IAlligatorOPV2(alligator).castVote(rulesHash, authority, propId, support);
    }

    function _castVoteWithReason(
        BaseRules memory,
        bytes32 rulesHash,
        address[] memory authority,
        uint256 propId,
        uint8 support,
        string memory reason
    ) internal virtual override {
        IAlligatorOPV2(alligator).castVoteWithReason(rulesHash, authority, propId, support, reason);
    }

    function _castVoteWithReasonAndParams(
        BaseRules memory,
        bytes32 rulesHash,
        address[] memory authority,
        uint256 propId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal virtual override {
        IAlligatorOPV2(alligator).castVoteWithReasonAndParams(rulesHash, authority, propId, support, reason, params);
    }

    function _castVoteWithReasonAndParamsBatched(
        BaseRules[] memory,
        bytes32[] memory rulesHashes,
        address[][] memory authorities,
        uint256 propId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal virtual override {
        IAlligatorOPV2(alligator).castVoteWithReasonAndParamsBatched(
            rulesHashes, authorities, propId, support, reason, params
        );
    }
}
