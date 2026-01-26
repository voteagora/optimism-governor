# Timelock Proposal Canceller

This script generates Gnosis Safe transaction JSON files that can be imported into the Gnosis Safe UI to cancel proposals in Optimism's Timelock contract. This is the recommended approach for the Foundation's L2 Safe to cancel potentially malicious proposals.

## Features

- **Primary Feature:** Generates Gnosis Safe-compatible JSON files for cancelling queued timelock proposals
- Lists all pending proposals or targets a specific proposal ID
- **Optional:** Supports direct onchain cancellation with private key (not recommended for multisig operations)
- Can process single or multiple proposals at once

## Requirements

- Foundry (https://book.getfoundry.sh/getting-started/installation) - This script uses Foundry's `cast` tool
- Bash shell environment
- The `list-pending-proposals.sh` script in the same directory (when cancelling all proposals)

## Installation

1. Clone the repository:
```bash
git clone https://github.com/voteagora/optimism-governor.git
```

2. Navigate to the scripts directory:
```bash
cd optimism-governor/script/cancel-proposals/bash
```

## Usage

For Foundation's L2 Safe (recommended):
```bash
./cancel-proposals.sh [timelock_address] --proposal <id_or_all> --json [--output-dir <dir>]
```

Full usage with all options:
```bash
./cancel-proposals.sh [timelock_address] [--proposal <id_or_all>] [--rpc-url <rpc_url>] [--json] [--output-dir <dir>] [--chain-id <id>] [--private-key <key>] [--help]
```

### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `timelock_address` | The address of the `TimelockController` contract | 0x0eDd4B2cCCf41453D8B5443FBB96cc577d1d06bF |
| `--proposal <id_or_all>` | The proposal ID to cancel (32-byte hex starting with 0x) or 'all' for all pending proposals | Required parameter, no default |
| `--json` | Generate Gnosis Safe transaction JSON files **(recommended for L2 Safe use)** | False |
| `--output-dir <dir>` | Directory to save JSON files | ./safe-txs |
| `--rpc-url <url>` | The RPC endpoint URL to use | https://rpc.ankr.com/optimism |
| `--chain-id <id>` | Chain ID for the Safe transaction | 10 (Optimism) |
| `--private-key <key>` | Private key to sign and send transaction directly **(not recommended for multisig operations)** | None |
| `--help` | Display help information | - |

## How It Works

The script:

1. For the Foundation's L2 Safe (recommended workflow):
   - Run with the `--json` flag to generate Gnosis Safe transaction files
   - The generated files can be imported directly into the Gnosis Safe UI
   - No transactions are sent directly - execution happens through the multisig

2. For a specific proposal ID:
   - Generates the cancellation calldata
   - With `--json`: Creates a Gnosis Safe transaction file
   - Without any flags: Only outputs the ABI-encoded calldata

3. For "all" proposals:
   - Uses `list-pending-proposals.sh` to fetch all pending proposals
   - Processes each proposal as above

## Example Output (Recommended Usage)

```
> ./cancel-proposals.sh --proposal all --json
Using timelock address: 0x0eDd4B2cCCf41453D8B5443FBB96cc577d1d06bF
Using RPC URL: https://rpc.ankr.com/optimism
Will generate Gnosis Safe transaction JSON files in ./safe-txs
Starting cancellation process...
------------------------
Fetching all pending proposals...
Found 1 pending proposals
------------------------
Processing proposal: 0x15a9d5347cda8ddfbef031137bfbcb3e5d8dbf885b030516ff4456d715255bc5
Generated Gnosis Safe transaction JSON file: ./safe-txs/cancel-proposal-0x15a9d5347cda8ddfbef031137bfbcb3e5d8dbf885b030516ff4456d715255bc5.json
------------------------
Cancellation process completed
Gnosis Safe transaction JSON files are available in the ./safe-txs directory
You can import these files directly into the Gnosis Safe transaction builder UI
```

## Examples

### Recommended: Generate Gnosis Safe transaction JSON for a single proposal
```bash
./cancel-proposals.sh --proposal 0x15a9d5347cda8ddfbef031137bfbcb3e5d8dbf885b030516ff4456d715255bc5 --json
```

### Recommended: Generate Gnosis Safe transactions for all pending proposals
```bash
./cancel-proposals.sh --proposal all --json
```

### Generate Gnosis Safe transactions with custom output directory
```bash
./cancel-proposals.sh --proposal all --json --output-dir ./my-txs
```

### Get calldata only (without generating JSON)
```bash
./cancel-proposals.sh --proposal 0x15a9d5347cda8ddfbef031137bfbcb3e5d8dbf885b030516ff4456d715255bc5
```

### Direct cancellation (not recommended for multisig operations)
```bash
./cancel-proposals.sh --proposal 0x15a9d5347cda8ddfbef031137bfbcb3e5d8dbf885b030516ff4456d715255bc5 --private-key 0x...
```

## Using with Gnosis Safe (Recommended Workflow)

1. Run the script with the `--json` flag to generate transaction JSON files:
   ```bash
   ./cancel-proposals.sh --proposal all --json
   ```

2. In the Gnosis Safe UI, go to "New Transaction" > "Load transaction"

3. Drag and drop the generated JSON file or click to browse

4. Review the transaction details 

5. Submit the transaction for signing by the required signers

6. Execute the transaction once it has the required signatures

This workflow is the recommended approach for the Foundation's L2 Safe to safely cancel malicious proposals in the timelock without requiring direct key access.