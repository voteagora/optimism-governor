#!/bin/bash -e

set -o allexport
source .env
set +o allexport

forge script script/UpgradeOptimismGovernorV1.s.sol -vvvv \
  --fork-url https://mainnet.optimism.io \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
