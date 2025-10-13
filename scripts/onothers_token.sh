#!/usr/bin/env bash
set -euo pipefail

# ========================
# Config
# ========================
: "${HELIUS_API_KEY:?HELIUS_API_KEY non impostata}"
API_RPC="https://mainnet.helius-rpc.com/?api-key=$HELIUS_API_KEY"

# Wallet & mint (BUMPER su Solana)
WALLET="HtT3yMsAavLQYmd6VSbXSdbAefyZUrrFeEPoTPivde3s"
MINT_BUMPER="5bp5PwTyu4i1hGyQsRwRYqiR2CmxyHt2cPJGEbXEbonk"

DATA_DIR="data"
OUT_FILE="$DATA_DIR/onothers_token.json"

# Precisioni
QTY_SCALE=12       # decimali per la quantità
PRICE_SCALE=12     # decimali per il prezzo
VALUE_SCALE=2      # decimali per il totale USD

# ========================
# Dipendenze
# ========================
for bin in curl jq bc awk; do
  command -v "$bin" >/dev/null 2>&1 || { echo "❌ Richiesto '$bin' non trovato"; exit 1; }
done

mkdir -p "$DATA_DIR"

# ========================
# Helpers
# ========================
num_or_zero() {
  local v="${1:-}"
  [[ -z "$v" || "$v" == "null" ]] && { echo 0; return; }
  awk -v x="$v" 'BEGIN{ if (x+0==x+0) print x; else print 0 }'
}

fix_decimal() {
  # forza formato decimale (no notazione scientifica)
  local v="${1:-0}" scale="${2:-8}"
  printf "%.${scale}f" "$v"
}

# ========================
# 1) Quantità BUMPER nel wallet (Helius)
# ========================
ASSETS_JSON=$(
  curl -sS -X POST "$API_RPC" -H "Content-Type: application/json" -d '{
    "jsonrpc":"2.0","id":"1","method":"getAssetsByOwner",
    "params":{
      "ownerAddress":"'"$WALLET"'",
      "page":1,"limit":1000,
      "options":{"showFungible":true,"showZeroBalance":false}
    }
  }'
)

read -r RAW_BAL DECIMALS <<<"$(
  echo "$ASSETS_JSON" | jq -r --arg M "$MINT_BUMPER" '
    (.result.items // [])[]
    | select(.id == $M)
    | "\(.token_info.balance) \(.token_info.decimals)"
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

# ========================
# 2) Prezzo BUMPER in USDC (Jupiter price API)
#    (NO quote-api: evita problemi DNS nel runner)
# ========================
JUP_PRICE_JSON=$(curl -sS --retry 3 --retry-delay 2 --max-time 60 \
  "https://price.jup.ag/v4/price?ids=$MINT_BUMPER&vsToken=USDC" || echo "")

RAW_PRICE=$(echo "$JUP_PRICE_JSON" \
  | jq -r --arg ID "$MINT_BUMPER" '.data[$ID].price // (.data[]?.price) // empty')

if [[ -z "$RAW_PRICE" ]]; then
  echo "❌ Nessun prezzo per BUMPER da price.jup.ag; interruzione per non scrivere 0."
  exit 1
fi

PRICE_USD_NUM=$(num_or_zero "$RAW_PRICE")
PRICE_USD=$(fix_decimal "$PRICE_USD_NUM" "$PRICE_SCALE")

# ========================
# 3) Valore totale USD
# ========================
TOTAL_VALUE_USD=$(echo "scale=$VALUE_SCALE; $QUANTITY * $PRICE_USD" | bc -l)
TOTAL_VALUE_USD=$(fix_decimal "$TOTAL_VALUE_USD" "$VALUE_SCALE")

# ========================
# 4) Output JSON (fixed-point, niente 0E-8)
# ========================
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq -n \
  --arg token "BUMPER" \
  --arg mint "$MINT_BUMPER" \
  --arg price "$PRICE_USD" \
  --arg qty "$QUANTITY" \
  --arg value "$TOTAL_VALUE_USD" \
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
echo "   price_usd=$PRICE_USD | qty=$QUANTITY | total_usd=$TOTAL_VALUE_USD"

