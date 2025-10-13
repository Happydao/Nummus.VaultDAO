#!/usr/bin/env bash
set -euo pipefail

: "${HELIUS_API_KEY:?HELIUS_API_KEY non impostata}"
API_RPC="https://mainnet.helius-rpc.com/?api-key=$HELIUS_API_KEY"

WALLET="HtT3yMsAavLQYmd6VSbXSdbAefyZUrrFeEPoTPivde3s"
MINT_BUMPER="5bp5PwTyu4i1hGyQsRwRYqiR2CmxyHt2cPJGEbXEbonk"
MINT_SOL="So11111111111111111111111111111111111111112"

DATA_DIR="data"
OUT_FILE="$DATA_DIR/onothers_token.json"

QTY_SCALE=12
PRICE_SCALE=12
VALUE_SCALE=2

for bin in curl jq bc awk; do
  command -v "$bin" >/dev/null 2>&1 || { echo "❌ Missing '$bin'"; exit 1; }
done

mkdir -p "$DATA_DIR"

num_or_zero() {
  local v="${1:-}"
  [[ -z "$v" || "$v" == "null" ]] && { echo 0; return; }
  awk -v x="$v" 'BEGIN{ if (x+0==x+0) print x; else print 0 }'
}

fix_decimal() {
  local v="${1:-0}" scale="${2:-8}"
  printf "%.${scale}f" "$v"
}

# === 1) Quantità detenuta ===
ASSETS_JSON=$(
  curl -sS -X POST "$API_RPC" -H "Content-Type: application/json" -d '{
    "jsonrpc":"2.0","id":"1","method":"getAssetsByOwner",
    "params":{"ownerAddress":"'"$WALLET"'","page":1,"limit":1000,
      "options":{"showFungible":true,"showZeroBalance":false}}
  }'
)

read -r RAW_BAL DECIMALS <<<"$(
  echo "$ASSETS_JSON" | jq -r --arg M "$MINT_BUMPER" '
    (.result.items // [])[] | select(.id == $M) |
    "\(.token_info.balance) \(.token_info.decimals)"
  ' | head -n1
)"

RAW_BAL=$(num_or_zero "$RAW_BAL")
DECIMALS=${DECIMALS:-0}

if [[ "$RAW_BAL" != 0 && "$DECIMALS" =~ ^[0-9]+$ ]]; then
  QUANTITY=$(echo "scale=$QTY_SCALE; $RAW_BAL / (10 ^ $DECIMALS)" | bc -l)
else
  QUANTITY=$(printf "%.*f" "$QTY_SCALE" 0)
fi
QUANTITY=$(fix_decimal "$QUANTITY" "$QTY_SCALE")

# === 2) Prezzo BUMPER (Jupiter) ===
# Primo tentativo: price.jup.ag in USDC
PRICE_BUMPER=""
JUP_PRICE_JSON=$(curl -sS --retry 3 --retry-delay 2 --max-time 60 \
  "https://price.jup.ag/v4/price?ids=$MINT_BUMPER&vsToken=USDC" || echo "")

PRICE_BUMPER_DIRECT=$(echo "$JUP_PRICE_JSON" \
  | jq -r --arg ID "$MINT_BUMPER" '.data[$ID].price // (.data[]?.price) // empty')

if [[ -n "$PRICE_BUMPER_DIRECT" ]]; then
  PRICE_BUMPER="$PRICE_BUMPER_DIRECT"
else
  # Fallback: route quote → SOL (solo se serve)
  PRICE_SOL=$(curl -sS --retry 3 --retry-delay 2 --max-time 60 \
    "https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=usd" \
    | jq -r '.solana.usd // 0')

  QUOTE_JSON=$(curl -sS --retry 3 --retry-delay 2 --max-time 60 \
    "https://quote-api.jup.ag/v6/quote?inputMint=$MINT_BUMPER&outputMint=$MINT_SOL&amount=1000000&slippage=1" \
    || echo '{}')
  OUT_AMOUNT=$(echo "$QUOTE_JSON" | jq -r '.outAmount // "0"')

  SOL_PER_BUMPER=$(awk "BEGIN {printf \"%.12f\", $OUT_AMOUNT / 1000000000}")
  PRICE_BUMPER=$(awk "BEGIN {printf \"%.12f\", $SOL_PER_BUMPER * $PRICE_SOL}")
fi

# valida il numero
if ! awk "BEGIN{exit(!($PRICE_BUMPER+0==($PRICE_BUMPER+0)))}"; then
  echo "❌ Prezzo BUMPER non disponibile (Jupiter)."; exit 1
fi
BUMPER_PRICE_FMT=$(fix_decimal "$PRICE_BUMPER" "$PRICE_SCALE")

# === 3) Valore totale ===
VALUE_USD=$(echo "scale=$VALUE_SCALE; $QUANTITY * $BUMPER_PRICE_FMT" | bc -l)
VALUE_USD=$(fix_decimal "$VALUE_USD" "$VALUE_SCALE")

# === 4) Output ===
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
  price_usd: ($price | tonumber),
  quantity: ($qty | tonumber),
  total_value_usd: ($value | tonumber),
  timestamp: $time
}' > "$OUT_FILE"

echo "✅ Salvato $OUT_FILE (price_usd=$BUMPER_PRICE_FMT, qty=$QUANTITY, total_usd=$VALUE_USD)"
