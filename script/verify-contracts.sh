#!/bin/bash

# Script to verify all contracts from the latest 'Deploy.s.sol' script run
# on a single, specified block explorer.
# It reads deployment details from the corresponding run-latest.json broadcast file.

# Required command-line arguments:
# $1: Chain ID (e.g., 11155111 for Sepolia)
# $2: Explorer Type ("etherscan", "blockscout", "sourcify")
# $3: Explorer API URL (required for "etherscan" & "blockscout", can be empty for "sourcify")
# $4: Explorer API Key (optional, can be empty)

# Optional Environment Variables:
# COMPILER_VERSION:        Specify if contracts were compiled with a non-default version.
# OPTIMIZER_RUNS:          Number of optimizer runs if enabled and non-default.
# CONTRACT_SRC_PATH:       Base path for contract source files (default: '../src/').
# FORGE_VERIFY_EXTRA_ARGS: Extra arguments to pass to all forge verify-contract calls.

set -uo pipefail # Exit on unset variables and on pipeline errors

# Constants
DEPLOY_SCRIPT_FILENAME="Deploy.s.sol"

# Functions

usage() {
  echo "Usage:"
  echo "  $(basename $0) <chain_id> <explorer_type> <explorer_api_url> <explorer_api_key>"
  echo
  echo "Etherscan:"
  echo "  $(basename $0) 11155111 etherscan https://api-sepolia.etherscan.io/api api_key_1234"
  echo
  echo "Blockscout:"
  echo "  $(basename $0) 100 blockscout https://blockscout.com/xdai/mainnet/api api_key_1234"
  echo
  echo "Sourcify:"
  echo "  $(basename $0) 11155111 sourcify \"\" \"\""
  echo
  echo "Explorer Types: 'etherscan', 'blockscout', 'sourcify'"
  echo "API URL and Key are not used for 'sourcify' type but placeholders might be needed if your Makefile passes them."
  echo ""
  echo "Optional Environment Variables:"
  echo "  COMPILER_VERSION, OPTIMIZER_RUNS, CONTRACT_SRC_PATH, FORGE_VERIFY_EXTRA_ARGS"
  exit 1
}

check_dependencies() {
  if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq to use this script."
    exit 1
  fi
  if ! command -v forge &> /dev/null; then
    echo "Error: forge is not installed. Please install Foundry to use this script."
    exit 1
  fi
}

build_common_args() {
  local contract_address="$1"
  local contract_verification_path="$2"
  local constructor_args_hex="$3"
  local libraries_cli_string="$4"

  common_args=()

  common_args+=("$contract_address")
  common_args+=("$contract_verification_path")

  if [[ -n "$constructor_args_hex" && "$constructor_args_hex" != "null" && "$constructor_args_hex" != "0x" ]]; then
    common_args+=(--constructor-args "$constructor_args_hex")
  fi

  if [[ -n "$libraries_cli_string" ]]; then
    read -ra lib_flags <<< "$libraries_cli_string"
    for lib_flag_part in "${lib_flags[@]}"; do
        common_args+=("$lib_flag_part")
    done
  fi

  if [[ -n "${COMPILER_VERSION:-}" ]]; then
    common_args+=(--compiler-version "$COMPILER_VERSION")
  fi

  if [[ -n "${OPTIMIZER_RUNS:-}" ]]; then
    common_args+=(--num-of-optimizations "$OPTIMIZER_RUNS")
  fi

  if [[ -n "${FORGE_VERIFY_EXTRA_ARGS:-}" ]]; then
    common_args+=($FORGE_VERIFY_EXTRA_ARGS)
  fi

  echo $common_args
}

verify_contract() {
  local contract_address="$1"
  local contract_name="$2"
  local contract_verification_path="$3"
  local constructor_args_hex="$4"
  local libraries_cli_string="$5"

  local explorer_type="$EXPLORER_TYPE" # From global script variable
  local api_url="$EXPLORER_API_URL"
  local api_key="$EXPLORER_API_KEY"

  echo "----------------------------------------------------------------------"
  echo "Verifying ${contract_name} (${contract_address}) (Type: ${explorer_type}, URL: ${api_url:-N/A})"
  echo "Contract Path for Verification: ${contract_verification_path}"

  common_args=$(build_common_args "$contract_address" "$contract_verification_path" "$constructor_args_hex" "$libraries_cli_string")

  local verify_cmd_args=()
  verify_cmd_args+=(--chain-id "$CHAIN_ID")
  verify_cmd_args+=(--rpc-url "$RPC_URL")

  case "$explorer_type" in
    etherscan)
      if [[ -z "$api_url" ]]; then
        echo "Error: API URL is required for etherscan type."
        return 1 # Indicate failure for this specific verification
      fi
      verify_cmd_args+=(--verifier etherscan)
      verify_cmd_args+=(--verifier-url "$api_url")
      if [[ -n "$api_key" ]]; then
        verify_cmd_args+=(--etherscan-api-key "$api_key")
      fi
      ;;
    blockscout)
      if [[ -z "$api_url" ]]; then
        echo "Error: API URL is required for blockscout type."
        return 1
      fi
      verify_cmd_args+=(--verifier blockscout)
      verify_cmd_args+=(--verifier-url "$api_url")
      if [[ -n "$api_key" ]]; then
        verify_cmd_args+=(--etherscan-api-key "$api_key")
      fi
      ;;
    sourcify)
      verify_cmd_args+=(--verifier sourcify)
      # API URL and Key are not typically used for direct sourcify verification with forge
      ;;
    *)
      echo "Error: Unknown explorer type '${explorer_type}'. Supported types: etherscan, blockscout, sourcify."
      return 1
      ;;
  esac

  verify_cmd_args+=("${common_args[@]}")

  echo "Executing: forge verify-contract ${verify_cmd_args[*]}"
  if forge verify-contract "${verify_cmd_args[@]}"; then
    echo "Successfully verified ${contract_name} (${explorer_type})."
  else
    echo "Failed to verify ${contract_name} (${explorer_type}). Check output above."
  fi
  echo "----------------------------------------------------------------------"
}

# Script Main Logic

check_dependencies

# CLI arguments
if [[ $# -lt 3 || $# -gt 4 ]]; then
  usage
fi

CHAIN_ID="$1"
EXPLORER_TYPE="$2"
EXPLORER_API_URL="$3"
EXPLORER_API_KEY="${4:-}"

# Validate explorer type
case "$EXPLORER_TYPE" in
  etherscan|blockscout|sourcify)
    ;; # Valid type
  *)
    echo "Error: Invalid explorer_type '$EXPLORER_TYPE'."
    usage
    ;;
esac

if [[ ("$EXPLORER_TYPE" == "etherscan" || "$EXPLORER_TYPE" == "blockscout") && -z "$EXPLORER_API_URL" ]]; then
    echo "Error: Explorer API URL (argument 4) is required for type '$EXPLORER_TYPE'."
    usage
fi

RUN_LATEST_JSON_PATH="broadcast/${DEPLOY_SCRIPT_FILENAME}/${CHAIN_ID}/run-latest.json"

if [[ ! -f "$RUN_LATEST_JSON_PATH" ]]; then
  echo "Error: Broadcast file not found at ${RUN_LATEST_JSON_PATH}"
  echo "Ensure you have run 'forge script ${DEPLOY_SCRIPT_FILENAME} --chain-id ${CHAIN_ID} --broadcast ...' first."
  exit 1
fi
echo "Reading deployment data from: ${RUN_LATEST_JSON_PATH}"

jq_query=$(cat <<EOF
.transactions[] |
  select(.transactionType == "CREATE" or .transactionType == "CREATE2") |
  select(.contractAddress != null and .contractAddress != "0x0000000000000000000000000000000000000000") |
  select(.contractName != null and .contractName != "") |
  {
    address: .contractAddress,
    name: .contractName,
    constructorArgs: (.constructorArguments // "")
  } |
  "\(.address)|\(.name)|\(.constructorArgs)"
EOF
)

src_contract_path_base="${CONTRACT_SRC_PATH:-src/}"
[[ "${src_contract_path_base}" != */ ]] && src_contract_path_base="${src_contract_path_base}/"

jq -r "$jq_query" "$RUN_LATEST_JSON_PATH" | while IFS='|' read -r contract_address contract_name constructor_args_hex libraries_cli_string; do
  if [[ -z "$contract_address" || -z "$contract_name" ]]; then
    echo "Skipping entry with missing address or name: Addr='${contract_address}', Name='${contract_name}'"
    continue
  fi

  echo ""
  echo "Processing contract: ${contract_name} at ${contract_address}"
  contract_verification_path="${src_contract_path_base}${contract_name}.sol:${contract_name}"

  verify_contract "$contract_address" \
                               "$contract_name" \
                               "$contract_verification_path" \
                               "$constructor_args_hex" \
                               "$libraries_cli_string"
done

echo ""
echo "All contracts processed."
