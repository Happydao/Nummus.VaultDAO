#!/usr/bin/env bash
set -euo pipefail

INPUT="data/prices.json"
OUTPUT="data/prices2.json"

for bin in jq awk bc; do
  command -v "$bin" >/dev/null 2>&1 || { echo "❌ Missing '$bin'"; exit 1; }
done

num_or_zero() {
  local v="${1:-}"
  [[ -z "$v" || "$v" == "null" ]] && { echo 0; return; }
  awk -v x="$v" 'BEGIN{ if (x+0==x+0) print x; else print 0 }'
}

fix_decimal() {
  local v="${1:-0}" scale="${2:-8}"
  printf "%.${scale}f" "$v"
}

# Estrai e sanifica
total_tbtc=$(num_or_zero "$(jq -r '.total_tbtc_balance // 0' "$INPUT")")
tbtc_price=$(num_or_zero "$(jq -r '.tbtc_price_usd // 0' "$INPUT")")
nummus_price=$(num_or_zero "$(jq -r '.nummus_price_usd // 0' "$INPUT")")

# Evita notazione scientifica
total_tbtc=$(fix_decimal "$total_tbtc" 12)
tbtc_price=$(fix_decimal "$tbtc_price" 12)
nummus_price=$(fix_decimal "$nummus_price" 12)

fraction="0.0001"

tbtc_for_10000=$(echo "scale=8; $total_tbtc * $fraction" | bc -l)
usd_value_of_that_tbtc=$(echo "scale=2; $tbtc_for_10000 * $tbtc_price" | bc -l)
usd_value_of_10000_nummus=$(echo "scale=2; 10000 * $nummus_price" | bc -l)

usd_value_of_that_tbtc=$(fix_decimal "$usd_value_of_that_tbtc" 2)
usd_value_of_10000_nummus=$(fix_decimal "$usd_value_of_10000_nummus" 2)

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
