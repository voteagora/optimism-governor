# Optimism Governor Proposal Cancellation Tools

This directory contains tools for the Foundation's L2 Safe (or Security Council) to cancel queued proposals in the timelock if they are malicious.

## Available Tools

### 1. Solidity Script (CancelProposal.s.sol)

A Foundry script to:
- View queued proposals
- Generate cancellation transactions
- Generate JSON files for Gnosis Safe transaction builder UI

#### Usage

```bash
# View queued proposals
forge script script/CancelProposal.s.sol:CancelProposal --sig "viewQueuedProposals()" --rpc-url $RPC_URL

# Generate a cancellation transaction for a specific operation
forge script script/CancelProposal.s.sol:CancelProposal --sig "generateCancelTx(bytes32)" --rpc-url $RPC_URL

# Generate and save a cancellation transaction to a file
forge script script/CancelProposal.s.sol:CancelProposal --sig "generateCancelTxToFile(bytes32,string)" --rpc-url $RPC_URL
```

### 2. JavaScript CLI (CancelProposalCLI.js)

A more user-friendly CLI tool to:
- Find all currently queued proposals
- View their details and time remaining until execution
- Generate cancellation transactions compatible with Gnosis Safe

#### Setup

```bash
# Install dependencies
cd script
npm install

# Make the script executable (Unix-like systems)
chmod +x CancelProposalCLI.js

# Configure the tool
# Edit the config.json file with your RPC URL and governor address
```

#### Configuration

The tool will create a `config.json` file on first run. You should edit this file with the appropriate values:

```json
{
  "optimismGovernorAddress": "0x0000000000000000000000000000000000000000", // Replace with actual address
  "rpcUrl": "https://mainnet.optimism.io",
  "chainId": 10,
  "fromBlock": 0 // Starting block for event scanning (can be set to a more recent block)
}
```

#### Usage

```bash
# Run the CLI tool
node CancelProposalCLI.js

# Or use npm
npm start
```

## How It Works

1. The tools connect to the Optimism blockchain and locate the timelock controller address.
2. They identify queued proposals that are waiting in the timelock.
3. They generate transaction data to call the `cancel(bytes32 id)` function on the timelock controller.
4. The generated JSON file can be imported into the Gnosis Safe transaction builder UI.

## Security Considerations

- Only addresses with the CANCELLER_ROLE can successfully execute cancel transactions.
- The Foundation's L2 Safe must have been previously granted this role.
- These tools do not execute transactions directly - they only generate the transaction data.
- Always review the transaction in the Gnosis Safe UI before execution.

## Emergency Instructions

If a malicious proposal is discovered:

1. Run the CLI tool to list all queued proposals
2. Identify the malicious proposal by its ID
3. Generate a cancellation transaction
4. Import the JSON file into Gnosis Safe
5. Verify the transaction details
6. Execute the transaction from Gnosis Safe with the required number of signers

## Support

For assistance with these tools, please contact the Optimism Foundation security team. 