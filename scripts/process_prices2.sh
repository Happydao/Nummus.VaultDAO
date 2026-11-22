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

# Refuse the archived schema until the first successful ZEC collection.
jq -e '.asset == "ZEC" and .mint == "A7bdiYdS5GjqGFtxf17ppRHtDKPkkRqbKtR27dxvQXaS"' "$INPUT" >/dev/null

# Estrai e sanifica
total_zec=$(num_or_zero "$(jq -r '.vault_wallet_2.zec_balance // .wallet_2.zec_balance // 0' "$INPUT")")
zec_price=$(num_or_zero "$(jq -r '.zec_price_usd // 0' "$INPUT")")
nummus_price=$(num_or_zero "$(jq -r '.nummus_price_usd // 0' "$INPUT")")

# Evita notazione scientifica
total_zec=$(fix_decimal "$total_zec" 12)
zec_price=$(fix_decimal "$zec_price" 12)
nummus_price=$(fix_decimal "$nummus_price" 12)

fraction="0.0001"

zec_for_10000=$(echo "scale=8; $total_zec * $fraction" | bc -l)
usd_value_of_that_zec=$(echo "scale=2; $zec_for_10000 * $zec_price" | bc -l)
usd_value_of_10000_nummus=$(echo "scale=2; 10000 * $nummus_price" | bc -l)

usd_value_of_that_zec=$(fix_decimal "$usd_value_of_that_zec" 2)
usd_value_of_10000_nummus=$(fix_decimal "$usd_value_of_10000_nummus" 2)

jq -n \
  --arg zec "$zec_for_10000" \
  --arg usd_zec "$usd_value_of_that_zec" \
  --arg usd_nummus "$usd_value_of_10000_nummus" \
'{
  zec_for_10000_nummus: ($zec | tonumber),
  usd_value_of_that_zec: ($usd_zec | tonumber),
  usd_value_of_10000_nummus: ($usd_nummus | tonumber)
}' > "$OUTPUT"

echo "✅ Created $OUTPUT"
