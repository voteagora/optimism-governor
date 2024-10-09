// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./setup/SetupAlligatorOP.sol";
import {AlligatorOP, IAlligatorOP} from "src/alligator/AlligatorOP.sol";
import {GovernorCountingSimpleUpgradeableV2} from "src/lib/openzeppelin/v2/GovernorCountingSimpleUpgradeableV2.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AlligatorOPMock} from "./mocks/AlligatorOPMock.sol";

contract AlligatorOPTest is SetupAlligatorOP {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 internal constant BALLOT_TYPEHASH_V5 =
        keccak256("Ballot(uint256 proposalId,uint8 support,address[] authority)");
    bytes32 internal constant BALLOT_WITHPARAMS_TYPEHASH =
        keccak256("Ballot(uint256 proposalId,uint8 support,address[] authority,string reason,bytes params)");
    bytes32 internal constant BALLOT_WITHPARAMS_BATCHED_TYPEHASH = keccak256(
        "Ballot(uint256 proposalId,uint8 support,uint256 maxVotingPower,address[][] authorities,string reason,bytes params)"
    );

    function setUp() public virtual override {
        SetupAlligatorOP.setUp();

        proxy1 = _proxyAddress(address(this));
        proxy2 = _proxyAddress(address(alice));
        proxy3 = _proxyAddress(address(bob));

        _postSetup();
    }

    function testDeploy() public virtual {
        assertEq(Ownable(address(alligator)).owner(), address(this));
    }

    function testProxyAddressMatches() public virtual {
        address proxy = _proxyAddress(carol);
        assertEq(_create(carol), proxy);
    }

    function testCastVote() public virtual {
        address[] memory authority = new address[](1);
        authority[0] = address(this);

        standardCastVote(authority);

        address[] memory authority2 = new address[](2);
        authority2[0] = alice;
        authority2[1] = address(this);

        vm.prank(alice);
        AlligatorOPMock(alligator).subdelegate(address(this), subdelegationRules);

        standardCastVote(authority2);
    }

    function testCastVoteWithReason() public virtual {
        address[] memory authority = new address[](1);
        authority[0] = address(this);

        vm.expectEmit();
        emit VoteCast(_proxyAddress(authority[0]), address(this), authority, proposalId, 1);
        AlligatorOPMock(alligator).castVoteWithReason(authority, proposalId, 1, "reason");

        address[] memory authority2 = new address[](2);
        authority2[0] = alice;
        authority2[1] = address(this);

        vm.prank(alice);
        AlligatorOPMock(alligator).subdelegate(address(this), subdelegationRules);

        vm.expectEmit();
        emit VoteCast(_proxyAddress(authority2[0]), address(this), authority2, proposalId, 1);
        AlligatorOPMock(alligator).castVoteWithReason(authority2, proposalId, 1, "reason");
    }

    function testCastVoteWithReasonAndParams() public virtual {
        address[] memory authority = new address[](1);
        authority[0] = address(this);

        vm.expectEmit();
        emit VoteCast(_proxyAddress(authority[0]), address(this), authority, proposalId, 1);
        AlligatorOPMock(alligator).castVoteWithReasonAndParams(authority, proposalId, 1, "reason", "params");

        address[] memory authority2 = new address[](2);
        authority2[0] = alice;
        authority2[1] = address(this);

        vm.prank(alice);
        AlligatorOPMock(alligator).subdelegate(address(this), subdelegationRules);

        vm.expectEmit();
        emit VoteCast(_proxyAddress(authority2[0]), address(this), authority2, proposalId, 1);
        AlligatorOPMock(alligator).castVoteWithReasonAndParams(authority2, proposalId, 1, "reason", "params");
    }

    function testCastVoteWithReasonAndParamsBatched() public virtual {
        (address[][] memory authorities, address[] memory proxies,) = _formatBatchData();

        standardCastVoteWithReasonAndParamsBatched(authorities, proxies, "reason", "params");

        for (uint256 i = 0; i < proxies.length; i++) {
            assertEq(governor.hasVoted(proposalId, proxies[i]), true);
        }
    }

    function testCastVoteBySig() public virtual {
        address[] memory authority = new address[](2);
        authority[0] = alice;
        authority[1] = signer;

        vm.prank(alice);
        AlligatorOPMock(alligator).subdelegate(signer, subdelegationRules);

        standardCastVoteBySig(authority);
    }

    function testCastVoteWithReasonAndParamsBySig() public virtual {
        address[] memory authority = new address[](2);
        authority[0] = alice;
        authority[1] = signer;

        vm.prank(alice);
        AlligatorOPMock(alligator).subdelegate(signer, subdelegationRules);

        standardCastVoteWithReasonAndParamsBySig(authority);
    }

    function subdelegateAssertions(
        IAlligatorOP.SubdelegationRules memory rules1,
        IAlligatorOP.SubdelegationRules memory rules2
    ) internal virtual {
        assertEq(rules1.maxRedelegations, rules2.maxRedelegations);
        assertEq(rules1.notValidBefore, rules2.notValidBefore);
        assertEq(rules1.notValidAfter, rules2.notValidAfter);
        assertEq(rules1.blocksBeforeVoteCloses, rules2.blocksBeforeVoteCloses);
        assertEq(rules1.customRule, rules2.customRule);
        assertEq(uint8(rules1.allowanceType), uint8(rules2.allowanceType));
        assertEq(rules1.allowance, rules2.allowance);
    }

    /*//////////////////////////////////////////////////////////////
                              TEST REVERTS
    //////////////////////////////////////////////////////////////*/

    function testRevert_castVote_ZeroVotesToCast() public virtual {
        address[] memory authority = new address[](2);
        authority[0] = alice;
        authority[1] = address(this);

        vm.prank(alice);
        AlligatorOPMock(alligator).subdelegate(address(this), subdelegationRules);

        standardCastVote(authority);

        vm.expectRevert(ZeroVotesToCast.selector);
        AlligatorOPMock(alligator).castVote(authority, proposalId, 1);
        vm.expectRevert(ZeroVotesToCast.selector);
        AlligatorOPMock(alligator).castVoteWithReason(authority, proposalId, 1, "reason");
        vm.expectRevert(ZeroVotesToCast.selector);
        AlligatorOPMock(alligator).castVoteWithReasonAndParams(authority, proposalId, 1, "reason", "params");
    }

    function testRevert_validate_notDelegated() public {
        address[] memory authority = new address[](2);
        authority[0] = alice;
        authority[1] = address(this);

        vm.expectRevert(abi.encodeWithSelector(NotDelegated.selector, alice, address(this)));
        AlligatorOPMock(alligator).castVote(authority, proposalId, 1);
    }

    function testRevert_validate_senderNotAuthorityLeaf() public {
        address[] memory authority = new address[](3);
        authority[0] = alice;
        authority[1] = bob;
        authority[2] = address(this);

        AlligatorOPMock(alligator).subdelegate(bob, subdelegationRules);
        vm.prank(alice);
        AlligatorOPMock(alligator).subdelegate(bob, subdelegationRules);
        vm.prank(bob);
        AlligatorOPMock(alligator).subdelegate(address(this), subdelegationRules);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NotDelegated.selector, address(this), bob));
        AlligatorOPMock(alligator).castVote(authority, proposalId, 1);
    }

    function testRevert_validate_delegationRevoked() public {
        IAlligatorOP.SubdelegationRules memory subRules = subdelegationRules;
        address[] memory authority = new address[](2);
        authority[0] = alice;
        authority[1] = address(this);

        vm.prank(alice);
        AlligatorOPMock(alligator).subdelegate(address(this), subRules);

        AlligatorOPMock(alligator).castVote(authority, proposalId, 1);

        subRules.allowance = 0;
        vm.prank(alice);
        AlligatorOPMock(alligator).subdelegate(address(this), subRules);

        vm.expectRevert(abi.encodeWithSelector(NotDelegated.selector, alice, address(this)));
        AlligatorOPMock(alligator).castVote(authority, proposalId, 1);
    }

    function testRevert_validate_TooManyRedelegations() public {
        address[] memory authority = new address[](4);
        authority[0] = address(this);
        authority[1] = alice;
        authority[2] = bob;
        authority[3] = carol;

        subdelegationRules.maxRedelegations = 1;

        AlligatorOPMock(alligator).subdelegate(alice, subdelegationRules);
        vm.prank(alice);
        subdelegationRules.maxRedelegations = 255;
        AlligatorOPMock(alligator).subdelegate(bob, subdelegationRules);
        vm.prank(bob);
        AlligatorOPMock(alligator).subdelegate(carol, subdelegationRules);

        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(TooManyRedelegations.selector, address(this), alice));
        AlligatorOPMock(alligator).castVote(authority, proposalId, 1);

        address[] memory authority2 = new address[](3);
        authority2[0] = address(this);
        authority2[1] = alice;
        authority2[2] = bob;

        vm.prank(bob);
        AlligatorOPMock(alligator).castVote(authority2, proposalId, 1);
    }

    function testRevert_validate_NotValidYet() public {
        address[] memory authority = new address[](2);
        authority[0] = address(this);
        authority[1] = alice;

        subdelegationRules.notValidBefore = uint32(block.timestamp + 1e3);

        AlligatorOPMock(alligator).subdelegate(alice, subdelegationRules);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(NotValidYet.selector, address(this), alice, subdelegationRules.notValidBefore)
        );
        AlligatorOPMock(alligator).castVote(authority, proposalId, 1);
    }

    function testRevert_validate_NotValidAnymore() public {
        address[] memory authority = new address[](2);
        authority[0] = address(this);
        authority[1] = alice;

        subdelegationRules.notValidAfter = 90;

        AlligatorOPMock(alligator).subdelegate(alice, subdelegationRules);

        vm.warp(100);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(NotValidAnymore.selector, address(this), alice, subdelegationRules.notValidAfter)
        );
        AlligatorOPMock(alligator).castVote(authority, proposalId, 1);
    }

    function testRevert_validate_TooEarly() public {
        address[] memory authority = new address[](2);
        authority[0] = address(this);
        authority[1] = alice;

        subdelegationRules.blocksBeforeVoteCloses = 99;

        AlligatorOPMock(alligator).subdelegate(alice, subdelegationRules);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(TooEarly.selector, address(this), alice, subdelegationRules.blocksBeforeVoteCloses)
        );
        AlligatorOPMock(alligator).castVote(authority, proposalId, 1);
    }

    function testRevert_togglePause_notOwner() public {
        vm.prank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        AlligatorOP(alligator)._togglePause();
    }

    /*//////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _proxyAddress(address proxyOwner) internal view virtual returns (address computedAddress) {
        return AlligatorOP(alligator).proxyAddress(proxyOwner);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _formatBatchData()
        internal
        returns (
            address[][] memory authorities,
            address[] memory proxies,
            IAlligatorOP.SubdelegationRules[] memory proxyRules
        )
    {
        address[] memory authority1 = new address[](4);
        authority1[0] = address(this);
        authority1[1] = alice;
        authority1[2] = bob;
        authority1[3] = carol;

        address[] memory authority2 = new address[](2);
        authority2[0] = bob;
        authority2[1] = carol;

        authorities = new address[][](2);
        authorities[0] = authority1;
        authorities[1] = authority2;

        AlligatorOPMock(alligator).subdelegate(alice, subdelegationRules);
        vm.prank(alice);
        AlligatorOPMock(alligator).subdelegate(bob, subdelegationRules);
        vm.prank(bob);
        AlligatorOPMock(alligator).subdelegate(carol, subdelegationRules);
        vm.prank(bob);
        AlligatorOPMock(alligator).subdelegate(carol, subdelegationRules);

        proxies = new address[](2);
        proxies[0] = _proxyAddress(address(this));
        proxies[1] = _proxyAddress(bob);

        proxyRules = new IAlligatorOP.SubdelegationRules[](2);
        proxyRules[0] = subdelegationRules;
        proxyRules[1] = subdelegationRules;
    }

    function _formatBatchDataSigner()
        internal
        returns (
            address[][] memory authorities,
            address[] memory proxies,
            IAlligatorOP.SubdelegationRules[] memory proxyRules
        )
    {
        (authorities, proxies, proxyRules) = _formatBatchData();
        authorities[0][3] = signer;
        authorities[1][1] = signer;

        vm.prank(bob);
        AlligatorOPMock(alligator).subdelegate(signer, subdelegationRules);
        vm.prank(bob);
        AlligatorOPMock(alligator).subdelegate(signer, subdelegationRules);
    }

    function _formatBatchDataAlt(uint256 proxiesNumber)
        internal
        returns (
            address[][] memory authorities,
            address[] memory proxies,
            IAlligatorOP.SubdelegationRules[] memory proxyRules
        )
    {
        authorities = new address[][](proxiesNumber);
        proxies = new address[](proxiesNumber);
        proxyRules = new IAlligatorOP.SubdelegationRules[](proxiesNumber);

        for (uint256 i = 0; i < proxiesNumber; i++) {
            // Define an owner and mint OP to it
            address proxyOwner = address(uint160(i + 1));
            vm.prank(op.owner());
            op.mint(proxyOwner, 1e20);

            // Create a proxy for the owner
            address proxyAddress = _create(proxyOwner);

            vm.startPrank(proxyOwner);

            // Delegate the owner's OP to the proxy
            op.delegate(proxyAddress);

            // Subdelegate the proxy to `address(this)`
            AlligatorOPMock(alligator).subdelegate(address(this), subdelegationRules);

            vm.stopPrank();

            // Define authority chain to be used by `address(this)`, ie the delegate
            address[] memory authority = new address[](2);
            authority[0] = proxyOwner;
            authority[1] = address(this);

            // Push values to the returned arrays
            authorities[i] = authority;
            proxies[i] = proxyAddress;
            proxyRules[i] = subdelegationRules;
        }
    }

    function createAuthorityChain(address[1] memory initAuthority)
        internal
        virtual
        returns (address[] memory authority)
    {
        authority = new address[](initAuthority.length);
        for (uint256 i = 0; i < initAuthority.length - 1; i++) {
            authority[i] = initAuthority[i];

            address node = initAuthority[i];
            vm.prank(node);
            AlligatorOPMock(alligator).subdelegate(initAuthority[i + 1], subdelegationRules);
        }
        authority[initAuthority.length - 1] = initAuthority[initAuthority.length - 1];

        return authority;
    }

    function createAuthorityChain(address[2] memory initAuthority)
        internal
        virtual
        returns (address[] memory authority)
    {
        authority = new address[](initAuthority.length);
        for (uint256 i = 0; i < initAuthority.length - 1; i++) {
            authority[i] = initAuthority[i];

            address node = initAuthority[i];
            vm.prank(node);
            AlligatorOPMock(alligator).subdelegate(initAuthority[i + 1], subdelegationRules);
        }
        authority[initAuthority.length - 1] = initAuthority[initAuthority.length - 1];

        return authority;
    }

    function createAuthorityChain(
        address[2] memory initAuthority,
        ReducedSubdelegationRules[1] memory initSubdelegationRules
    ) internal virtual returns (address[] memory authority) {
        authority = new address[](initAuthority.length);
        for (uint256 i = 0; i < initAuthority.length - 1; i++) {
            authority[i] = initAuthority[i];
            ReducedSubdelegationRules memory rules = initSubdelegationRules[i];

            address node = initAuthority[i];
            vm.prank(node);
            AlligatorOPMock(alligator).subdelegate(
                initAuthority[i + 1],
                IAlligatorOP.SubdelegationRules(
                    subdelegationRules.maxRedelegations,
                    subdelegationRules.blocksBeforeVoteCloses,
                    subdelegationRules.notValidBefore,
                    subdelegationRules.notValidAfter,
                    subdelegationRules.customRule,
                    rules.allowanceType,
                    rules.allowance
                )
            );
        }
        authority[initAuthority.length - 1] = initAuthority[initAuthority.length - 1];

        return authority;
    }

    function createAuthorityChain(address[3] memory initAuthority)
        internal
        virtual
        returns (address[] memory authority)
    {
        authority = new address[](initAuthority.length);
        for (uint256 i = 0; i < initAuthority.length - 1; i++) {
            authority[i] = initAuthority[i];

            address node = initAuthority[i];
            vm.prank(node);
            AlligatorOPMock(alligator).subdelegate(initAuthority[i + 1], subdelegationRules);
        }
        authority[initAuthority.length - 1] = initAuthority[initAuthority.length - 1];

        return authority;
    }

    function createAuthorityChain(
        address[3] memory initAuthority,
        ReducedSubdelegationRules[2] memory initSubdelegationRules
    ) internal virtual returns (address[] memory authority) {
        authority = new address[](initAuthority.length);
        for (uint256 i = 0; i < initAuthority.length - 1; i++) {
            authority[i] = initAuthority[i];
            ReducedSubdelegationRules memory rules = initSubdelegationRules[i];

            address node = initAuthority[i];
            vm.prank(node);
            AlligatorOPMock(alligator).subdelegate(
                initAuthority[i + 1],
                IAlligatorOP.SubdelegationRules(
                    subdelegationRules.maxRedelegations,
                    subdelegationRules.blocksBeforeVoteCloses,
                    subdelegationRules.notValidBefore,
                    subdelegationRules.notValidAfter,
                    subdelegationRules.customRule,
                    rules.allowanceType,
                    rules.allowance
                )
            );
        }
        authority[initAuthority.length - 1] = initAuthority[initAuthority.length - 1];

        return authority;
    }

    function createAuthorityChain(address[4] memory initAuthority)
        internal
        virtual
        returns (address[] memory authority)
    {
        authority = new address[](initAuthority.length);
        for (uint256 i = 0; i < initAuthority.length - 1; i++) {
            authority[i] = initAuthority[i];

            address node = initAuthority[i];
            vm.prank(node);
            AlligatorOPMock(alligator).subdelegate(initAuthority[i + 1], subdelegationRules);
        }
        authority[initAuthority.length - 1] = initAuthority[initAuthority.length - 1];

        return authority;
    }

    function createAuthorityChain(
        address[4] memory initAuthority,
        ReducedSubdelegationRules[3] memory initSubdelegationRules
    ) internal virtual returns (address[] memory authority) {
        authority = new address[](initAuthority.length);
        for (uint256 i = 0; i < initAuthority.length - 1; i++) {
            authority[i] = initAuthority[i];
            ReducedSubdelegationRules memory rules = initSubdelegationRules[i];

            address node = initAuthority[i];
            vm.prank(node);
            AlligatorOPMock(alligator).subdelegate(
                initAuthority[i + 1],
                IAlligatorOP.SubdelegationRules(
                    subdelegationRules.maxRedelegations,
                    subdelegationRules.blocksBeforeVoteCloses,
                    subdelegationRules.notValidBefore,
                    subdelegationRules.notValidAfter,
                    subdelegationRules.customRule,
                    rules.allowanceType,
                    rules.allowance
                )
            );
        }
        authority[initAuthority.length - 1] = initAuthority[initAuthority.length - 1];

        return authority;
    }

    function createAuthorityChain(address[5] memory initAuthority)
        internal
        virtual
        returns (address[] memory authority)
    {
        authority = new address[](initAuthority.length);
        for (uint256 i = 0; i < initAuthority.length - 1; i++) {
            authority[i] = initAuthority[i];

            address node = initAuthority[i];
            vm.prank(node);
            AlligatorOPMock(alligator).subdelegate(initAuthority[i + 1], subdelegationRules);
        }
        authority[initAuthority.length - 1] = initAuthority[initAuthority.length - 1];

        return authority;
    }

    function createAuthorityChain(
        address[5] memory initAuthority,
        ReducedSubdelegationRules[4] memory initSubdelegationRules
    ) internal virtual returns (address[] memory authority) {
        authority = new address[](initAuthority.length);
        for (uint256 i = 0; i < initAuthority.length - 1; i++) {
            authority[i] = initAuthority[i];
            ReducedSubdelegationRules memory rules = initSubdelegationRules[i];

            address node = initAuthority[i];
            vm.prank(node);
            AlligatorOPMock(alligator).subdelegate(
                initAuthority[i + 1],
                IAlligatorOP.SubdelegationRules(
                    subdelegationRules.maxRedelegations,
                    subdelegationRules.blocksBeforeVoteCloses,
                    subdelegationRules.notValidBefore,
                    subdelegationRules.notValidAfter,
                    subdelegationRules.customRule,
                    rules.allowanceType,
                    rules.allowance
                )
            );
        }
        authority[initAuthority.length - 1] = initAuthority[initAuthority.length - 1];

        return authority;
    }

    function createAuthorityChain(address[6] memory initAuthority)
        internal
        virtual
        returns (address[] memory authority)
    {
        authority = new address[](initAuthority.length);
        for (uint256 i = 0; i < initAuthority.length - 1; i++) {
            authority[i] = initAuthority[i];

            address node = initAuthority[i];
            vm.prank(node);
            AlligatorOPMock(alligator).subdelegate(initAuthority[i + 1], subdelegationRules);
        }
        authority[initAuthority.length - 1] = initAuthority[initAuthority.length - 1];

        return authority;
    }

    function createAuthorityChain(
        address[6] memory initAuthority,
        ReducedSubdelegationRules[5] memory initSubdelegationRules
    ) internal virtual returns (address[] memory authority) {
        authority = new address[](initAuthority.length);
        for (uint256 i = 0; i < initAuthority.length - 1; i++) {
            authority[i] = initAuthority[i];
            ReducedSubdelegationRules memory rules = initSubdelegationRules[i];

            address node = initAuthority[i];
            vm.prank(node);
            AlligatorOPMock(alligator).subdelegate(
                initAuthority[i + 1],
                IAlligatorOP.SubdelegationRules(
                    subdelegationRules.maxRedelegations,
                    subdelegationRules.blocksBeforeVoteCloses,
                    subdelegationRules.notValidBefore,
                    subdelegationRules.notValidAfter,
                    subdelegationRules.customRule,
                    rules.allowanceType,
                    rules.allowance
                )
            );
        }
        authority[initAuthority.length - 1] = initAuthority[initAuthority.length - 1];

        return authority;
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function testCastVoteTwice() public virtual {
        address[] memory authority = createAuthorityChain([alice, address(this)]);

        standardCastVote(authority);

        (, uint256 forVotes,) = GovernorCountingSimpleUpgradeableV2(governor).proposalVotes(proposalId);
        assertEq(forVotes, 50e18 + op.getVotes(address(this)));

        createAuthorityChain(
            [alice, address(this)], [ReducedSubdelegationRules(IAlligatorOP.AllowanceType.Relative, 75e3 /* 75% */ )]
        );
        standardCastVote(authority);

        (, forVotes,) = GovernorCountingSimpleUpgradeableV2(governor).proposalVotes(proposalId);
        assertEq(forVotes, 75e18 + op.getVotes(address(this)));
    }

    function testCastVoteMaxRedelegations() public virtual {
        uint256 length = 255;
        subdelegationRules.allowanceType = IAlligatorOP.AllowanceType.Absolute;
        address[] memory authority = new address[](length + 1);
        authority[0] = alice;
        for (uint256 i = 0; i < length; i++) {
            address delegator = i == 0 ? authority[0] : address(uint160(i));
            address delegate = address(uint160(i + 1));
            subdelegationRules.allowance = 1e18 - 10 * i;
            vm.prank(delegator);
            AlligatorOPMock(alligator).subdelegate(delegate, subdelegationRules);

            authority[i + 1] = delegate;
        }

        // startMeasuringGas("castVote with max chain length - partial allowances");
        vm.startPrank(address(uint160(length)));
        standardCastVote(authority);
        vm.stopPrank();
        // stopMeasuringGas();
    }

    function testCastVoteTwiceWithTwoChains_Alt() public virtual {
        address[] memory authority1 = createAuthorityChain([alice, voter, carol]);
        address[] memory authority2 = createAuthorityChain([alice, bob, carol]);

        address[][] memory authorities = new address[][](2);
        authorities[1] = authority1;
        authorities[0] = authority2;

        address[] memory proxies = new address[](2);
        proxies[0] = _proxyAddress(alice);
        proxies[1] = _proxyAddress(alice);

        IAlligatorOP.SubdelegationRules[] memory proxyRules = new IAlligatorOP.SubdelegationRules[](2);
        proxyRules[0] = subdelegationRules;
        proxyRules[1] = subdelegationRules;

        standardCastVoteWithReasonAndParamsBatched(authorities, proxies, "reason", "params");

        (, uint256 forVotes,) = GovernorCountingSimpleUpgradeableV2(governor).proposalVotes(proposalId);
        assertEq(forVotes, 50e18);
    }

    function testCastVoteTwiceWithTwoChains() public virtual {
        address[] memory authority1 = createAuthorityChain([alice, carol]);
        address[] memory authority2 = createAuthorityChain([alice, bob, carol]);

        address[][] memory authorities = new address[][](2);
        authorities[1] = authority1;
        authorities[0] = authority2;

        address[] memory proxies = new address[](2);
        proxies[0] = _proxyAddress(alice);
        proxies[1] = _proxyAddress(alice);

        standardCastVoteWithReasonAndParamsBatched(authorities, proxies, "reason", "params");

        (, uint256 forVotes,) = GovernorCountingSimpleUpgradeableV2(governor).proposalVotes(proposalId);
        assertEq(forVotes, 75e18);
    }

    function testCastVoteTwiceWithTwoLongerChains_Relative1() public virtual {
        address[] memory authority1 = createAuthorityChain([alice, erin, dave, carol]);
        address[] memory authority2 = createAuthorityChain([alice, bob, dave, carol]);

        (address[][] memory authorities, address[] memory proxies,,) = createBasicAuthorities([authority1, authority2]);

        vm.prank(carol);

        vm.expectEmit();
        emit VotesCast(proxies, carol, authorities, proposalId, 1);
        AlligatorOPMock(alligator).castVoteWithReasonAndParamsBatched(authorities, proposalId, 1, "reason", "params");

        (, uint256 forVotes,) = GovernorCountingSimpleUpgradeableV2(governor).proposalVotes(proposalId);
        assertEq(forVotes, 250e17);
    }

    function testCastVoteTwiceWithTwoLongerChains_Relative2() public virtual {
        address[] memory authority1 = createAuthorityChain([alice, dave, carol]);
        address[] memory authority2 = createAuthorityChain([alice, bob, dave, carol]);

        (address[][] memory authorities, address[] memory proxies,,) = createBasicAuthorities([authority1, authority2]);

        vm.prank(carol);

        vm.expectEmit();
        emit VotesCast(proxies, carol, authorities, proposalId, 1);
        AlligatorOPMock(alligator).castVoteWithReasonAndParamsBatched(authorities, proposalId, 1, "reason", "params");

        (, uint256 forVotes,) = GovernorCountingSimpleUpgradeableV2(governor).proposalVotes(proposalId);
        assertEq(forVotes, 375e17);
    }

    function testCastVoteTwiceWithTwoLongerChains_Relative3() public virtual {
        address[] memory authority1 = createAuthorityChain([alice, erin, dave, carol]);
        address[] memory authority2 = createAuthorityChain([alice, bob, dave, carol]);

        (address[][] memory authorities, address[] memory proxies,,) = createBasicAuthorities([authority1, authority2]);

        vm.prank(carol);

        vm.expectEmit();
        emit VotesCast(proxies, carol, authorities, proposalId, 1);
        AlligatorOPMock(alligator).castVoteWithReasonAndParamsBatched(authorities, proposalId, 1, "reason", "params");

        subdelegationRules.allowance = 75e3;
        vm.prank(dave);
        AlligatorOPMock(alligator).subdelegate(carol, subdelegationRules);

        vm.prank(carol);

        vm.expectEmit();
        emit VotesCast(proxies, carol, authorities, proposalId, 1);
        AlligatorOPMock(alligator).castVoteWithReasonAndParamsBatched(authorities, proposalId, 1, "reason", "params");

        (, uint256 forVotes,) = GovernorCountingSimpleUpgradeableV2(governor).proposalVotes(proposalId);
        assertEq(forVotes, 375e17);
    }

    function testCastVoteTwiceWithTwoLongerChains_Relative4() public virtual {
        address[] memory authority1 = createAuthorityChain([alice, bob, frank]);
        address[] memory authority2 = createAuthorityChain([alice, bob, dave, carol]);

        (, uint256 initForVotes,) = governor.proposalVotes(proposalId);
        (address proxy, uint256 votesToCast, uint256 initWeightCast, uint256[] memory initWeights) =
            _getInitParams(authority1);
        vm.prank(frank);
        AlligatorOPMock(alligator).castVoteWithReasonAndParams(authority1, proposalId, 1, "reason", "");
        _castVoteAssertions(authority1, proxy, votesToCast, initWeightCast, initForVotes, initWeights, true);

        (, uint256 forVotes,) = GovernorCountingSimpleUpgradeableV2(governor).proposalVotes(proposalId);
        assertEq(forVotes, 250e17);

        (, initForVotes,) = governor.proposalVotes(proposalId);
        (proxy, votesToCast, initWeightCast, initWeights) = _getInitParams(authority2);
        vm.prank(carol);
        AlligatorOPMock(alligator).castVoteWithReasonAndParams(authority2, proposalId, 1, "reason", "");
        _castVoteAssertions(authority2, proxy, votesToCast, initWeightCast, initForVotes, initWeights, true);

        (, forVotes,) = GovernorCountingSimpleUpgradeableV2(governor).proposalVotes(proposalId);
        assertEq(forVotes, 375e17);
    }

    function testCastVoteTwiceWithTwoLongerChains_Relative5() public virtual {
        address[] memory authority1 = createAuthorityChain(
            [alice, bob, frank],
            [
                ReducedSubdelegationRules(IAlligatorOP.AllowanceType.Relative, 5e4),
                ReducedSubdelegationRules(IAlligatorOP.AllowanceType.Relative, 9e4)
            ]
        );
        address[] memory authority2 = createAuthorityChain([alice, bob, dave, carol]);

        (, uint256 initForVotes,) = governor.proposalVotes(proposalId);
        (address proxy, uint256 votesToCast, uint256 initWeightCast, uint256[] memory initWeights) =
            _getInitParams(authority1);
        vm.prank(frank);
        AlligatorOPMock(alligator).castVoteWithReasonAndParams(authority1, proposalId, 1, "reason", "");
        _castVoteAssertions(authority1, proxy, votesToCast, initWeightCast, initForVotes, initWeights, true);

        (, uint256 forVotes,) = GovernorCountingSimpleUpgradeableV2(governor).proposalVotes(proposalId);
        assertEq(forVotes, 450e17);

        (, initForVotes,) = governor.proposalVotes(proposalId);
        (proxy, votesToCast, initWeightCast, initWeights) = _getInitParams(authority2);
        vm.prank(carol);
        AlligatorOPMock(alligator).castVoteWithReasonAndParams(authority2, proposalId, 1, "reason", "");
        _castVoteAssertions(authority2, proxy, votesToCast, initWeightCast, initForVotes, initWeights, true);

        (, forVotes,) = GovernorCountingSimpleUpgradeableV2(governor).proposalVotes(proposalId);
        assertEq(forVotes, 500e17);
    }

    function testCastVoteTwiceWithTwoLongerChains_Absolute1() public virtual {
        address[] memory authority1 = createAuthorityChain(
            [alice, erin, dave, carol],
            [
                ReducedSubdelegationRules(IAlligatorOP.AllowanceType.Absolute, 100),
                ReducedSubdelegationRules(IAlligatorOP.AllowanceType.Absolute, 250),
                ReducedSubdelegationRules(IAlligatorOP.AllowanceType.Absolute, 250)
            ]
        );
        address[] memory authority2 = createAuthorityChain(
            [alice, bob, dave, carol],
            [
                ReducedSubdelegationRules(IAlligatorOP.AllowanceType.Absolute, 200),
                ReducedSubdelegationRules(IAlligatorOP.AllowanceType.Absolute, 250),
                ReducedSubdelegationRules(IAlligatorOP.AllowanceType.Absolute, 250)
            ]
        );

        (address[][] memory authorities, address[] memory proxies,,) = createBasicAuthorities([authority1, authority2]);

        vm.prank(carol);

        vm.expectEmit();
        emit VotesCast(proxies, carol, authorities, proposalId, 1);
        AlligatorOPMock(alligator).castVoteWithReasonAndParamsBatched(authorities, proposalId, 1, "reason", "params");

        (, uint256 forVotes,) = GovernorCountingSimpleUpgradeableV2(governor).proposalVotes(proposalId);
        assertEq(forVotes, 250);
    }

    function testCastVoteTwiceWithTwoLongerChains_Absolute2() public virtual {
        address[] memory authority1 = createAuthorityChain(
            [alice, erin, dave, carol],
            [
                ReducedSubdelegationRules(IAlligatorOP.AllowanceType.Absolute, 100),
                ReducedSubdelegationRules(IAlligatorOP.AllowanceType.Absolute, 500),
                ReducedSubdelegationRules(IAlligatorOP.AllowanceType.Absolute, 500)
            ]
        );

        (address[][] memory authorities, address[] memory proxies,,) = createBasicAuthorities([authority1, authority1]);

        vm.prank(carol);

        vm.expectEmit();
        emit VotesCast(proxies, carol, authorities, proposalId, 1);
        AlligatorOPMock(alligator).castVoteWithReasonAndParamsBatched(authorities, proposalId, 1, "reason", "params");

        (, uint256 forVotes,) = GovernorCountingSimpleUpgradeableV2(governor).proposalVotes(proposalId);
        assertEq(forVotes, 100);
    }

    function testLimitedCastVoteWithReasonAndParamsBatched() public virtual {
        (address[][] memory authorities,,) = _formatBatchData();

        standardLimitedCastVoteWithReasonAndParamsBatched(1e12, authorities, "reason", "params");
    }

    function testLimitedCastVoteWithReasonAndParamsBatchedBySig() public virtual {
        (address[][] memory authorities,,) = _formatBatchDataSigner();

        standardLimitedCastVoteWithReasonAndParamsBatchedBySig(1e12, authorities);
    }

    function testSubdelegate() public virtual {
        AlligatorOPMock(alligator).subdelegate(alice, subdelegationRules);

        (
            uint8 maxRedelegations,
            uint16 blocksBeforeVoteCloses,
            uint32 notValidBefore,
            uint32 notValidAfter,
            address customRule,
            IAlligatorOP.AllowanceType allowanceType,
            uint256 allowance
        ) = AlligatorOPMock(alligator).subdelegations(address(this), alice);

        IAlligatorOP.SubdelegationRules memory subdelegationRulesSet = IAlligatorOP.SubdelegationRules(
            maxRedelegations,
            uint16(notValidBefore),
            uint16(notValidAfter),
            blocksBeforeVoteCloses,
            customRule,
            allowanceType,
            allowance
        );

        subdelegateAssertions(subdelegationRulesSet, subdelegationRules);
    }

    function testSubdelegateBatched() public virtual {
        address[] memory targets = new address[](2);
        targets[0] = address(bob);
        targets[1] = address(alice);

        AlligatorOPMock(alligator).subdelegateBatched(targets, subdelegationRules);

        for (uint256 i = 0; i < targets.length; i++) {
            (
                uint8 maxRedelegations,
                uint16 blocksBeforeVoteCloses,
                uint32 notValidBefore,
                uint32 notValidAfter,
                address customRule,
                IAlligatorOP.AllowanceType allowanceType,
                uint256 allowance
            ) = AlligatorOPMock(alligator).subdelegations(address(this), targets[i]);

            IAlligatorOP.SubdelegationRules memory subdelegationRulesSet = IAlligatorOP.SubdelegationRules(
                maxRedelegations,
                uint16(notValidBefore),
                uint16(notValidAfter),
                blocksBeforeVoteCloses,
                customRule,
                allowanceType,
                allowance
            );

            subdelegateAssertions(subdelegationRulesSet, subdelegationRules);
        }
    }

    function testSubdelegateBatchedAlt() public virtual {
        address[] memory targets = new address[](2);
        targets[0] = address(bob);
        targets[1] = address(alice);

        IAlligatorOP.SubdelegationRules[] memory subRules = new IAlligatorOP.SubdelegationRules[](targets.length);
        for (uint256 i = 0; i < targets.length; i++) {
            subRules[i] = IAlligatorOP.SubdelegationRules(
                uint8(i + 1),
                subdelegationRules.blocksBeforeVoteCloses,
                subdelegationRules.notValidBefore,
                subdelegationRules.notValidAfter,
                subdelegationRules.customRule,
                subdelegationRules.allowanceType,
                subdelegationRules.allowance
            );
        }

        AlligatorOPMock(alligator).subdelegateBatched(targets, subRules);

        for (uint256 i = 0; i < targets.length; i++) {
            (
                uint8 maxRedelegations,
                uint16 blocksBeforeVoteCloses,
                uint32 notValidBefore,
                uint32 notValidAfter,
                address customRule,
                IAlligatorOP.AllowanceType allowanceType,
                uint256 allowance
            ) = AlligatorOPMock(alligator).subdelegations(address(this), targets[i]);

            IAlligatorOP.SubdelegationRules memory subdelegationRulesSet = IAlligatorOP.SubdelegationRules(
                maxRedelegations,
                uint16(notValidBefore),
                uint16(notValidAfter),
                blocksBeforeVoteCloses,
                customRule,
                allowanceType,
                allowance
            );

            assertEq(subdelegationRulesSet.maxRedelegations, subRules[i].maxRedelegations);
            assertEq(subdelegationRulesSet.notValidBefore, subRules[i].notValidBefore);
            assertEq(subdelegationRulesSet.notValidAfter, subRules[i].notValidAfter);
            assertEq(subdelegationRulesSet.blocksBeforeVoteCloses, subRules[i].blocksBeforeVoteCloses);
            assertEq(subdelegationRulesSet.customRule, subRules[i].customRule);
            assertEq(uint8(subdelegationRulesSet.allowanceType), uint8(subRules[i].allowanceType));
            assertEq(subdelegationRulesSet.allowance, subRules[i].allowance);
        }
    }

    function testValidate() public {
        IAlligatorOP.SubdelegationRules memory subRules = subdelegationRules;
        address[] memory authority = new address[](1);
        authority[0] = address(this);

        address proxy = _proxyAddress(authority[0]);
        uint256 proxyTotalVotes = op.getPastVotes(proxy, governor.proposalSnapshot(proposalId));

        (uint256 votesToCast) = AlligatorOPMock(alligator)._validate(
            proxy, authority[authority.length - 1], authority, proposalId, 1, proxyTotalVotes
        );

        assertEq(votesToCast, proxyTotalVotes);

        authority = new address[](2);
        authority[0] = address(alice);
        authority[1] = address(this);

        subRules.allowance = 2e4;
        vm.prank(alice);
        AlligatorOPMock(alligator).subdelegate(address(this), subRules);

        (votesToCast) = AlligatorOPMock(alligator)._validate(
            proxy, authority[authority.length - 1], authority, proposalId, 1, proxyTotalVotes
        );

        assertEq(votesToCast, proxyTotalVotes * subRules.allowance / 1e5);

        subRules.allowance = 1e5;
        vm.prank(alice);
        AlligatorOPMock(alligator).subdelegate(address(this), subRules);

        (votesToCast) = AlligatorOPMock(alligator)._validate(
            proxy, authority[authority.length - 1], authority, proposalId, 1, proxyTotalVotes
        );

        assertEq(votesToCast, proxyTotalVotes * subRules.allowance / 1e5);

        subRules.allowanceType = IAlligatorOP.AllowanceType.Absolute;
        vm.prank(alice);
        AlligatorOPMock(alligator).subdelegate(address(this), subRules);

        (votesToCast) = AlligatorOPMock(alligator)._validate(
            proxy, authority[authority.length - 1], authority, proposalId, 1, proxyTotalVotes
        );

        assertEq(votesToCast, subRules.allowance);
    }

    /*//////////////////////////////////////////////////////////////
                                REVERTS
    //////////////////////////////////////////////////////////////*/

    function testRevert_castVoteBatched_ZeroVotesToCast() public virtual {
        (address[][] memory authorities, address[] memory proxies,) = _formatBatchData();

        standardCastVoteWithReasonAndParamsBatched(authorities, proxies, "reason", "params");

        vm.expectRevert(ZeroVotesToCast.selector);
        vm.prank(carol);
        AlligatorOP(alligator).castVoteWithReasonAndParamsBatched(authorities, proposalId, 1, "reason", "params");

        vm.expectRevert(ZeroVotesToCast.selector);
        vm.prank(carol);
        AlligatorOPMock(alligator).limitedCastVoteWithReasonAndParamsBatched(
            200, authorities, proposalId, 1, "reason", "params"
        );
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function standardCastVote(address[] memory authority) public virtual {
        address voterAddress = authority[authority.length - 1];
        (, uint256 initForVotes,) = governor.proposalVotes(proposalId);
        (address proxy, uint256 votesToCast, uint256 initWeightCast, uint256[] memory initWeights) =
            _getInitParams(authority);

        bool isStandardVote = !governor.hasVoted(proposalId, voterAddress);

        vm.expectEmit();
        emit VoteCastWithParams(
            voterAddress, proposalId, 1, isStandardVote ? votesToCast + op.getVotes(voterAddress) : votesToCast, "", ""
        );
        vm.expectEmit();
        emit VoteCast(_proxyAddress(authority[0]), authority[authority.length - 1], authority, proposalId, 1);
        AlligatorOPMock(alligator).castVote(authority, proposalId, 1);

        _castVoteAssertions(authority, proxy, votesToCast, initWeightCast, initForVotes, initWeights, isStandardVote);
    }

    function standardCastVoteWithReason(address[] memory authority, string memory reason) public virtual {
        address voterAddress = authority[authority.length - 1];
        (, uint256 initForVotes,) = governor.proposalVotes(proposalId);
        (address proxy, uint256 votesToCast, uint256 initWeightCast, uint256[] memory initWeights) =
            _getInitParams(authority);

        bool isStandardVote = !governor.hasVoted(proposalId, voterAddress);

        vm.expectEmit();
        emit VoteCastWithParams(
            voterAddress,
            proposalId,
            1,
            isStandardVote ? votesToCast + op.getVotes(voterAddress) : votesToCast,
            reason,
            ""
        );
        vm.expectEmit();
        emit VoteCast(_proxyAddress(authority[0]), address(this), authority, proposalId, 1);
        AlligatorOPMock(alligator).castVoteWithReason(authority, proposalId, 1, reason);

        _castVoteAssertions(authority, proxy, votesToCast, initWeightCast, initForVotes, initWeights, true);
    }

    function standardCastVoteWithReasonAndParams(address[] memory authority, string memory reason, bytes memory params)
        public
        virtual
    {
        address voterAddress = authority[authority.length - 1];
        (, uint256 initForVotes,) = governor.proposalVotes(proposalId);
        (address proxy, uint256 votesToCast, uint256 initWeightCast, uint256[] memory initWeights) =
            _getInitParams(authority);

        bool isStandardVote = !governor.hasVoted(proposalId, voterAddress);

        vm.expectEmit();
        emit VoteCastWithParams(
            authority[authority.length - 1],
            proposalId,
            1,
            isStandardVote ? votesToCast + op.getVotes(voterAddress) : votesToCast,
            reason,
            params
        );
        vm.expectEmit();
        emit VoteCast(_proxyAddress(authority[0]), address(this), authority, proposalId, 1);
        AlligatorOPMock(alligator).castVoteWithReasonAndParams(authority, proposalId, 1, reason, params);

        _castVoteAssertions(authority, proxy, votesToCast, initWeightCast, initForVotes, initWeights, true);
    }

    mapping(address proxy => uint256) public votesToCast_;

    function standardCastVoteWithReasonAndParamsBatched(
        address[][] memory authorities,
        address[] memory proxies,
        string memory reason,
        bytes memory params
    ) public virtual {
        uint256[] memory votesToCast = new uint256[](authorities.length);
        uint256[] memory initWeightCast = new uint256[](authorities.length);
        uint256[][] memory initWeights = new uint256[][](authorities.length);
        (, uint256 initForVotes,) = governor.proposalVotes(proposalId);
        uint256 totalVotesToCast = op.getVotes(authorities[0][authorities[0].length - 1]);

        for (uint256 i = 0; i < authorities.length; i++) {
            address[] memory authority = authorities[i];
            (, votesToCast[i], initWeightCast[i], initWeights[i]) = _getInitParams(authority);
            totalVotesToCast += votesToCast[i];
        }

        vm.expectEmit();
        emit VoteCastWithParams(
            authorities[0][authorities[0].length - 1], proposalId, 1, totalVotesToCast, reason, params
        );
        vm.prank(carol);

        vm.expectEmit();
        emit VotesCast(proxies, carol, authorities, proposalId, 1);
        AlligatorOPMock(alligator).castVoteWithReasonAndParamsBatched(authorities, proposalId, 1, reason, params);

        _castVoteBatchedAssertions(
            authorities, proxies, votesToCast, totalVotesToCast, initWeightCast, initForVotes, initWeights
        );
    }

    function standardLimitedCastVoteWithReasonAndParamsBatched(
        uint256 maxVotingPower,
        address[][] memory authorities,
        string memory reason,
        bytes memory params
    ) public virtual {
        address[] memory proxies = new address[](authorities.length);
        uint256[] memory votesToCast = new uint256[](authorities.length);
        uint256[] memory initWeightCast = new uint256[](authorities.length);
        uint256[][] memory initWeights = new uint256[][](authorities.length);
        (, uint256 initForVotes,) = governor.proposalVotes(proposalId);
        uint256 totalVotesToCast = op.getVotes(authorities[0][authorities[0].length - 1]);

        for (uint256 i = 0; i < authorities.length; i++) {
            address[] memory authority = authorities[i];
            (proxies[i], votesToCast[i], initWeightCast[i], initWeights[i]) = _getInitParams(authority);
            totalVotesToCast += votesToCast[i];

            if (totalVotesToCast > maxVotingPower) {
                votesToCast_[proxies[i]] -= votesToCast[i];
                votesToCast[i] = maxVotingPower - (totalVotesToCast - votesToCast[i]);
                votesToCast_[proxies[i]] += votesToCast[i];
                totalVotesToCast = maxVotingPower;
                break;
            }
        }

        vm.expectEmit();
        emit VoteCastWithParams(
            authorities[0][authorities[0].length - 1], proposalId, 1, totalVotesToCast, reason, params
        );
        vm.expectEmit();
        emit VotesCast(proxies, carol, authorities, proposalId, 1);

        vm.prank(carol);
        AlligatorOPMock(alligator).limitedCastVoteWithReasonAndParamsBatched(
            maxVotingPower, authorities, proposalId, 1, reason, params
        );

        _castVoteBatchedAssertions(
            authorities, proxies, votesToCast, totalVotesToCast, initWeightCast, initForVotes, initWeights
        );
    }

    function standardCastVoteBySig(address[] memory authority) public virtual {
        bytes32 domainSeparator =
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Alligator"), block.chainid, alligator));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH_V5, proposalId, 1, authority));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(123, keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash)));

        vm.expectEmit();
        emit VoteCast(_proxyAddress(authority[0]), signer, authority, proposalId, 1);
        AlligatorOPMock(alligator).castVoteBySig(authority, proposalId, 1, v, r, s);
    }

    function standardCastVoteWithReasonAndParamsBySig(address[] memory authority) public virtual {
        bytes32 domainSeparator =
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Alligator"), block.chainid, alligator));
        bytes32 structHash = keccak256(
            abi.encode(
                BALLOT_WITHPARAMS_TYPEHASH, proposalId, 1, authority, keccak256(bytes("reason")), keccak256("params")
            )
        );
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(123, keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash)));

        vm.expectEmit();
        emit VoteCast(_proxyAddress(authority[0]), signer, authority, proposalId, 1);
        AlligatorOPMock(alligator).castVoteWithReasonAndParamsBySig(
            authority, proposalId, 1, "reason", "params", v, r, s
        );
    }

    function standardLimitedCastVoteWithReasonAndParamsBatchedBySig(
        uint256 maxVotingPower,
        address[][] memory authorities
    ) public virtual {
        address[] memory proxies = new address[](authorities.length);
        uint256[] memory votesToCast = new uint256[](authorities.length);
        uint256[] memory initWeightCast = new uint256[](authorities.length);
        uint256[][] memory initWeights = new uint256[][](authorities.length);
        (, uint256 initForVotes,) = governor.proposalVotes(proposalId);
        uint256 totalVotesToCast = op.getVotes(authorities[0][authorities[0].length - 1]);

        for (uint256 i = 0; i < authorities.length; i++) {
            address[] memory authority = authorities[i];
            (proxies[i], votesToCast[i], initWeightCast[i], initWeights[i]) = _getInitParams(authority);
            totalVotesToCast += votesToCast[i];

            if (totalVotesToCast > maxVotingPower) {
                votesToCast_[proxies[i]] -= votesToCast[i];
                votesToCast[i] = maxVotingPower - (totalVotesToCast - votesToCast[i]);
                votesToCast_[proxies[i]] += votesToCast[i];
                totalVotesToCast = maxVotingPower;
                break;
            }
        }

        vm.expectEmit();
        emit VoteCastWithParams(
            authorities[0][authorities[0].length - 1], proposalId, 1, totalVotesToCast, "reason", "params"
        );
        vm.expectEmit();
        emit VotesCast(proxies, signer, authorities, proposalId, 1);

        _limitedCastVoteWithReasonAndParamsBatchedBySig(maxVotingPower, authorities, proposalId, 1, "reason", "params");

        _castVoteBatchedAssertions(
            authorities, proxies, votesToCast, totalVotesToCast, initWeightCast, initForVotes, initWeights
        );
    }

    function _getInitParams(address[] memory authority)
        internal
        returns (address proxy, uint256 votesToCast, uint256 initWeightCast, uint256[] memory initWeights)
    {
        proxy = _proxyAddress(authority[0]);
        uint256 proxyTotalVotes = op.getPastVotes(proxy, governor.proposalSnapshot(proposalId));
        (votesToCast) = AlligatorOPMock(alligator)._validate(
            proxy, authority[authority.length - 1], authority, proposalId, 1, proxyTotalVotes
        );
        votesToCast_[proxy] += votesToCast;
        initWeightCast = governor.weightCast(proposalId, proxy);
        initWeights = new uint256[](authority.length);
        for (uint256 i = 1; i < authority.length; ++i) {
            initWeights[i] = AlligatorOPMock(alligator).votesCast(proxy, proposalId, authority[i - 1], authority[i]);
        }
    }

    function _castVoteAssertions(
        address[] memory authority,
        address proxy,
        uint256 votesToCast,
        uint256 initWeightCast,
        uint256 initForVotes,
        uint256[] memory initWeights,
        bool isStandardVote
    ) internal view {
        (, uint256 finalForVotes,) = governor.proposalVotes(proposalId);

        assertTrue(governor.hasVoted(proposalId, proxy));
        assertEq(governor.weightCast(proposalId, proxy), initWeightCast + votesToCast);
        assertEq(
            finalForVotes,
            initForVotes + votesToCast + (isStandardVote ? op.getVotes(authority[authority.length - 1]) : 0)
        );

        if (authority.length > 1) {
            uint256 recordedVotes = AlligatorOPMock(alligator).votesCast(
                proxy, proposalId, authority[authority.length - 2], authority[authority.length - 1]
            );
            assertEq(recordedVotes, initWeights[authority.length - 1] + votesToCast);
        }
    }

    function _castVoteBatchedAssertions(
        address[][] memory authorities,
        address[] memory proxies,
        uint256[] memory votesToCast,
        uint256 totalVotesToCast,
        uint256[] memory initWeightCast,
        uint256 initForVotes,
        uint256[][] memory initWeights
    ) internal view {
        (, uint256 finalForVotes,) = governor.proposalVotes(proposalId);

        assertEq(finalForVotes, initForVotes + totalVotesToCast);

        for (uint256 i = 0; i < authorities.length; i++) {
            address[] memory authority = authorities[i];
            address proxy = proxies[i];

            if (proxy != address(0)) {
                assertTrue(governor.hasVoted(proposalId, proxy));
                assertEq(governor.weightCast(proposalId, proxy), initWeightCast[i] + votesToCast_[proxy]);

                if (authority.length > 1) {
                    uint256 recordedVotes = AlligatorOPMock(alligator).votesCast(
                        proxy, proposalId, authority[authority.length - 2], authority[authority.length - 1]
                    );
                    assertEq(recordedVotes, initWeights[i][authority.length - 1] + votesToCast[i]);
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _proxyAddress(address proxyOwner, bytes32) internal view returns (address computedAddress) {
        return AlligatorOPMock(alligator).proxyAddress(proxyOwner);
    }

    function _create(address proxyOwner) internal view returns (address computedAddress) {
        return _proxyAddress(proxyOwner);
    }

    function _limitedCastVoteWithReasonAndParamsBatchedBySig(
        uint256 maxVotingPower,
        address[][] memory authorities,
        uint256 propId,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal virtual {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            123,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Alligator"), block.chainid, alligator)),
                    keccak256(
                        abi.encode(
                            BALLOT_WITHPARAMS_BATCHED_TYPEHASH,
                            proposalId,
                            1,
                            maxVotingPower,
                            authorities,
                            keccak256(bytes("reason")),
                            keccak256("params")
                        )
                    )
                )
            )
        );

        AlligatorOPMock(alligator).limitedCastVoteWithReasonAndParamsBatchedBySig(
            maxVotingPower, authorities, propId, support, reason, params, v, r, s
        );
    }

    function createBasicAuthorities(address[][1] memory initAuthorities)
        internal
        virtual
        returns (
            address[][] memory authorities,
            address[] memory proxies,
            IAlligatorOP.SubdelegationRules[] memory proxyRules,
            uint256 totalVotesToCast
        )
    {
        authorities = new address[][](initAuthorities.length);
        proxies = new address[](initAuthorities.length);
        proxyRules = new IAlligatorOP.SubdelegationRules[](initAuthorities.length);

        uint256[] memory votesToCast = new uint256[](authorities.length);

        for (uint256 i = 0; i < initAuthorities.length; i++) {
            authorities[i] = initAuthorities[i];
            proxies[i] = _proxyAddress(authorities[i][0]);
            proxyRules[i] = subdelegationRules;

            (, votesToCast[i],,) = _getInitParams(authorities[i]);
            totalVotesToCast += votesToCast[i];
        }
    }

    function createBasicAuthorities(address[][2] memory initAuthorities)
        internal
        virtual
        returns (
            address[][] memory authorities,
            address[] memory proxies,
            IAlligatorOP.SubdelegationRules[] memory proxyRules,
            uint256 totalVotesToCast
        )
    {
        authorities = new address[][](initAuthorities.length);
        proxies = new address[](initAuthorities.length);
        proxyRules = new IAlligatorOP.SubdelegationRules[](initAuthorities.length);

        uint256[] memory votesToCast = new uint256[](authorities.length);

        for (uint256 i = 0; i < initAuthorities.length; i++) {
            authorities[i] = initAuthorities[i];
            proxies[i] = _proxyAddress(authorities[i][0]);
            proxyRules[i] = subdelegationRules;

            (, votesToCast[i],,) = _getInitParams(authorities[i]);
            totalVotesToCast += votesToCast[i];
        }
    }

    function createBasicAuthorities(address[][3] memory initAuthorities)
        internal
        virtual
        returns (
            address[][] memory authorities,
            address[] memory proxies,
            IAlligatorOP.SubdelegationRules[] memory proxyRules,
            uint256 totalVotesToCast
        )
    {
        authorities = new address[][](initAuthorities.length);
        proxies = new address[](initAuthorities.length);
        proxyRules = new IAlligatorOP.SubdelegationRules[](initAuthorities.length);

        uint256[] memory votesToCast = new uint256[](authorities.length);

        for (uint256 i = 0; i < initAuthorities.length; i++) {
            authorities[i] = initAuthorities[i];
            proxies[i] = _proxyAddress(authorities[i][0]);
            proxyRules[i] = subdelegationRules;

            (, votesToCast[i],,) = _getInitParams(authorities[i]);
            totalVotesToCast += votesToCast[i];
        }
    }
}
