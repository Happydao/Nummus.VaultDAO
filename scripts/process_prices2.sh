#!/bin/bash
set -e

# Percorso del file di input
INPUT_FILE="data/prices.json"
OUTPUT_FILE="data/prices2.json"

# Verifica che il file esista
if [ ! -f "$INPUT_FILE" ]; then
  echo "❌ File $INPUT_FILE non trovato!"
  exit 1
fi

# Estrai i valori dal file JSON
TBTC_PRICE_USD=$(jq -r '.tbtc_price_usd' "$INPUT_FILE")
NUMMUS_PRICE_USD=$(jq -r '.nummus_price_usd' "$INPUT_FILE")
TOTAL_TBTC_BALANCE=$(jq -r '.total_tbtc_balance' "$INPUT_FILE")

# Calcoli
TBTC_PER_1000_NUMMUS=$(awk "BEGIN { printf \"%.8f\", $TOTAL_TBTC_BALANCE / 100000 }")
USD_EQUIV_OF_TBTC_FOR_1000_NUMMUS=$(awk "BEGIN { printf \"%.2f\", $TBTC_PER_1000_NUMMUS * $TBTC_PRICE_USD }")
USD_VALUE_OF_1000_NUMMUS=$(awk "BEGIN { printf \"%.2f\", $NUMMUS_PRICE_USD * 1000 }")

# Salva tutto nel nuovo file JSON
jq -n \
  --arg tbtc_for_1000 "$TBTC_PER_1000_NUMMUS" \
  --arg usd_of_tbtc "$USD_EQUIV_OF_TBTC_FOR_1000_NUMMUS" \
  --arg usd_1000_nummus "$USD_VALUE_OF_1000_NUMMUS" \
  '{
    tbtc_for_1000_nummus: ($tbtc_for_1000 | tonumber),
    usd_value_of_that_tbtc: ($usd_of_tbtc | tonumber),
    usd_value_of_1000_nummus: ($usd_1000_nummus | tonumber)
  }' > "$OUTPUT_FILE"

echo "✅ prices2.json generato con successo:"
cat "$OUTPUT_FILE"
