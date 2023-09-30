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
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function testCreate() public override {}

    function testLimitedCastVoteWithReasonAndParamsBatched() public virtual {
        (address[][] memory authorities,, BaseRules[] memory proxyRules, bytes32[] memory proxyRulesHashes) =
            _formatBatchData();

        standardLimitedCastVoteWithReasonAndParamsBatched(
            1e12, authorities, proxyRules, proxyRulesHashes, "reason", "params"
        );
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function standardCastVote(address[] memory authority) public virtual override {
        (, uint256 initForVotes,) = governor.proposalVotes(proposalId);
        (address proxy, uint256 votesToCast, uint256 k, uint256 initWeightCast, uint256[] memory initWeights) =
            _getInitParams(authority);

        vm.expectEmit();
        emit VoteCastWithParams(authority[authority.length - 1], proposalId, 1, votesToCast, "", "");
        super.standardCastVote(authority);

        _castVoteAssertions(authority, proxy, votesToCast, k, initWeightCast, initForVotes, initWeights);
    }

    function standardCastVoteWithReason(address[] memory authority, string memory reason) public virtual override {
        (, uint256 initForVotes,) = governor.proposalVotes(proposalId);
        (address proxy, uint256 votesToCast, uint256 k, uint256 initWeightCast, uint256[] memory initWeights) =
            _getInitParams(authority);

        vm.expectEmit();
        emit VoteCastWithParams(authority[authority.length - 1], proposalId, 1, votesToCast, reason, "");
        super.standardCastVoteWithReason(authority, reason);

        _castVoteAssertions(authority, proxy, votesToCast, k, initWeightCast, initForVotes, initWeights);
    }

    function standardCastVoteWithReasonAndParams(address[] memory authority, string memory reason, bytes memory params)
        public
        virtual
        override
    {
        (, uint256 initForVotes,) = governor.proposalVotes(proposalId);
        (address proxy, uint256 votesToCast, uint256 k, uint256 initWeightCast, uint256[] memory initWeights) =
            _getInitParams(authority);

        vm.expectEmit();
        emit VoteCastWithParams(authority[authority.length - 1], proposalId, 1, votesToCast, reason, params);
        super.standardCastVoteWithReasonAndParams(authority, reason, params);

        _castVoteAssertions(authority, proxy, votesToCast, k, initWeightCast, initForVotes, initWeights);
    }

    mapping(address proxy => uint256) public votesToCast_;

    function standardCastVoteWithReasonAndParamsBatched(
        address[][] memory authorities,
        address[] memory proxies,
        BaseRules[] memory proxyRules,
        bytes32[] memory proxyRulesHashes,
        string memory reason,
        bytes memory params
    ) public virtual override {
        uint256[] memory votesToCast = new uint256[](authorities.length);
        uint256[] memory k = new uint256[](authorities.length);
        uint256[] memory initWeightCast = new uint256[](authorities.length);
        uint256[][] memory initWeights = new uint256[][](authorities.length);
        (, uint256 initForVotes,) = governor.proposalVotes(proposalId);
        uint256 totalVotesToCast;

        for (uint256 i = 0; i < authorities.length; i++) {
            address[] memory authority = authorities[i];
            (, votesToCast[i], k[i], initWeightCast[i], initWeights[i]) = _getInitParams(authority);
            totalVotesToCast += votesToCast[i];
        }

        vm.expectEmit();
        emit VoteCastWithParams(
            authorities[0][authorities[0].length - 1], proposalId, 1, totalVotesToCast, reason, params
        );
        super.standardCastVoteWithReasonAndParamsBatched(
            authorities, proxies, proxyRules, proxyRulesHashes, reason, params
        );

        _castVoteBatchedAssertions(
            authorities, proxies, votesToCast, totalVotesToCast, k, initWeightCast, initForVotes, initWeights
        );
    }

    function standardLimitedCastVoteWithReasonAndParamsBatched(
        uint256 maxVotes,
        address[][] memory authorities,
        BaseRules[] memory proxyRules,
        bytes32[] memory proxyRulesHashes,
        string memory reason,
        bytes memory params
    ) public virtual {
        address[] memory proxies = new address[](authorities.length);
        uint256[] memory votesToCast = new uint256[](authorities.length);
        uint256[] memory k = new uint256[](authorities.length);
        uint256[] memory initWeightCast = new uint256[](authorities.length);
        uint256[][] memory initWeights = new uint256[][](authorities.length);
        (, uint256 initForVotes,) = governor.proposalVotes(proposalId);
        uint256 totalVotesToCast;

        for (uint256 i = 0; i < authorities.length; i++) {
            address[] memory authority = authorities[i];
            (proxies[i], votesToCast[i], k[i], initWeightCast[i], initWeights[i]) = _getInitParams(authority);
            totalVotesToCast += votesToCast[i];

            if (totalVotesToCast > maxVotes) {
                votesToCast_[proxies[i]] -= votesToCast[i];
                votesToCast[i] = maxVotes - (totalVotesToCast - votesToCast[i]);
                votesToCast_[proxies[i]] += votesToCast[i];
                totalVotesToCast = maxVotes;
                break;
            }
        }

        vm.expectEmit();
        emit VoteCastWithParams(
            authorities[0][authorities[0].length - 1], proposalId, 1, totalVotesToCast, reason, params
        );
        vm.expectEmit();
        emit VotesCast(proxies, Utils.carol, authorities, proposalId, 1);

        vm.prank(Utils.carol);
        _limitedCastVoteWithReasonAndParamsBatched(
            maxVotes, proxyRules, proxyRulesHashes, authorities, proposalId, 1, reason, params
        );

        _castVoteBatchedAssertions(
            authorities, proxies, votesToCast, totalVotesToCast, k, initWeightCast, initForVotes, initWeights
        );
    }

    function _getInitParams(address[] memory authority)
        internal
        returns (address proxy, uint256 votesToCast, uint256 k, uint256 initWeightCast, uint256[] memory initWeights)
    {
        proxy = _proxyAddress(authority[0], baseRules, baseRulesHash);
        uint256 proxyTotalVotes = op.getPastVotes(proxy, governor.proposalSnapshot(proposalId));
        (votesToCast, k) = IAlligatorOPV5(alligator).validate(
            proxy, authority[authority.length - 1], authority, proposalId, 1, proxyTotalVotes
        );
        votesToCast_[proxy] += votesToCast;
        initWeightCast = governor.weightCast(proposalId, proxy);
        initWeights = new uint256[](authority.length);
        for (uint256 i; i < authority.length; ++i) {
            initWeights[i] = IAlligatorOPV5(alligator).votesCast(proxy, proposalId, authority[i]);
        }
    }

    function _castVoteAssertions(
        address[] memory authority,
        address proxy,
        uint256 votesToCast,
        uint256 k,
        uint256 initWeightCast,
        uint256 initForVotes,
        uint256[] memory initWeights
    ) internal {
        (, uint256 finalForVotes,) = governor.proposalVotes(proposalId);

        assertTrue(governor.hasVoted(proposalId, proxy));
        assertEq(governor.weightCast(proposalId, proxy), initWeightCast + votesToCast);
        assertEq(finalForVotes, initForVotes + votesToCast);

        for (uint256 i; i < authority.length; ++i) {
            uint256 recordedVotes = IAlligatorOPV5(alligator).votesCast(proxy, proposalId, authority[i]);
            assertEq(recordedVotes, (k == 0 || i < k) ? initWeights[i] : initWeights[i] + votesToCast);
        }
    }

    function _castVoteBatchedAssertions(
        address[][] memory authorities,
        address[] memory proxies,
        uint256[] memory votesToCast,
        uint256 totalVotesToCast,
        uint256[] memory k,
        uint256[] memory initWeightCast,
        uint256 initForVotes,
        uint256[][] memory initWeights
    ) internal {
        (, uint256 finalForVotes,) = governor.proposalVotes(proposalId);

        assertEq(finalForVotes, initForVotes + totalVotesToCast);

        for (uint256 i = 0; i < authorities.length; i++) {
            address[] memory authority = authorities[i];
            address proxy = proxies[i];

            if (proxy != address(0)) {
                assertTrue(governor.hasVoted(proposalId, proxy));
                assertEq(governor.weightCast(proposalId, proxy), initWeightCast[i] + votesToCast_[proxy]);

                for (uint256 l; l < authority.length; ++l) {
                    uint256 recordedVotes = IAlligatorOPV5(alligator).votesCast(proxy, proposalId, authority[l]);
                    assertEq(
                        recordedVotes, (k[i] == 0 || l < k[i]) ? initWeights[i][l] : initWeights[i][l] + votesToCast[i]
                    );
                }
            }
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

    function _limitedCastVoteWithReasonAndParamsBatched(
        uint256 maxVotes,
        BaseRules[] memory,
        bytes32[] memory,
        address[][] memory authorities,
        uint256 propId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal virtual {
        IAlligatorOPV5(alligator).limitedCastVoteWithReasonAndParamsBatched(
            maxVotes, authorities, propId, support, reason, params
        );
    }
}
