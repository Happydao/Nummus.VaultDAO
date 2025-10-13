#!/usr/bin/env bash
set -euo pipefail

# =========================
# Config
# =========================
: "${HELIUS_API_KEY:?HELIUS_API_KEY non impostata}"
API_RPC="https://mainnet.helius-rpc.com/?api-key=$HELIUS_API_KEY"

WALLET="HtT3yMsAavLQYmd6VSbXSdbAefyZUrrFeEPoTPivde3s"  # Wallet 2
MINT_BUMPER="5bp5PwTyu4i1hGyQsRwRYqiR2CmxyHt2cPJGEbXEbonk"

DATA_DIR="data"
OUT_FILE="$DATA_DIR/onothers_token.json"

# Precisioni di calcolo
QTY_SCALE=12        # decimali per la quantità
PRICE_SCALE=12      # decimali per il prezzo
VALUE_SCALE=2       # decimali per il valore totale in USD

# =========================
# Prerequisiti
# =========================
for bin in curl jq bc awk; do
  command -v "$bin" >/dev/null 2>&1 || { echo "❌ Richiesto '$bin' non trovato"; exit 1; }
done

mkdir -p "$DATA_DIR"

# =========================
# Funzioni di utilità
# =========================
num_or_zero() {
  # Stampa 0 se la stringa è vuota o non numerica
  local v="${1:-}"
  if [[ -z "$v" ]]; then echo "0"; return; fi
  # consenti notazione scientifica
  if awk "BEGIN{exit(!('$v'+0==('$v'+0)))}"; then
    echo "$v"
  else
    echo "0"
  fi
}

# =========================
# 1) Ottieni saldo e decimali del token dal wallet (Helius)
# =========================
ASSETS_JSON=$(curl -sS -X POST "$API_RPC" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0","id":"1","method":"getAssetsByOwner",
    "params":{
      "ownerAddress":"'"$WALLET"'",
      "page":1,"limit":1000,
      "options":{"showFungible":true,"showZeroBalance":false}
    }
  }')

# Estrai balance Grezzo (intero) e decimals
read -r RAW_BAL DECIMALS <<<"$(
  echo "$ASSETS_JSON" | jq -r --arg M "$MINT_BUMPER" '
    .result.items[]? | select(.id == $M) |
    "\(.token_info.balance) \(.token_info.decimals)"
  ' 2>/dev/null || echo ""
)"

RAW_BAL=$(num_or_zero "$RAW_BAL")
DECIMALS=${DECIMALS:-0}

# Calcola quantità = balance / (10^decimals) usando bc per evitare problemi di potenza in awk
if [[ "$RAW_BAL" != "0" && "$DECIMALS" =~ ^[0-9]+$ ]]; then
  QUANTITY=$(echo "scale=$QTY_SCALE; ($RAW_BAL) / (10 ^ $DECIMALS)" | bc -l)
else
  QUANTITY=$(printf "%.*f" "$QTY_SCALE" 0)
fi

# Normalizza rimuovendo zeri finali inutili ma lasciando almeno 1 zero dopo il punto se necessario
QUANTITY=$(awk -v q="$QUANTITY" 'BEGIN{
  if (index(q,".")==0){print q; exit}
  sub(/0+$/,"",q); sub(/\.$/,".0",q); print q
}')

# =========================
# 2) Prezzo da Jupiter (in USDC)
# =========================
PRICE_JSON=$(curl -sS "https://price.jup.ag/v4/price?ids=$MINT_BUMPER&vsToken=USDC" || echo "")
# Prova chiave diretta .data[MINT].price, poi fallback al primo elemento
BUMPER_PRICE=$(echo "$PRICE_JSON" | jq -r --arg ID "$MINT_BUMPER" '
  (.data[$ID].price // (.data[]?.price) // 0)
' 2>/dev/null || echo "0")

BUMPER_PRICE=$(num_or_zero "$BUMPER_PRICE")

# Riformatta prezzo con precisione controllata (evita notazione scientifica)
# ATTENZIONE: non arrotondiamo a 2 decimali, manteniamo alta precisione per prezzi piccoli.
BUMPER_PRICE_FMT=$(printf "%.${PRICE_SCALE}f" "$BUMPER_PRICE" 2>/dev/null || echo "0")

# =========================
# 3) Valore totale (USD) quantità * prezzo
# =========================
VALUE_USD=$(echo "scale=$VALUE_SCALE; ($QUANTITY) * ($BUMPER_PRICE)" | bc -l)
# forza formato con due decimali
VALUE_USD=$(printf "%.${VALUE_SCALE}f" "$VALUE_USD")

# =========================
# 4) Output JSON
# =========================
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq -n \
  --arg token "BUMPER" \
  --arg mint "$MINT_BUMPER" \
  --arg price "$BUMPER_PRICE_FMT" \
  --arg qty "$QUANTITY" \
  --arg value "$VALUE_USD" \
  --arg time "$TIMESTAMP" \
'{
  token: $token,
  mint: $mint,
  price_usd: ($price | tonumber),
  quantity: ($qty | tonumber),
  total_value_usd: ($value | tonumber),
  timestamp: $time
}' > "$OUT_FILE"

echo "✅ Salvato in $OUT_FILE"

