// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TokenMock} from "test/mocks/TokenMock.sol";
import {
    ApprovalVotingModule,
    ProposalOption,
    ProposalSettings,
    PassingCriteria,
    Proposal
} from "src/modules/ApprovalVotingModule.sol";
import {VotingModule} from "src/modules/VotingModule.sol";
import {ApprovalVotingModuleMock} from "test/mocks/ApprovalVotingModuleMock.sol";

enum ProposalState {
    Pending,
    Active,
    Canceled,
    Defeated,
    Succeeded,
    Queued,
    Expired,
    Executed
}

enum VoteType {
    Against,
    For,
    Abstain
}

contract ApprovalVotingModuleTest is Test {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address internal token = address(new TokenMock(address(this)));
    string internal description = "a nice description";
    bytes32 internal descriptionHash = keccak256(bytes("a nice description"));
    address internal governor;
    address internal voter = makeAddr("voter");
    address internal altVoter = makeAddr("altVoter");
    address receiver1 = makeAddr("receiver1");
    address receiver2 = makeAddr("receiver2");

    ApprovalVotingModuleMock private module;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        governor = address(new GovernorMock());
        module = new ApprovalVotingModuleMock(governor);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function testPropose() public {
        (bytes memory proposalData, ProposalOption[] memory options, ProposalSettings memory settings) =
            _formatProposalData();

        vm.prank(governor);
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);
        module.propose(proposalId, proposalData, descriptionHash);

        Proposal memory proposal = module._proposals(proposalId);

        assertEq(proposal.governor, governor);
        assertEq(proposal.optionVotes[0], 0);
        assertEq(proposal.optionVotes[1], 0);
        assertEq(proposal.optionVotes[2], 0);
        assertEq(proposal.settings.maxApprovals, settings.maxApprovals);
        assertEq(proposal.settings.criteria, settings.criteria);
        assertEq(proposal.settings.budgetToken, settings.budgetToken);
        assertEq(proposal.settings.criteriaValue, settings.criteriaValue);
        assertEq(proposal.settings.budgetAmount, settings.budgetAmount);
        assertEq(proposal.options[0].targets[0], options[0].targets[0]);
        assertEq(proposal.options[0].values[0], options[0].values[0]);
        assertEq(proposal.options[0].calldatas[0], options[0].calldatas[0]);
        assertEq(proposal.options[0].description, options[0].description);
        assertEq(proposal.options[1].targets[0], options[1].targets[0]);
        assertEq(proposal.options[1].values[0], options[1].values[0]);
        assertEq(proposal.options[1].calldatas[0], options[1].calldatas[0]);
        assertEq(proposal.options[1].targets[1], options[1].targets[1]);
        assertEq(proposal.options[1].values[1], options[1].values[1]);
        assertEq(proposal.options[1].calldatas[1], options[1].calldatas[1]);
        assertEq(proposal.options[1].description, options[1].description);
    }

    function testCountVote_voteForSingle() public {
        (bytes memory proposalData,,) = _formatProposalData();
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);
        uint256 weight = 100;

        vm.startPrank(governor);
        module.propose(proposalId, proposalData, descriptionHash);

        uint256[] memory votes = new uint256[](1);
        votes[0] = 0;
        bytes memory params = abi.encode(votes);

        assertEq(module.getAccountTotalVotes(proposalId, voter), 0);

        module._countVote(proposalId, voter, uint8(VoteType.For), weight, params);

        Proposal memory proposal = module._proposals(proposalId);

        assertEq(module.getAccountTotalVotes(proposalId, voter), votes.length);
        assertEq(proposal.optionVotes[0], weight);
        assertEq(proposal.optionVotes[1], 0);
        assertEq(proposal.optionVotes[2], 0);
    }

    function testCountVote_voteForMultiple() public {
        (bytes memory proposalData,,) = _formatProposalData();
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);
        uint256 weight = 100;

        vm.startPrank(governor);
        module.propose(proposalId, proposalData, descriptionHash);

        uint256[] memory votes = new uint256[](2);
        votes[0] = 0;
        votes[1] = 1;
        bytes memory params = abi.encode(votes);

        assertEq(module.getAccountTotalVotes(proposalId, voter), 0);

        module._countVote(proposalId, voter, uint8(VoteType.For), weight, params);

        Proposal memory proposal = module._proposals(proposalId);

        assertEq(module.getAccountTotalVotes(proposalId, voter), votes.length);
        assertEq(proposal.optionVotes[0], weight);
        assertEq(proposal.optionVotes[1], weight);
        assertEq(proposal.optionVotes[2], 0);
    }

    function testCountVote_voteAgainst() public {
        (bytes memory proposalData,,) = _formatProposalData();
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);
        uint256 weight = 100;

        vm.startPrank(governor);
        module.propose(proposalId, proposalData, descriptionHash);

        uint256[] memory votes = new uint256[](2);
        votes[0] = 0;
        votes[1] = 1;
        bytes memory params = abi.encode(votes);

        assertEq(module.getAccountTotalVotes(proposalId, voter), 0);

        module._countVote(proposalId, voter, uint8(VoteType.Against), weight, params);

        Proposal memory proposal = module._proposals(proposalId);

        assertEq(module.getAccountTotalVotes(proposalId, voter), 0);
        assertEq(proposal.optionVotes[0], 0);
        assertEq(proposal.optionVotes[1], 0);
        assertEq(proposal.optionVotes[2], 0);
    }

    function testCountVote_voteAbstain() public {
        (bytes memory proposalData,,) = _formatProposalData();
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);
        uint256 weight = 100;

        vm.startPrank(governor);
        module.propose(proposalId, proposalData, descriptionHash);

        uint256[] memory votes = new uint256[](2);
        votes[0] = 0;
        votes[1] = 1;
        bytes memory params = abi.encode(votes);

        assertEq(module.getAccountTotalVotes(proposalId, voter), 0);

        module._countVote(proposalId, voter, uint8(VoteType.Abstain), weight, params);

        Proposal memory proposal = module._proposals(proposalId);

        assertEq(module.getAccountTotalVotes(proposalId, voter), 0);
        assertEq(proposal.optionVotes[0], 0);
        assertEq(proposal.optionVotes[1], 0);
        assertEq(proposal.optionVotes[2], 0);
    }

    function testVoteSucceeded() public {
        (bytes memory proposalData,,) = _formatProposalData();
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);
        uint256 weight = 100;

        vm.startPrank(governor);
        module.propose(proposalId, proposalData, descriptionHash);

        uint256[] memory votes = new uint256[](1);
        bytes memory params = abi.encode(votes);

        module._countVote(proposalId, voter, uint8(VoteType.For), weight, params);

        assertTrue(module._voteSucceeded(proposalId));
    }

    function testSortOptions() public view {
        (, ProposalOption[] memory options,) = _formatProposalData();

        uint128[] memory optionVotes = new uint128[](3);
        optionVotes[0] = 0;
        optionVotes[1] = 10;
        optionVotes[2] = 2;

        (uint128[] memory sortedOptionVotes, ProposalOption[] memory sortedOptions) =
            module.sortOptions(optionVotes, options);

        assertEq(sortedOptionVotes[0], optionVotes[1]);
        assertEq(sortedOptions[0].targets[0], options[1].targets[0]);
        assertEq(sortedOptionVotes[1], optionVotes[2]);
        assertEq(sortedOptions[1].targets[0], options[2].targets[0]);
        assertEq(sortedOptionVotes[2], optionVotes[0]);
        assertEq(sortedOptions[2].targets[0], options[0].targets[0]);
    }

    function testCountOptions_criteriaTopChoices(uint128[3] memory _optionVotes) public view {
        (, ProposalOption[] memory options, ProposalSettings memory settings) = _formatProposalData();

        uint128[] memory optionVotes = new uint128[](3);
        optionVotes[0] = _optionVotes[0];
        optionVotes[1] = _optionVotes[1];
        optionVotes[2] = _optionVotes[2];

        (uint128[] memory sortedOptionVotes, ProposalOption[] memory sortedOptions) =
            module.sortOptions(optionVotes, options);

        // count proposals with more than zero votes
        uint256 succesfulVotes = 0;
        for (uint256 i = 0; i < sortedOptionVotes.length; i++) {
            if (sortedOptionVotes[i] > 0) {
                succesfulVotes++;
            } else {
                break;
            }
        }

        (uint256 executeParamsLength, uint256 succeededOptionsLength) =
            module.countOptions(sortedOptions, sortedOptionVotes, settings);

        assertEq(
            succeededOptionsLength, settings.criteriaValue < succesfulVotes ? settings.criteriaValue : succesfulVotes
        );
        assertLe(
            executeParamsLength,
            sortedOptions[0].targets.length + sortedOptions[1].targets.length + sortedOptions[2].targets.length
        );
    }

    function testCountOptions_criteriaThreshold() public view {
        (, ProposalOption[] memory options, ProposalSettings memory settings) = _formatProposalData();
        settings.criteria = uint8(PassingCriteria.Threshold);

        uint128[] memory optionVotes = new uint128[](3);
        optionVotes[0] = 0;
        optionVotes[1] = 10;
        optionVotes[2] = 2;

        (uint128[] memory sortedOptionVotes, ProposalOption[] memory sortedOptions) =
            module.sortOptions(optionVotes, options);
        (uint256 executeParamsLength, uint256 succeededOptionsLength) =
            module.countOptions(sortedOptions, sortedOptionVotes, settings);

        assertEq(succeededOptionsLength, 2);
        assertEq(executeParamsLength, sortedOptions[0].targets.length + sortedOptions[1].targets.length);

        settings.criteriaValue = 3;

        (executeParamsLength, succeededOptionsLength) = module.countOptions(sortedOptions, sortedOptionVotes, settings);

        assertEq(succeededOptionsLength, 1);
        assertEq(executeParamsLength, sortedOptions[0].targets.length);
    }

    function testFormatExecuteParams() public {
        (bytes memory proposalData, ProposalOption[] memory options,) = _formatProposalData();
        uint256 weight = 100;

        vm.startPrank(governor);
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);
        module.propose(proposalId, proposalData, descriptionHash);

        uint256[] memory votes = new uint256[](2);
        votes[0] = 1;
        votes[1] = 2;
        bytes memory params = abi.encode(votes);

        module._countVote(proposalId, voter, uint8(VoteType.For), weight, params);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            module._formatExecuteParams(proposalId, proposalData);
        vm.stopPrank();

        uint256 _totalValue = options[1].values[0] + options[1].values[1] + options[2].values[0];

        assertEq(targets.length, options[1].targets.length + options[2].targets.length + 1);
        assertEq(targets.length, values.length);
        assertEq(targets.length, calldatas.length);
        assertEq(targets[0], options[1].targets[0]);
        assertEq(values[0], options[1].values[0]);
        assertEq(calldatas[0], options[1].calldatas[0]);
        assertEq(targets[1], options[1].targets[1]);
        assertEq(values[1], options[1].values[1]);
        assertEq(calldatas[1], options[1].calldatas[1]);
        assertEq(targets[2], options[2].targets[0]);
        assertEq(values[2], options[2].values[0]);
        assertEq(calldatas[2], options[2].calldatas[0]);
        assertEq(targets[3], address(module));
        assertEq(values[3], 0);
        assertEq(
            calldatas[3], abi.encodeCall(ApprovalVotingModule._afterExecute, (proposalId, proposalData, _totalValue))
        );
    }

    function testFormatExecuteParams_ethBudgetExceeded() public {
        address[] memory targets1 = new address[](1);
        uint256[] memory values1 = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets1[0] = receiver1;
        values1[0] = 0.1 ether;

        address[] memory targets2 = new address[](1);
        uint256[] memory values2 = new uint256[](1);
        targets2[0] = receiver1;
        values2[0] = 0;

        ProposalOption[] memory options = new ProposalOption[](2);
        options[0] = ProposalOption(0, targets1, values1, calldatas, "option 1");
        options[1] = ProposalOption(0, targets2, values2, calldatas, "option 2");

        ProposalSettings memory settings = ProposalSettings({
            maxApprovals: 2,
            criteria: uint8(PassingCriteria.TopChoices),
            criteriaValue: 2,
            budgetToken: address(0),
            budgetAmount: 0
        });

        bytes memory proposalData = abi.encode(options, settings);
        uint256 weight = 100;

        vm.startPrank(governor);
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);
        module.propose(proposalId, proposalData, descriptionHash);

        uint256[] memory votes = new uint256[](1);
        votes[0] = 0;
        votes[0] = 1;
        bytes memory params = abi.encode(votes);

        module._countVote(proposalId, voter, uint8(VoteType.For), weight, params);

        (address[] memory targets, uint256[] memory values,) = module._formatExecuteParams(proposalId, proposalData);
        vm.stopPrank();

        assertEq(targets.length, options.length);
        assertEq(targets.length, values.length);
        assertEq(targets[0], options[1].targets[0]);
        assertEq(values[0], options[1].values[0]);
        assertEq(targets[1], address(module));
        assertEq(values[1], 0);
    }

    function testFormatExecuteParams_opBudgetExceeded() public {
        (bytes memory proposalData, ProposalOption[] memory options,) = _formatProposalData(true, true);
        uint256 weight = 100;

        vm.startPrank(governor);
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);
        module.propose(proposalId, proposalData, descriptionHash);

        uint256[] memory votes = new uint256[](2);
        votes[0] = 1;
        votes[1] = 2;
        bytes memory params = abi.encode(votes);
        module._countVote(proposalId, voter, uint8(VoteType.For), weight, params);

        votes = new uint256[](1);
        votes[0] = 1;
        params = abi.encode(votes);
        module._countVote(proposalId, altVoter, uint8(VoteType.For), weight, params);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            module._formatExecuteParams(proposalId, proposalData);
        vm.stopPrank();

        assertEq(targets.length, options[1].targets.length + 1);
        assertEq(targets.length, values.length);
        assertEq(targets.length, calldatas.length);
        assertEq(targets[0], options[1].targets[0]);
        assertEq(values[0], options[1].values[0]);
        assertEq(calldatas[0], options[1].calldatas[0]);
        assertEq(targets[1], options[1].targets[1]);
        assertEq(values[1], options[1].values[1]);
        assertEq(calldatas[1], options[1].calldatas[1]);
        assertEq(targets[2], address(module));
        assertEq(values[2], 0);
        assertEq(
            calldatas[2],
            abi.encodeCall(ApprovalVotingModule._afterExecute, (proposalId, proposalData, options[1].budgetTokensSpent))
        );
    }

    function testGetAccountVotes() public {
        (bytes memory proposalData,,) = _formatProposalData();
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);
        uint256 weight = 100;

        vm.startPrank(governor);
        module.propose(proposalId, proposalData, descriptionHash);

        uint256[] memory votes = new uint256[](2);
        votes[0] = 0;
        votes[1] = 1;
        bytes memory params = abi.encode(votes);

        module._countVote(proposalId, voter, uint8(VoteType.For), weight, params);

        assertEq(module.getAccountVotes(proposalId, voter)[0], 0);
        assertEq(module.getAccountVotes(proposalId, voter)[1], 1);
    }

    /*//////////////////////////////////////////////////////////////
                                REVERTS
    //////////////////////////////////////////////////////////////*/

    function testRevert_propose_existingProposal() public {
        (bytes memory proposalData,,) = _formatProposalData();
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);
        vm.prank(governor);
        module.propose(proposalId, proposalData, descriptionHash);

        vm.expectRevert(VotingModule.ExistingProposal.selector);
        vm.prank(governor);
        module.propose(proposalId, proposalData, descriptionHash);
    }

    function testRevert_propose_invalidProposalData() public {
        bytes memory proposalData = abi.encode(0x12345678);
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);

        vm.expectRevert();
        vm.prank(governor);
        module.propose(proposalId, proposalData, descriptionHash);
    }

    function testRevert_propose_invalidParams_noOptions() public {
        ProposalOption[] memory options = new ProposalOption[](0);
        ProposalSettings memory settings = ProposalSettings({
            maxApprovals: 1,
            criteria: uint8(PassingCriteria.TopChoices),
            criteriaValue: 1,
            budgetToken: address(0),
            budgetAmount: 1 ether
        });

        bytes memory proposalData = abi.encode(options, settings);
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);

        vm.expectRevert(VotingModule.InvalidParams.selector);
        vm.prank(governor);
        module.propose(proposalId, proposalData, descriptionHash);
    }

    function testRevert_propose_invalidParams_lengthMismatch() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](0);
        ProposalOption[] memory options = new ProposalOption[](1);
        options[0] = ProposalOption(0, targets, values, calldatas, "option");
        ProposalSettings memory settings = ProposalSettings({
            maxApprovals: 1,
            criteria: uint8(PassingCriteria.TopChoices),
            criteriaValue: 1,
            budgetToken: address(0),
            budgetAmount: 1 ether
        });

        bytes memory proposalData = abi.encode(options, settings);
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);

        vm.expectRevert(VotingModule.InvalidParams.selector);
        vm.prank(governor);
        module.propose(proposalId, proposalData, descriptionHash);
    }

    function testRevert_propose_maxChoicesExceeded() public {
        ProposalOption[] memory options = new ProposalOption[](2);
        ProposalSettings memory settings = ProposalSettings({
            maxApprovals: 1,
            criteria: uint8(PassingCriteria.TopChoices),
            criteriaValue: 3,
            budgetToken: address(0),
            budgetAmount: 1 ether
        });

        bytes memory proposalData = abi.encode(options, settings);
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);

        vm.expectRevert(ApprovalVotingModule.MaxChoicesExceeded.selector);
        vm.prank(governor);
        module.propose(proposalId, proposalData, descriptionHash);
    }

    function testRevert_propose_invalidCastVoteData() public {
        (bytes memory proposalData,,) = _formatProposalData();
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);
        uint256 weight = 100;

        vm.prank(governor);
        module.propose(proposalId, proposalData, descriptionHash);

        bytes memory params = abi.encode(0x12345678);

        vm.expectRevert();
        module._countVote(proposalId, voter, uint8(VoteType.For), weight, params);
    }

    function testRevert_propose_wrongProposalId() public {
        (bytes memory proposalData,,) = _formatProposalData();

        uint256 proposalId = hashProposalWithModule(address(this), address(module), proposalData, descriptionHash);

        vm.expectRevert(ApprovalVotingModule.WrongProposalId.selector);
        vm.prank(governor);
        module.propose(proposalId, proposalData, descriptionHash);
    }

    function testRevert_countVote_onlyGovernor() public {
        (bytes memory proposalData,,) = _formatProposalData();
        uint256 weight = 100;

        vm.prank(governor);
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);
        module.propose(proposalId, proposalData, descriptionHash);

        vm.expectRevert(VotingModule.NotGovernor.selector);
        module._countVote(proposalId, voter, uint8(VoteType.Abstain), weight, "");
    }

    function testRevert_countVote_invalidParams() public {
        (bytes memory proposalData,,) = _formatProposalData();
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);
        uint256 weight = 100;

        vm.prank(governor);
        module.propose(proposalId, proposalData, descriptionHash);

        uint256[] memory votes = new uint256[](0);
        bytes memory params = abi.encode(votes);

        vm.expectRevert(VotingModule.InvalidParams.selector);
        vm.prank(governor);
        module._countVote(proposalId, voter, uint8(VoteType.For), weight, params);
    }

    function testRevert_countVote_maxApprovalsExceeded() public {
        (bytes memory proposalData,,) = _formatProposalData();
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);
        uint256 weight = 100;

        vm.prank(governor);
        module.propose(proposalId, proposalData, descriptionHash);

        uint256[] memory votes = new uint256[](3);
        votes[0] = 0;
        votes[1] = 1;
        votes[2] = 2;
        bytes memory params = abi.encode(votes);

        vm.expectRevert(ApprovalVotingModule.MaxApprovalsExceeded.selector);
        vm.prank(governor);
        module._countVote(proposalId, voter, uint8(VoteType.For), weight, params);
    }

    function testRevert_countVote_optionsNotStrictlyAscending() public {
        (bytes memory proposalData,,) = _formatProposalData();
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);
        uint256 weight = 100;

        vm.prank(governor);
        module.propose(proposalId, proposalData, descriptionHash);

        uint256[] memory votes = new uint256[](2);
        votes[0] = 1;
        votes[1] = 0;
        bytes memory params = abi.encode(votes);

        vm.expectRevert(ApprovalVotingModule.OptionsNotStrictlyAscending.selector);
        vm.prank(governor);
        module._countVote(proposalId, voter, uint8(VoteType.For), weight, params);
    }

    function testRevert_countVote_outOfBounds() public {
        (bytes memory proposalData,,) = _formatProposalData();
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);
        uint256 weight = 100;

        vm.startPrank(governor);
        module.propose(proposalId, proposalData, descriptionHash);

        uint256[] memory votes = new uint256[](2);
        votes[0] = 2;
        votes[1] = 3;
        bytes memory params = abi.encode(votes);

        vm.expectRevert();
        module._countVote(proposalId, voter, uint8(VoteType.For), weight, params);
    }

    function testRevert_formatExecuteParams_onlyGovernor() public {
        (bytes memory proposalData,,) = _formatProposalData();

        vm.prank(governor);
        uint256 proposalId = hashProposalWithModule(governor, address(module), proposalData, descriptionHash);
        module.propose(proposalId, proposalData, descriptionHash);

        vm.expectRevert(VotingModule.NotGovernor.selector);
        module._formatExecuteParams(proposalId, proposalData);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _formatProposalData(bool budgetExceeded, bool isBudgetOp)
        internal
        view
        returns (bytes memory proposalData, ProposalOption[] memory options, ProposalSettings memory settings)
    {
        address[] memory targets1 = new address[](1);
        uint256[] memory values1 = new uint256[](1);
        bytes[] memory calldatas1 = new bytes[](1);
        // Send 0.01 ether to receiver1
        targets1[0] = receiver1;
        values1[0] = budgetExceeded ? 0.6 ether : 0.01 ether;

        address[] memory targets2 = new address[](2);
        uint256[] memory values2 = new uint256[](2);
        bytes[] memory calldatas2 = new bytes[](2);
        // Transfer 100 OP tokens to receiver2
        targets2[0] = token;
        calldatas2[0] = abi.encodeCall(IERC20.transfer, (receiver1, budgetExceeded ? 6e17 : 100));
        // Send 0.01 ether to receiver2, and emit call to test calls to targets different than budgetTokens are ignored
        targets2[1] = receiver2;
        values2[1] = budgetExceeded ? 0.6 ether : 0.01 ether;
        calldatas2[1] = calldatas2[0];

        options = new ProposalOption[](3);
        options[0] = ProposalOption(0, targets1, values1, calldatas1, "option 1");
        options[1] = ProposalOption(budgetExceeded ? 6e17 : 100, targets2, values2, calldatas2, "option 2");

        address[] memory targets3 = new address[](1);
        uint256[] memory values3 = new uint256[](1);
        bytes[] memory calldatas3 = new bytes[](1);
        targets3[0] = token;
        calldatas3[0] = abi.encodeCall(IERC20.transferFrom, (address(governor), receiver1, budgetExceeded ? 6e17 : 100));

        options[2] = ProposalOption(budgetExceeded ? 6e17 : 100, targets3, values3, calldatas3, "option 3");
        settings = ProposalSettings({
            maxApprovals: 2,
            criteria: uint8(PassingCriteria.TopChoices),
            criteriaValue: 2,
            budgetToken: isBudgetOp ? token : address(0),
            budgetAmount: 1e18
        });

        proposalData = abi.encode(options, settings);
    }

    function _formatProposalData()
        internal
        view
        returns (bytes memory proposalData, ProposalOption[] memory options, ProposalSettings memory settings)
    {
        return _formatProposalData(false, false);
    }

    function hashProposalWithModule(
        address sender,
        address module_,
        bytes memory proposalData,
        bytes32 descriptionHash_
    ) public view virtual returns (uint256) {
        return uint256(keccak256(abi.encode(sender, module_, proposalData, descriptionHash_)));
    }
}

contract GovernorMock {
    function timelock() external view returns (address) {
        return address(this);
    }
}
