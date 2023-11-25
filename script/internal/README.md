## Internal scripts

### Set up

Add `MANAGER_KEY` and `VOTER_KEY` as private keys to `.env` file

### Execute scripts

`forge script script/internal/{scriptName}.s.sol -f op --broadcast --priority-gas-price 20000000`

### Order of execution

- TokenDelegateScript: Voter delegates to its proxy address
- AlligatorSubdelegateScript: Subdelegate from `manager` to `voter`
- CreateStandardProposalScript / CreateApprovalVotingProposalScript: Create props
  - note `proposalId` for subsequent steps
  - change descriptions or params if transaction fails due to already existing proposal
- CastVoteScript: Cast normal vote for `proposalId`, from `manager`
- CastVoteFromAlligatorScript: cast partially delegated votes for `proposalId`, from `voter`
