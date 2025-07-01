#!/bin/bash
set -e

# Percorsi dei file
INPUT="data/prices.json"
OUTPUT="data/prices2.json"

# Estrai i valori dal JSON
total_tbtc=$(jq -r '.total_tbtc_balance' "$INPUT")
tbtc_price=$(jq -r '.tbtc_price_usd' "$INPUT")
nummus_price=$(jq -r '.nummus_price_usd' "$INPUT")

# Calcolo proporzione per 10.000 su 100 milioni (0.0001)
fraction=0.0001

# Calcoli
tbtc_for_10000=$(awk "BEGIN {printf \"%.8f\", $total_tbtc * $fraction}")
usd_value_of_that_tbtc=$(awk "BEGIN {printf \"%.2f\", $tbtc_for_10000 * $tbtc_price}")
usd_value_of_10000_nummus=$(awk "BEGIN {printf \"%.2f\", 10000 * $nummus_price}")

# Scrivi JSON senza punti nei nomi delle chiavi
jq -n \
  --arg tbtc "$tbtc_for_10000" \
  --arg usd_tbtc "$usd_value_of_that_tbtc" \
  --arg usd_nummus "$usd_value_of_10000_nummus" \
  '{
    tbtc_for_10000_nummus: ($tbtc | tonumber),
    usd_value_of_that_tbtc: ($usd_tbtc | tonumber),
    usd_value_of_10000_nummus: ($usd_nummus | tonumber)
  }' > "$OUTPUT"

echo "✅ Created $OUTPUT"
