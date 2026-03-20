#!/usr/bin/env bash
set -euo pipefail

# ========================
# Config
# ========================
: "${HELIUS_API_KEY:?HELIUS_API_KEY non impostata}"
API_RPC="https://mainnet.helius-rpc.com/?api-key=$HELIUS_API_KEY"

# Wallet & mint (PISTA su Solana)
WALLET="HtT3yMsAavLQYmd6VSbXSdbAefyZUrrFeEPoTPivde3s"
MINT_BUMPER="9CaQUthsVMugZzMvskrrvcHXyjFqHGdNtGkPT8QSRACE"
MINT_PUNCHY="GnYufMbTAMz1DzkSN2DmwkBzjMTLkM22WvQuN1VCbonk"

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
# Fetch assets una sola volta (PISTA + PUNCHY)
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

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ========================
# Funzione generica per leggere quantità da ASSETS_JSON
# ========================
get_quantity_for_mint() {
  local MINT="$1"
  local RAW_BAL DECIMALS TOKEN_ACCOUNTS_JSON RAW_SUM

  read -r RAW_BAL DECIMALS <<<"$(
    echo "$ASSETS_JSON" | jq -r --arg M "$MINT" '
      (.result.items // [])[]
      | select(.id == $M)
      | "\(.token_info.balance) \(.token_info.decimals)"
    ' | head -n1
  )"

  RAW_BAL=$(num_or_zero "$RAW_BAL")
  DECIMALS=${DECIMALS:-0}

  local QTY
  if [[ "$RAW_BAL" != 0 && "$DECIMALS" =~ ^[0-9]+$ ]]; then
    QTY=$(echo "scale=$QTY_SCALE; $RAW_BAL / (10 ^ $DECIMALS)" | bc -l)
  else
    TOKEN_ACCOUNTS_JSON=$(
      curl -sS -X POST "$API_RPC" -H "Content-Type: application/json" -d '{
        "jsonrpc":"2.0","id":"1","method":"getTokenAccountsByOwner",
        "params":[
          "'"$WALLET"'",
          {"mint":"'"$MINT"'"},
          {"encoding":"jsonParsed"}
        ]
      }'
    )

    read -r RAW_SUM DECIMALS <<<"$(
      echo "$TOKEN_ACCOUNTS_JSON" | jq -r '
        [
          .result.value[]?.account.data.parsed.info.tokenAmount.amount // "0"
        ] as $amounts
        |
        (($amounts | map(tonumber) | add) // 0 | tostring) + " " +
        ((.result.value[0]?.account.data.parsed.info.tokenAmount.decimals // 0) | tostring)
      '
    )"

    RAW_SUM=$(num_or_zero "$RAW_SUM")
    if [[ "$RAW_SUM" != 0 && "$DECIMALS" =~ ^[0-9]+$ ]]; then
      QTY=$(echo "scale=$QTY_SCALE; $RAW_SUM / (10 ^ $DECIMALS)" | bc -l)
    else
      QTY=$(printf "%.*f" "$QTY_SCALE" 0)
    fi
  fi
  fix_decimal "$QTY" "$QTY_SCALE"
}

# ========================
# Funzione generica per il prezzo via Jupiter
# ========================
get_price_for_mint() {
  local MINT="$1"

  local JUP_PRICE_JSON DS_JSON RAW_PRICE PRICE_USD_NUM
  JUP_PRICE_JSON=$(curl -sS --retry 3 --retry-delay 2 --max-time 60 \
    "https://price.jup.ag/v4/price?ids=$MINT&vsToken=USDC" || echo "")

  RAW_PRICE=$(echo "$JUP_PRICE_JSON" \
    | jq -r --arg ID "$MINT" '.data[$ID].price // (.data[]?.price) // empty')

  if [[ -z "$RAW_PRICE" ]]; then
    DS_JSON=$(curl -sS --retry 3 --retry-delay 2 --max-time 60 \
      "https://api.dexscreener.com/latest/dex/tokens/$MINT" || echo "")

    RAW_PRICE=$(echo "$DS_JSON" | jq -r '
      (.pairs // [])
      | map(select(.chainId == "solana"))
      | sort_by((.liquidity.usd // 0) | tonumber)
      | last
      | .priceUsd // empty
    ')
  fi

  if [[ -z "$RAW_PRICE" ]]; then
    echo "❌ Nessun prezzo per $MINT da Jupiter o DexScreener; interruzione per non scrivere 0."
    exit 1
  fi

  PRICE_USD_NUM=$(num_or_zero "$RAW_PRICE")
  fix_decimal "$PRICE_USD_NUM" "$PRICE_SCALE"
}

# ========================
# 1) PISTA (stesso flusso di prima, stessi campi nel JSON)
# ========================
QUANTITY_BUMPER=$(get_quantity_for_mint "$MINT_BUMPER")
PRICE_BUMPER_USD=$(get_price_for_mint "$MINT_BUMPER")

TOTAL_VALUE_BUMPER_USD=$(echo "scale=$VALUE_SCALE; $QUANTITY_BUMPER * $PRICE_BUMPER_USD" | bc -l)
TOTAL_VALUE_BUMPER_USD=$(fix_decimal "$TOTAL_VALUE_BUMPER_USD" "$VALUE_SCALE")

# ========================
# 2) PUNCHY (stessi dati: qty, prezzo, valore)
# ========================
QUANTITY_PUNCHY=$(get_quantity_for_mint "$MINT_PUNCHY")
PRICE_PUNCHY_USD=$(get_price_for_mint "$MINT_PUNCHY")

TOTAL_VALUE_PUNCHY_USD=$(echo "scale=$VALUE_SCALE; $QUANTITY_PUNCHY * $PRICE_PUNCHY_USD" | bc -l)
TOTAL_VALUE_PUNCHY_USD=$(fix_decimal "$TOTAL_VALUE_PUNCHY_USD" "$VALUE_SCALE")

# ========================
# 3) Output JSON
#    ⚠ I campi legacy "bumper" restano identici a prima.
#    PUNCHY è aggiunto sotto la chiave "punchy".
# ========================
jq -n \
  --arg token "PISTA" \
  --arg mint "$MINT_BUMPER" \
  --arg price "$PRICE_BUMPER_USD" \
  --arg qty "$QUANTITY_BUMPER" \
  --arg value "$TOTAL_VALUE_BUMPER_USD" \
  --arg time "$TIMESTAMP" \
  --arg p_token "PUNCHY" \
  --arg p_mint "$MINT_PUNCHY" \
  --arg p_price "$PRICE_PUNCHY_USD" \
  --arg p_qty "$QUANTITY_PUNCHY" \
  --arg p_value "$TOTAL_VALUE_PUNCHY_USD" '
{
  token: $token,
  mint: $mint,
  price_usd: ($price | tonumber),
  quantity: ($qty | tonumber),
  total_value_usd: ($value | tonumber),
  timestamp: $time,
  punchy: {
    token: $p_token,
    mint: $p_mint,
    price_usd: ($p_price | tonumber),
    quantity: ($p_qty | tonumber),
    total_value_usd: ($p_value | tonumber)
  }
}' > "$OUT_FILE"

echo "✅ Salvato $OUT_FILE"
echo "   PISTA: price_usd=$PRICE_BUMPER_USD | qty=$QUANTITY_BUMPER | total_usd=$TOTAL_VALUE_BUMPER_USD"
echo "   PUNCHY: price_usd=$PRICE_PUNCHY_USD | qty=$QUANTITY_PUNCHY | total_usd=$TOTAL_VALUE_PUNCHY_USD"
