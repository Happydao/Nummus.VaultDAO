#!/usr/bin/env bash
set -euo pipefail

: "${HELIUS_API_KEY:?HELIUS_API_KEY non impostata}"
API_RPC="https://mainnet.helius-rpc.com/?api-key=$HELIUS_API_KEY"

WALLET="HtT3yMsAavLQYmd6VSbXSdbAefyZUrrFeEPoTPivde3s"
MINT_BUMPER="5bp5PwTyu4i1hGyQsRwRYqiR2CmxyHt2cPJGEbXEbonk"
MINT_USDC="EPjFWdd5Au1Y7x1fGkM4uJ7x1GzW1tWQpM1vMcmGmC1"   # USDC (Solana mainnet)

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

# === 1) Leggi balance grezzo + decimals (Helius) ===
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

# quantità = balance / 10^decimals
if [[ "$RAW_BAL" != 0 && "$DECIMALS" =~ ^[0-9]+$ ]]; then
  QUANTITY=$(echo "scale=$QTY_SCALE; $RAW_BAL / (10 ^ $DECIMALS)" | bc -l)
else
  QUANTITY=$(printf "%.*f" "$QTY_SCALE" 0)
fi
QUANTITY=$(fix_decimal "$QUANTITY" "$QTY_SCALE")

# === 2) Prezzo BUMPER -> USDC con quote-api (amount = 1 token) ===
# amount = 10^decimals (unità minime del token)
AMOUNT_SMALLEST=$(echo "10 ^ $DECIMALS" | bc)   # intero senza decimali

# nota: Jupiter richiede amount come intero (stringa), non in decimali
QUOTE_JSON=$(curl -sS --retry 3 --retry-delay 2 --max-time 60 \
  "https://quote-api.jup.ag/v6/quote?inputMint=$MINT_BUMPER&outputMint=$MINT_USDC&amount=$AMOUNT_SMALLEST&slippageBps=50" \
  || echo '{}')

# Se non c’è route o outAmount manca, fallisci esplicitamente (meglio di salvare 0)
HAS_ROUTE=$(echo "$QUOTE_JSON" | jq -r 'has("outAmount") or ((.routePlan // []) | length > 0)')
if [[ "$HAS_ROUTE" != "true" ]]; then
  echo "❌ Jupiter non ha una route BUMPER→USDC per amount=$AMOUNT_SMALLEST (decimals=$DECIMALS)."
  echo "Response: $QUOTE_JSON"
  exit 1
fi

OUT_AMOUNT_USDC_SMALLEST=$(echo "$QUOTE_JSON" | jq -r '.outAmount // "0"')
if [[ "$OUT_AMOUNT_USDC_SMALLEST" == "0" ]]; then
  echo "❌ outAmount=0 dalla quote BUMPER→USDC; impossibile calcolare il prezzo."
  echo "Response: $QUOTE_JSON"
  exit 1
fi

# USDC ha 6 decimali su Solana
PRICE_BUMPER_USD=$(echo "scale=$PRICE_SCALE; $OUT_AMOUNT_USDC_SMALLEST / (10 ^ 6)" | bc -l)
PRICE_BUMPER_USD=$(fix_decimal "$PRICE_BUMPER_USD" "$PRICE_SCALE")

# === 3) Valore totale ===
VALUE_USD=$(echo "scale=$VALUE_SCALE; $QUANTITY * $PRICE_BUMPER_USD" | bc -l)
VALUE_USD=$(fix_decimal "$VALUE_USD" "$VALUE_SCALE")

# === 4) Output JSON (fixed-point, niente 0E-8) ===
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n \
  --arg token "BUMPER" \
  --arg mint "$MINT_BUMPER" \
  --arg price "$PRICE_BUMPER_USD" \
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

echo "✅ Salvato $OUT_FILE"
echo "   price_usd=$PRICE_BUMPER_USD | qty=$QUANTITY | total_usd=$VALUE_USD"

