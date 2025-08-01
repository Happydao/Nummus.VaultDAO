#!/bin/bash
set -e

# === Config ===
WALLET="HtT3yMsAavLQYmd6VSbXSdbAefyZUrrFeEPoTPivde3s"  # Wallet 2
MINT_BUMPER="5bp5PwTyu4i1hGyQsRwRYqiR2CmxyHt2cPJGEbXEbonk"
API_RPC="https://mainnet.helius-rpc.com/?api-key=$HELIUS_API_KEY"
DATA_DIR="data"
OUT_FILE="$DATA_DIR/onothers_token.json"

mkdir -p "$DATA_DIR"

# === Get BUMPER balance ===
BAL_DEC=$(curl -s -X POST "$API_RPC" -H "Content-Type: application/json" -d '{
  "jsonrpc":"2.0","id":"1","method":"getAssetsByOwner",
  "params":{
    "ownerAddress":"'"$WALLET"'",
    "page":1,"limit":1000,
    "options":{"showFungible":true,"showZeroBalance":false}
  }
}' | jq -r --arg M "$MINT_BUMPER" '
  .result.items[]? | select(.id == $M) |
  {bal: (.token_info.balance | tonumber), dec: (.token_info.decimals | tonumber)} |
  "\(.bal) \(.dec)"')

if [ -n "$BAL_DEC" ]; then
  QUANTITY=$(echo "$BAL_DEC" | awk '{ if ($1 && $2) printf "%.8f", $1 / (10 ^ $2); else print "0.00000000" }')
else
  QUANTITY="0.00000000"
fi

# === Get BUMPER price from Jupiter ===
BUMPER_PRICE=$(curl -s "https://price.jup.ag/v4/price?ids=$MINT_BUMPER&vsToken=USDC" | jq -r '.data[].price' || echo "0")

# === Calculate total value ===
VALUE_USD=$(awk "BEGIN {printf \"%.2f\", $QUANTITY * $BUMPER_PRICE}")

# === Output JSON ===
jq -n \
  --arg price "$BUMPER_PRICE" \
  --arg qty "$QUANTITY" \
  --arg value "$VALUE_USD" \
  --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    token: "BUMPER",
    mint: "'"$MINT_BUMPER"'",
    price_usd: ($price | tonumber),
    quantity: ($qty | tonumber),
    total_value_usd: ($value | tonumber),
    timestamp: $time
  }' > "$OUT_FILE"

echo "✅ Saved BUMPER info to $OUT_FILE"
