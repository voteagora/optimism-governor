#!/bin/bash

# Default values
DEFAULT_TIMELOCK="0x0eDd4B2cCCf41453D8B5443FBB96cc577d1d06bF"
DEFAULT_RPC="https://rpc.ankr.com/optimism"
DEFAULT_OP_TOKEN="0x4200000000000000000000000000000000000042" # OP token address
TIMELOCK_ADDRESS=$DEFAULT_TIMELOCK
RPC_ARGS="--rpc-url $DEFAULT_RPC"
TYPE="pending" # Default type

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --rpc-url)
      RPC_ARGS="--rpc-url $2"
      shift 2
      ;;
    --type)
      if [[ "$2" == "pending" || "$2" == "cancelled" || "$2" == "executed" ]]; then
        TYPE="$2"
        shift 2
      else
        echo "Error: Invalid type. Must be one of: pending, cancelled, executed"
        exit 1
      fi
      ;;
    --help)
      echo "Usage: $0 [timelock_address] [--rpc-url <rpc_url>] [--type <type>]"
      echo ""
      echo "Parameters:"
      echo "  timelock_address: The address of the TimelockController contract"
      echo "                   (defaults to $DEFAULT_TIMELOCK)"
      echo "  --rpc-url <url>: The RPC endpoint URL to use"
      echo "                   (defaults to $DEFAULT_RPC)"
      echo "  --type <type>:   Type of proposals to display: pending, cancelled, or executed"
      echo "                   (defaults to pending)"
      exit 0
      ;;
    -*)
      echo "Unknown option: $1"
      echo "Use --help to see available options"
      exit 1
      ;;
    *)
      TIMELOCK_ADDRESS=$1
      shift
      ;;
  esac
done

echo "Using timelock address: $TIMELOCK_ADDRESS"
echo "Using RPC URL: $(echo $RPC_ARGS | sed 's/--rpc-url //')"
echo "Showing $TYPE proposals"

# The signature of CallScheduled event
CALL_SCHEDULED_EVENT_SIG="CallScheduled(bytes32,uint256,address,uint256,bytes,bytes32,uint256)"
CANCELLED_EVENT_SIG="Cancelled(bytes32)"
CALL_EXECUTED_EVENT_SIG="CallExecuted(bytes32,uint256,address,uint256,bytes)"

# Default block range
FROM_BLOCK="128528629"
TO_BLOCK="latest"

echo "Fetching CallScheduled events..."
SCHEDULED_LOGS=$(cast logs $RPC_ARGS \
  --from-block $FROM_BLOCK \
  --to-block $TO_BLOCK \
  --address $TIMELOCK_ADDRESS \
  "$CALL_SCHEDULED_EVENT_SIG")


# Function to parse transaction data and detect OP token transfers
# Parameters:
#   $1: The full data field (with or without 0x prefix)
#   $2: The target address of the transaction
#   $3: The default OP token address for comparison
parse_function_data() {
    local data_input="$1"
    local target="$2"
    local op_token_address="${3:-0x4200000000000000000000000000000000000042}"
    local function_data=""
    
    # Ensure the data doesn't have 0x prefix for consistent processing
    local data_no_prefix="${data_input#0x}"
    
    # Check if there's enough data to parse
    if [ ${#data_no_prefix} -gt 320 ]; then
        # Get the length of the function data
        local data_length_hex=${data_no_prefix:320:64}
        local data_length=$(printf "%d" "0x${data_length_hex}" 2>/dev/null || echo "0")
        
        # Extract the actual function data if present
        if [ -n "$data_length" ] && [ "$data_length" -gt 0 ]; then
            # Function data starts after the length field
            function_data=${data_no_prefix:384}
            
            # Look for OP token transfers
            local target_lower=$(echo "$target" | tr '[:upper:]' '[:lower:]')
            local op_token_lower=$(echo "$op_token_address" | tr '[:upper:]' '[:lower:]')
            
            if [[ "$target_lower" == "$op_token_lower" && "${function_data:0:8}" == "a9059cbb" ]]; then
                # Decode the function call using cast 4byte-decode
                local decoded_data=$(cast 4byte-decode "$function_data")

                # Extract recipient and amount from decoded data
                local recipient=$(echo "$decoded_data" | sed -n '2p')
                local amount_wei=$(echo "$decoded_data" | sed -n '3p' | sed 's/\[.*//' | tr -cd '0-9')

                # Convert amount to OP units (18 decimals)
                local amount_op=$(cast --from-wei "$amount_wei")

                # Add token transfer info to function data
                function_data="OP Token transfer: $amount_op OP to $recipient"
            fi
        fi
    fi
    
    # Return the parsed function data
    echo "$function_data"
}

# Function to process each log
process_log() {
    local log="$1"
    
    # Extract basic fields
    local proposal_id=$(echo "$log" | grep "topics:" -A 2 | tail -n 1 | tr -d '[:space:]')
    local tx_hash=$(echo "$log" | grep "transactionHash:" | sed 's/.*transactionHash: *//')
    local block_number=$(echo "$log" | grep "blockNumber:" | sed 's/.*blockNumber: *//')
    
    # Get timestamp for block
    local block_info=$(cast block "$block_number" $RPC_ARGS --field timestamp)
    local start_timestamp=$block_info
    
    local data=$(echo "$log" | grep "data:" | sed 's/.*data: *//' | sed 's/^0x//')

    # # Extract target address (starts at position 0, 64 hex chars in length)
    # # Address is in the last 20 bytes of the 32 byte field
    local target_with_padding=${data:0:64}
    local target="0x${target_with_padding:24:40}"

    # Extract value (starts at position 64, 64 hex chars in length)
    local value_hex=${data:64:64}
    # Convert to decimal using printf instead of bc
    local value_dec=$(printf "%d" "0x${value_hex}" 2>/dev/null || echo "0")
    
    # Skip data pointer (position 128, 64 hex chars)
    
    # Extract predecessor (starts at position 192, 64 hex chars)
    local predecessor_hex=${data:192:64}

    # Extract delay (starts at position 256, 64 hex chars)
    local delay_hex=${data:256:64}
    local delay=$(printf "%d" "0x${delay_hex}" 2>/dev/null || echo "0")

    # Parse the transaction data
    local function_data=$(parse_function_data "$data" "$target")

    # Calculate ready timestamp
    local ready_timestamp=$((start_timestamp + delay))

    # Check if the proposal is pending, cancelled or executed
    local proposal_status
    if [ "$TYPE" == "pending" ]; then
        proposal_status=$(cast call $RPC_ARGS $TIMELOCK_ADDRESS "isOperationPending(bytes32)(bool)" "$proposal_id")
    elif [ "$TYPE" == "cancelled" ]; then
        proposal_status=$(cast call $RPC_ARGS $TIMELOCK_ADDRESS "getTimestamp(bytes32)(uint256)" "$proposal_id")
        if [ "$proposal_status" == "0" ]; then
            proposal_status="true"
        else
            proposal_status="false"
        fi
    elif [ "$TYPE" == "executed" ]; then
        proposal_status=$(cast call $RPC_ARGS $TIMELOCK_ADDRESS "isOperationDone(bytes32)(bool)" "$proposal_id")
    fi

    if [ "$proposal_status" != "true" ]; then
        return
    fi
    # Print results
    echo "Proposal ID: $proposal_id"
    echo "Transaction Hash: $tx_hash"
    echo "Start Block Number: $block_number"
    echo "Start Block Timestamp: $start_timestamp"
    echo "Transaction Target: $target"
    echo "Transaction Value: $value_dec"
    echo "Proposal Delay: $delay"
    echo "Ready Timestamp: $ready_timestamp"
    echo "Function Data: $function_data"
    echo "------------------------"
}

echo "Processing scheduled proposals:"
echo "------------------------"

# Save logs to a temporary file
TEMP_FILE=$(mktemp)
echo "$SCHEDULED_LOGS" > "$TEMP_FILE"

# Use a simple approach to extract each log entry
# Each log starts with "- address:" and contains multiple lines
{
    log_entry=""
    while IFS= read -r line; do
        if [[ "$line" == "- address:"* && -n "$log_entry" ]]; then
            # Process the previous log entry before starting a new one
            process_log "$log_entry"
            log_entry="$line"
        elif [[ "$line" == "- address:"* ]]; then
            # First log entry
            log_entry="$line"
        elif [[ -n "$log_entry" ]]; then
            # Continue building the current log entry
            log_entry="$log_entry
$line"
        fi
    done < "$TEMP_FILE"
    
    # Process the last log entry if it exists
    if [[ -n "$log_entry" ]]; then
        process_log "$log_entry"
    fi
}

# Clean up
rm -f "$TEMP_FILE"