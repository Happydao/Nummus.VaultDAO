#!/usr/bin/env bash
set -euo pipefail

# ========= Config =========
: "${HELIUS_API_KEY:?HELIUS_API_KEY non impostata}"
API_RPC="https://mainnet.helius-rpc.com/?api-key=$HELIUS_API_KEY"

WALLET="HtT3yMsAavLQYmd6VSbXSdbAefyZUrrFeEPoTPivde3s"
MINT_BUMPER="5bp5PwTyu4i1hGyQsRwRYqiR2CmxyHt2cPJGEbXEbonk"

DATA_DIR="data"
OUT_FILE="$DATA_DIR/onothers_token.json"

QTY_SCALE=12
PRICE_SCALE=12
VALUE_SCALE=2

command -v curl >/dev/null || { echo "curl mancante"; exit 1; }
command -v jq   >/dev/null || { echo "jq mancante"; exit 1; }
command -v bc   >/dev/null || { echo "bc mancante"; exit 1; }

mkdir -p "$DATA_DIR"

# ========= Helpers =========
num_or_zero() {
  local v="${1:-}"
  [[ -z "$v" || "$v" == "null" ]] && { echo 0; return; }
  # accetta anche 1e-4
  awk -v x="$v" 'BEGIN{ if (x+0==x+0) print x; else print 0 }'
}

fix_decimal() {
  # Forza formato decimale "normale" (niente 1e-4), con scale data
  # uso printf che capisce anche 1e-4
  local v="${1:-0}" scale="${2:-8}"
  printf "%.${scale}f" "$v"
}

# ========= 1) Quantità BUMPER =========
ASSETS_JSON=$(
  curl -sS -X POST "$API_RPC" -H "Content-Type: application/json" -d '{
    "jsonrpc":"2.0","id":"1","method":"getAssetsByOwner",
    "params":{"ownerAddress":"'"$WALLET"'","page":1,"limit":1000,
      "options":{"showFungible":true,"showZeroBalance":false}}
  }'
)

read -r RAW_BAL DECIMALS <<<"$(
  echo "$ASSETS_JSON" | jq -r --arg M "$MINT_BUMPER" '
    .result.items[]? | select(.id == $M) |
    "\(.token_info.balance) \(.token_info.decimals)"
  ' 2>/dev/null || echo ""
)"

RAW_BAL=$(num_or_zero "$RAW_BAL")
DECIMALS=${DECIMALS:-0}

if [[ "$RAW_BAL" != 0 && "$DECIMALS" =~ ^[0-9]+$ ]]; then
  QUANTITY=$(echo "scale=$QTY_SCALE; $RAW_BAL / (10 ^ $DECIMALS)" | bc -l)
else
  QUANTITY=$(printf "%.*f" "$QTY_SCALE" 0)
fi
QUANTITY=$(fix_decimal "$QUANTITY" "$QTY_SCALE")

# ========= 2) Prezzo da Jupiter =========
PRICE_JSON=$(curl -sS "https://price.jup.ag/v4/price?ids=$MINT_BUMPER&vsToken=USDC" || echo "")

RAW_PRICE=$(
  echo "$PRICE_JSON" | jq -r --arg ID "$MINT_BUMPER" '
    (.data[$ID].price // (.data[]?.price) // null)
  ' 2>/dev/null || echo "null"
)

# Se non c'è prezzo → esci con errore esplicito (meglio che salvare 0)
if [[ -z "$RAW_PRICE" || "$RAW_PRICE" == "null" ]]; then
  echo "❌ Nessun prezzo trovato per BUMPER su Jupiter (response vuota/null)."
  exit 1
fi

# Normalizza: accetta anche notazione scientifica e forza fixed-point
BUMPER_PRICE=$(num_or_zero "$RAW_PRICE")
BUMPER_PRICE_FMT=$(fix_decimal "$BUMPER_PRICE" "$PRICE_SCALE")

# ========= 3) Valore USD =========
VALUE_USD=$(echo "scale=$VALUE_SCALE; $QUANTITY * $BUMPER_PRICE_FMT" | bc -l)
VALUE_USD=$(fix_decimal "$VALUE_USD" "$VALUE_SCALE")

# ========= 4) Output JSON =========
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq -n \
  --arg token "BUMPER" \
  --arg mint "$MINT_BUMPER" \
  --arg price "$BUMPER_PRICE_FMT" \
  --arg qty "$QUANTITY" \
  --arg value "$VALUE_USD" \
  --arg time "$TIMESTAMP" '
{
  token: $token,
  mint: $mint,
  # Salviamo come numero ma già in fixed-point → niente 1e-xx
  price_usd: ($price | tonumber),
  quantity: ($qty | tonumber),
  total_value_usd: ($value | tonumber),
  timestamp: $time
}' > "$OUT_FILE"

echo "✅ Salvato in $OUT_FILE"
