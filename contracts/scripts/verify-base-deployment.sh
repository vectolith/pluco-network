#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$ROOT_DIR/contracts/art/deployments/base.json"
BASE_RPC_URL="${BASE_RPC_URL:-https://mainnet.base.org}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for deployment verification." >&2
  exit 1
fi
if ! command -v cast >/dev/null 2>&1; then
  echo "Foundry cast is required for deployment verification." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 is required for runtime bytecode verification." >&2
  exit 1
fi

rpc() {
  local method="$1"
  local params="$2"
  local payload
  local response
  payload="$(jq -cn --arg method "$method" --argjson params "$params" \
    '{jsonrpc:"2.0",id:1,method:$method,params:$params}')"
  response="$(curl --fail --silent --show-error --retry 3 --retry-delay 1 \
    --retry-all-errors --max-time 25 "$BASE_RPC_URL" \
    -H "Content-Type: application/json" --data "$payload")"
  if jq -e '.error != null' >/dev/null <<<"$response"; then
    echo "Base RPC error for $method: $(jq -c '.error' <<<"$response")" >&2
    return 1
  fi
  jq -c '.result' <<<"$response"
}

manifest_value() {
  jq -er "$1" "$MANIFEST"
}

normalize_address() {
  tr '[:upper:]' '[:lower:]' <<<"$1"
}

expect_equal() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  if [[ "$(normalize_address "$actual")" != "$(normalize_address "$expected")" ]]; then
    echo "$label mismatch: expected $expected, received $actual" >&2
    exit 1
  fi
  echo "Verified $label: $actual"
}

verify_transaction() {
  local label="$1"
  local tx_hash="$2"
  local expected_address="$3"
  local receipt
  local status
  local observed_address

  receipt="$(rpc eth_getTransactionReceipt "[\"$tx_hash\"]")"
  if [[ "$receipt" == "null" ]]; then
    echo "$label transaction has no indexed receipt: $tx_hash" >&2
    exit 1
  fi

  status="$(jq -r '.status // empty' <<<"$receipt")"
  if [[ "$status" != "0x1" ]]; then
    echo "$label transaction did not succeed (status: $status): $tx_hash" >&2
    exit 1
  fi

  if [[ "$label" == deploy* ]]; then
    observed_address="$(jq -r '.contractAddress // empty' <<<"$receipt")"
    expect_equal "$label contract address" "$observed_address" "$expected_address"
  else
    observed_address="$(jq -r '.to // empty' <<<"$receipt")"
    expect_equal "$label target contract" "$observed_address" "$expected_address"
  fi

  echo "Verified successful transaction: $label ($tx_hash)"
}

echo "Verifying Vectolith PLUCO deployment against Base mainnet RPC: $BASE_RPC_URL"
chain_id="$(rpc eth_chainId '[]' | tr -d '"')"
if [[ "$chain_id" != "0x2105" ]]; then
  echo "Expected Base mainnet chain ID 0x2105, received $chain_id" >&2
  exit 1
fi

owner="$(manifest_value '.owner')"
treasury="$(manifest_value '.treasury')"
royalty_receiver="$(manifest_value '.royaltyReceiver')"
registry="$(manifest_value '.contracts.registry')"
originals="$(manifest_value '.contracts.originals')"
marketplace="$(manifest_value '.contracts.marketplace')"

verify_transaction "deployRegistry" "$(manifest_value '.transactions.deployRegistry')" "$registry"
verify_transaction "deployOriginals" "$(manifest_value '.transactions.deployOriginals')" "$originals"
verify_transaction "deployMarketplace" "$(manifest_value '.transactions.deployMarketplace')" "$marketplace"
verify_transaction "register" "$(manifest_value '.transactions.register')" "$registry"
verify_transaction "mint" "$(manifest_value '.transactions.mint')" "$originals"
verify_transaction "list" "$(manifest_value '.transactions.list')" "$marketplace"
verify_transaction "buy" "$(manifest_value '.transactions.buy')" "$marketplace"
verify_transaction "withdraw" "$(manifest_value '.transactions.withdraw')" "$marketplace"

verify_runtime_bytecode() {
  local label="$1"
  local address="$2"
  local artifact="$3"
  local code
  code="$(rpc eth_getCode "[\"$address\",\"latest\"]" | tr -d '"')"
  if [[ "$code" == "0x" || "$code" == "0x0" ]]; then
    echo "No deployed bytecode at $address" >&2
    exit 1
  fi
  python3 "$ROOT_DIR/contracts/scripts/verify-runtime-bytecode.py" \
    "$artifact" "$code" "$label"
}

verify_runtime_bytecode "registry" "$registry" \
  "$ROOT_DIR/contracts/out/VectolithRegistry.sol/VectolithRegistry.json"
verify_runtime_bytecode "originals" "$originals" \
  "$ROOT_DIR/contracts/out/VectolithOriginals.sol/VectolithOriginals.json"
verify_runtime_bytecode "marketplace" "$marketplace" \
  "$ROOT_DIR/contracts/out/VectolithMarketplace.sol/VectolithMarketplace.json"

registry_owner="$(cast call "$registry" "owner()(address)" --rpc-url "$BASE_RPC_URL")"
originals_owner="$(cast call "$originals" "owner()(address)" --rpc-url "$BASE_RPC_URL")"
marketplace_owner="$(cast call "$marketplace" "owner()(address)" --rpc-url "$BASE_RPC_URL")"
expect_equal "registry owner" "$registry_owner" "$owner"
expect_equal "originals owner" "$originals_owner" "$owner"
expect_equal "marketplace owner" "$marketplace_owner" "$owner"

marketplace_registry="$(cast call "$marketplace" "registry()(address)" --rpc-url "$BASE_RPC_URL")"
marketplace_treasury="$(cast call "$marketplace" "treasury()(address)" --rpc-url "$BASE_RPC_URL")"
originals_treasury="$(cast call "$originals" "treasury()(address)" --rpc-url "$BASE_RPC_URL")"
expect_equal "marketplace registry" "$marketplace_registry" "$registry"
expect_equal "marketplace treasury" "$marketplace_treasury" "$treasury"
expect_equal "originals treasury" "$originals_treasury" "$treasury"

marketplace_fee="$(cast call "$marketplace" "feeBps()(uint96)" --rpc-url "$BASE_RPC_URL" | awk '{print $1}')"
originals_fee="$(cast call "$originals" "feeBps()(uint96)" --rpc-url "$BASE_RPC_URL" | awk '{print $1}')"
max_supply="$(cast call "$originals" "maxSupply()(uint256)" --rpc-url "$BASE_RPC_URL" | awk '{print $1}')"
max_per_wallet="$(cast call "$originals" "maxPerWallet()(uint256)" --rpc-url "$BASE_RPC_URL" | awk '{print $1}')"
mint_price="$(cast call "$originals" "mintPrice()(uint256)" --rpc-url "$BASE_RPC_URL" | awk '{print $1}')"
expected_marketplace_fee="$(manifest_value '.settings.marketplaceFeeBps')"
expected_mint_fee="$(manifest_value '.settings.mintFeeBps')"
expected_max_supply="$(manifest_value '.settings.maxSupply')"
expected_mint_price="$(cast to-wei "$(manifest_value '.settings.mintPriceEth')" ether)"

[[ "$marketplace_fee" == "$expected_marketplace_fee" ]] || {
  echo "Marketplace fee mismatch: expected $expected_marketplace_fee, received $marketplace_fee" >&2
  exit 1
}
[[ "$originals_fee" == "$expected_mint_fee" ]] || {
  echo "Primary mint fee mismatch: expected $expected_mint_fee, received $originals_fee" >&2
  exit 1
}
[[ "$max_supply" == "$expected_max_supply" ]] || {
  echo "Maximum supply mismatch: expected $expected_max_supply, received $max_supply" >&2
  exit 1
}
if (( max_per_wallet < 1 || max_per_wallet > max_supply )); then
  echo "Invalid maximum-per-wallet setting: $max_per_wallet (max supply: $max_supply)" >&2
  exit 1
fi
echo "Observed maxPerWallet: $max_per_wallet"
[[ "$mint_price" == "$expected_mint_price" ]] || {
  echo "Mint price mismatch: expected $expected_mint_price, received $mint_price" >&2
  exit 1
}

royalty_info="$(cast call "$originals" "royaltyInfo(uint256,uint256)(address,uint256)" 1 10000 --rpc-url "$BASE_RPC_URL")"
if ! grep -qi "$royalty_receiver" <<<"$royalty_info"; then
  echo "EIP-2981 royalty receiver mismatch: expected $royalty_receiver, received $royalty_info" >&2
  exit 1
fi
if ! grep -q "750" <<<"$royalty_info"; then
  echo "EIP-2981 royalty amount did not match the manifest's 7.5% rate: $royalty_info" >&2
  exit 1
fi

registry_active="$(cast call "$registry" "isActive(address)(bool)" "$originals" --rpc-url "$BASE_RPC_URL")"
total_minted="$(cast call "$originals" "totalMinted()(uint256)" --rpc-url "$BASE_RPC_URL" | awk '{print $1}')"
listing_count="$(cast call "$marketplace" "listingCount()(uint256)" --rpc-url "$BASE_RPC_URL" | awk '{print $1}')"
[[ "$registry_active" == "true" ]] || {
  echo "The Originals collection is not active in the registry." >&2
  exit 1
}
(( total_minted >= 1 )) || {
  echo "Expected at least one minted Original; received $total_minted." >&2
  exit 1
}
(( listing_count >= 1 )) || {
  echo "Expected at least one marketplace listing; received $listing_count." >&2
  exit 1
}

echo "Base deployment transaction, bytecode, ownership, treasury, fee, supply, mint, registry and royalty checks passed."
echo "Explorer source verification and an independent contract security review remain separate requirements."
