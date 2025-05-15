#!/bin/bash

# Default values
DEFAULT_TIMELOCK="0x0eDd4B2cCCf41453D8B5443FBB96cc577d1d06bF"
DEFAULT_RPC="https://rpc.ankr.com/optimism"
DEFAULT_CHAIN_ID="10" # Optimism mainnet
TIMELOCK_ADDRESS=$DEFAULT_TIMELOCK
RPC_ARGS="--rpc-url $DEFAULT_RPC"
PROPOSAL_ID=""
ACCOUNT_NAME=""
GENERATE_JSON=false
OUTPUT_DIR="./safe-txs"
CHAIN_ID=$DEFAULT_CHAIN_ID

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --proposal)
      PROPOSAL_ID="$2"
      shift 2
      ;;
    --rpc-url)
      RPC_ARGS="--rpc-url $2"
      shift 2
      ;;
    --account-name)
      ACCOUNT_NAME="$2"
      shift 2
      ;;
    --json)
      GENERATE_JSON=true
      shift
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --chain-id)
      CHAIN_ID="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [timelock_address] [--proposal <id_or_all>] [--rpc-url <rpc_url>] [--private-key <key>] [--json] [--output-dir <dir>] [--chain-id <id>]"
      echo ""
      echo "Parameters:"
      echo "  timelock_address: The address of the TimelockController contract"
      echo "                   (defaults to $DEFAULT_TIMELOCK)"
      echo "  --proposal <id_or_all>: The proposal ID to cancel, or 'all' to cancel all pending proposals"
      echo "                        This parameter is required"
      echo "  --rpc-url <url>: The RPC endpoint URL to use"
      echo "                   (defaults to $DEFAULT_RPC)"
      echo "  --account-name <name>: The account name set with the cast wallet keystore to sign and send transaction"
      echo "                      If not provided, will only output the ABI-encoded calldata"
      echo "  --json: Generate Gnosis Safe transaction JSON files"
      echo "  --output-dir <dir>: Directory to save JSON files (defaults to ./safe-txs)"
      echo "  --chain-id <id>: Chain ID for the Safe transaction (defaults to 10 for Optimism)"
      exit 0
      ;;
    -*)
      echo "Unknown option: $1"
      echo "Use --help to see available options"
      exit 1
      ;;
    *)
      # First non-option argument is treated as the timelock address
      TIMELOCK_ADDRESS=$1
      shift
      ;;
  esac
done

# Verify proposal ID is provided
if [ -z "$PROPOSAL_ID" ]; then
  echo "Error: --proposal parameter is required"
  echo "Use --help to see available options"
  exit 1
fi

echo "Using timelock address: $TIMELOCK_ADDRESS"
echo "Using RPC URL: $(echo $RPC_ARGS | sed 's/--rpc-url //')"
[ -n "$ACCOUNT_NAME" ] && echo "Using account name: $ACCOUNT_NAME"
[ "$GENERATE_JSON" = true ] && echo "Will generate Gnosis Safe transaction JSON files in $OUTPUT_DIR"

# Create output directory if it doesn't exist
if [ "$GENERATE_JSON" = true ] && [ ! -d "$OUTPUT_DIR" ]; then
  mkdir -p "$OUTPUT_DIR"
  echo "Created output directory: $OUTPUT_DIR"
fi

# Function to generate Gnosis Safe transaction JSON
generate_safe_json() {
  local proposal_id=$1
  local calldata=$2
  local filename="${OUTPUT_DIR}/cancel-proposal-${proposal_id}.json"
  
  # Create JSON object
  cat > "$filename" << EOF
{
  "version": "1.0",
  "chainId": "${CHAIN_ID}",
  "createdAt": $(date +%s000),
  "meta": {
    "name": "Cancel proposal ${proposal_id}",
    "description": "Cancellation of queued proposal in TimelockController",
    "txBuilderVersion": "1.16.3"
  },
  "transactions": [
    {
      "to": "${TIMELOCK_ADDRESS}",
      "value": "0",
      "data": "${calldata}",
      "operation": 0,
      "nonce": 0
    }
  ]
}
EOF

  echo "Generated Gnosis Safe transaction JSON file: $filename"
}

# Function to process a proposal
process_proposal() {
  local proposal_id=$1
  
  echo "Processing proposal: $proposal_id"
  
  # Always generate the calldata first
  local calldata=$(cast calldata "cancel(bytes32)" "$proposal_id")
  
  if [ "$GENERATE_JSON" = true ]; then
    # Generate Gnosis Safe transaction JSON file
    generate_safe_json "$proposal_id" "$calldata"
  else
    # Just output the calldata
    echo "ABI-encoded calldata: $calldata"
  fi
  
  if [ -n "$PRIVATE_KEY" ]; then
    # If private key is provided, send the transaction
    echo "Sending transaction..."
    cast send $RPC_ARGS $TIMELOCK_ADDRESS "cancel(bytes32)" "$proposal_id" --account "$ACCOUNT_NAME"
  fi
}

# Main execution
echo "Starting cancellation process..."
echo "------------------------"

if [ "$PROPOSAL_ID" == "all" ]; then
  # Check if the list script exists
  if [ ! -f "./list-pending-proposals.sh" ]; then
    echo "Error: list-pending-proposals.sh not found in current directory"
    exit 1
  fi
  
  # Make sure the script is executable
  chmod +x ./list-pending-proposals.sh
  
  # Get all pending proposals
  echo "Fetching all pending proposals..."
  proposal_list=$(./list-pending-proposals.sh "$TIMELOCK_ADDRESS" $RPC_ARGS --type pending)
  
  # Extract proposal IDs from the output
  proposal_ids=($(echo "$proposal_list" | grep "Proposal ID:" | sed 's/Proposal ID: //'))
  
  if [ ${#proposal_ids[@]} -eq 0 ]; then
    echo "No pending proposals found"
    exit 0
  fi
  
  echo "Found ${#proposal_ids[@]} pending proposals"
  echo "------------------------"
  
  # Process each proposal
  for id in "${proposal_ids[@]}"; do
    process_proposal "$id"
    echo "------------------------"
  done
  
else
  # Process single specific proposal
  process_proposal "$PROPOSAL_ID"
fi

echo "Cancellation process completed"
if [ "$GENERATE_JSON" = true ]; then
  echo "Gnosis Safe transaction JSON files are available in the $OUTPUT_DIR directory"
  echo "You can import these files directly into the Gnosis Safe transaction builder UI"
fi