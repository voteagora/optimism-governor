# Optimism Onchain Governance

## Motivation

Optimism is moving towards onchain governance. The initial version of the governance system is used for signalling purposes only and is designed to be upgraded in the future.

## Overview

The governance contract is upgradeable. The proxy is owned by the admin address, which is currently [the Optimism multisig](https://optimistic.etherscan.io/address/0x2501c477D0A35545a387Aa4A3EEe4292A9a8B3F0). The admin address can upgrade the implementation to a new version, and transfer ownership to a new address.

The core governor implementation is based on [OpenZeppelin's Governor](https://docs.openzeppelin.com/contracts/4.x/api/governance).

The contract has been modified to support the following features:

- Quorum calculation includes `for`, `against`, and `abstain` votes
- When executed, proposals don't perform any onchain actions
- A special `manager` address has certain permissions (see below)

## Roles

The contracts in this repo are designed to be used by the following roles:

- **admin** is the top-level owner of the governance system. The admin address can only do the following:

  - Upgrade implementation to a new version
  - Transfer admin role to a new address (inlcuding renouncing ownership)
  - Can't have any other roles (i.e. can't be a manager and can't interact with the governance system in any other way)

- **manager** address used in day-to-day operations of the governance system. The manager address has the following permissions:

  - Create proposals
  - Mark passed proposals as executed (without performing onchain actions)
  - Update any proposal's `endBlock` (to extend the voting period)
  - Update voting delay (number of blocks before a proposal can be voted on)
  - Update voting period (number of blocks a proposal can be voted on)
  - Update proposal threshold (number of votes required to create a proposal)
  - Update quorum (number of votes required to pass a proposal, snapshotted at the time of proposal creation)

- **voter** is any address that has OP tokens delegated to it

  - Vote on proposals
  - Delegate votes to another address (via OP token contract)

## Versions

6 versions of the OP governor implementation have been deployed.

### V1

Main implementation

### V2

- Set `quorumDenominator` to 100_000

### V3

- Added manager role: `cancel` proposal

### V4

- Fixes incorrect quorum for a past block

### V5

- Added support for voting modules
  - Update OZ `Governor` storage to add `moduleAddress` in `ProposalCore` struct
  - Updated / added new functions and events in [`OptimismGovernorV5`](/src/OptimismGovernorV5.sol) to interact with external modules
  - Updated `COUNTING_MODE` to also include `params=modules`
- Added [`ApprovalVotingModule`](/src/modules/ApprovalVotingModule.sol)

### V6

- [`Governor`](/src/OptimismGovernorV6.sol)
  - Added support for external voting modules
  - Added support for partial voting via Alligator
  - Added votable supply oracle
  - Added support for proposal types
- Voting modules with partial voting support
  - [`VotingModule`](/src/modules/VotingModule.sol)
  - [`ApprovalVotingModule`](/src/modules/ApprovalVotingModule.sol)
  - [`OptimisticModule`](/src/modules/OptimisticModule.sol)
- Liquid delegation protocol [`Alligator`](/src/alligator/AlligatorOP_V5.sol)
  - Added support for partial voting and advanced delegations
- [`ProposalTypesConfigurator`](/src/ProposalTypesConfigurator.sol)
  - Allows Governor manager to add, remove and update proposal types
- [`VotableSupplyOracle`](/src/VotableSupplyOracle.sol)
  - Allows contract owner to update votable supply used by the governor

## Deployment

- [`0xcDF27F107725988f2261Ce2256bDfCdE8B382B10`](https://optimistic.etherscan.io/address/0xcdf27f107725988f2261ce2256bdfcde8b382b10) - Optimism Governor Proxy

## See Also

- [OPerating Manual of the Optimism Collective](https://github.com/ethereum-optimism/OPerating-manual)
- [Agora](https://twitter.com/nounsagora)

## Audits

- [Optimism Governor V5 by Zach Obront](./audits/23-05-12_zachobront.md)
- [Optimism Governor V6 by Openzeppelin](./audits/23-11-22_openzeppelin.pdf)
