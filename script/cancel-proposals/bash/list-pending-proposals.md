# Timelock Proposal Lister

This script identifies and displays proposals in Optimism's Timelock contract by analyzing historical events and current contract state. It can show pending, cancelled, or executed proposals.

## Features

- Allows fetching proposals by type (pending, cancelled, executed)
- Decodes event data to extract proposal details
- Processes CallScheduled, Cancelled, and CallExecuted events
- For OP token transfers, calculates total token amounts at risk

## Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation) - This script uses Foundry's `cast` tool
- Bash shell environment

## Installation

1. Clone the repository:
```bash
git clone https://github.com/voteagora/op-governance-ops.git
```

2. Move to the directory:
```bash
cd op-governance-ops/procedures/timelock-admin
```

## Usage

```bash
./list-timelock-proposals.sh [timelock_address] [--rpc-url <rpc_url>] [--type <type>] [--help]
```

### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `timelock_address` | The address of the `TimelockController` contract | 0x0eDd4B2cCCf41453D8B5443FBB96cc577d1d06bF |
| `--rpc-url <url>` | The RPC endpoint URL to use | https://rpc.ankr.com/optimism |
| `--type <type>` | Type of proposals to display: pending, cancelled, or executed | pending |
| `--help` | Display help information | - |

## How It Works

The script:

1. Fetches all `CallScheduled`, `Cancelled`, and `CallExecuted` events from the `TimelockController`
2. Decodes the event data to extract details about each proposal
3. Processes OP token transfers to identify the amount at risk
4. Checks the current state of each proposal via the contract
5. Filters proposals based on the specified type (pending, cancelled, executed)
6. Displays detailed information including status, timestamps, and token amounts

## Example Output

```
> ./list-timelock-proposals.sh
Using timelock address: 0x0eDd4B2cCCf41453D8B5443FBB96cc577d1d06bF
Using RPC URL: https://rpc.ankr.com/optimism
Showing executed proposals
Fetching CallScheduled events...
Fetching Cancelled events...
Fetching CallExecuted events...
Processing scheduled operations...
Processing cancelled operations...
Processing executed operations...

Executed proposals in timelock:
==============================
Proposal ID: 
Block: 129092649
Tx: 
Created: Mon Dec  9 23:41:15 CET 2024
Target: 0x4200000000000000000000000000000000000042
Value: 0.000000000000000000 ETH
OP Tokens at risk: 1.000000000000000000 OP
Status: Executed
Ready at: Thu Dec 12 23:41:15 CET 2024
----------------------------

Total pending proposals: 1
```

## Examples

### Get list of pending proposals

```bash
./list-timelock-proposals.sh --type pending
```

Shows operations that have been scheduled but not yet executed or cancelled. For each pending proposal, it shows the time remaining until it's ready for execution or indicates if it's already ready.

### Get list of cancelled proposals

```bash
./list-timelock-proposals.sh --type cancelled
```

Shows operations that were scheduled but later cancelled before execution.

### Get list of executed proposals

```bash
./list-timelock-proposals.sh --type executed
```

Shows operations that have been successfully executed in the timelock.

## OP Token Detection

The script automatically detects operations that interact with the OP token:

- It identifies ERC20 transfers with function selector `0xa9059cbb`
- It decodes the recipient address and transfer amount
- It displays the amount of OP tokens at risk in a human-readable format