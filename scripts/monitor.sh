#!/usr/bin/env bash
set -euo pipefail
mkdir -p data
: "${HELIUS_API_KEY:?HELIUS_API_KEY is required}"
[[ "$(date -u +%F)" < "2026-11-22" ]] && { echo "ZEC monitoring starts November 22 UTC" >&2; exit 1; }
OUTPUT_DIR=$(mktemp -d)
trap 'rm -rf "$OUTPUT_DIR"' EXIT

# ------------ CONFIG ------------
WALLET1="3X7SW24GtQD3oGKoEhMpk54qqDoy3V7aGg31RdQKf4mh"  # swap wallet
WALLET2="HtT3yMsAavLQYmd6VSbXSdbAefyZUrrFeEPoTPivde3s"  # vault (solo ricevente)

MINT_ZEC="A7bdiYdS5GjqGFtxf17ppRHtDKPkkRqbKtR27dxvQXaS"

API_RPC="https://mainnet.helius-rpc.com/?api-key=$HELIUS_API_KEY"

# Profondità per wallet (solo WALLET2 molto profonda)
HELIUS_PAGES_W1=8
HELIUS_PAGES_W2=60
HELIUS_LIMIT=100
HELIUS_DELAY_SEC=0.25

# ------------ HELPERS ------------
get_balance() {
  local WALLET=$1 MINT=$2 OUTPUT
  OUTPUT=$(curl -fsS --retry 3 --retry-delay 2 --max-time 60 -X POST "$API_RPC" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg w "$WALLET" --arg m "$MINT" '{jsonrpc:"2.0",id:1,method:"getTokenAccountsByOwner",params:[$w,{mint:$m},{encoding:"jsonParsed",commitment:"finalized"}]}')") || return 1
  jq -e '.error == null and (.result.value | type == "array")' >/dev/null <<<"$OUTPUT" || return 1
  jq -r '[.result.value[].account.data.parsed.info.tokenAmount | (.amount | tonumber) / pow(10; .decimals)] | add // 0' <<<"$OUTPUT"
}

fetch_page() {
  local URL=$1
  local RES
  RES=$(curl -fsS --retry 3 --retry-delay 2 --max-time 60 "$URL") || return 1
  if jq -e 'type=="array"' >/dev/null 2>&1 <<<"$RES"; then
    echo "$RES"
  else
    echo "Invalid transaction response" >&2
    return 1
  fi
}

fetch_transactions() {
  local WALLET=$1
  local PAGES=$2
  local LIMIT=$3
  local DELAY=$4
  local ALL_TXS="[]"
  local LAST_SIG=""
  for ((i=1;i<=PAGES;i++)); do
    local URL="https://api.helius.xyz/v0/addresses/$WALLET/transactions?api-key=$HELIUS_API_KEY&limit=$LIMIT"
    [ -n "$LAST_SIG" ] && URL="$URL&before=$LAST_SIG"
    local PAGE; PAGE=$(fetch_page "$URL") || return 1
    if [ "$(jq 'length' <<<"$PAGE")" -eq 0 ]; then break; fi
    ALL_TXS=$(jq -s '[.[] | select(type=="array")] | add // []' <<<"$ALL_TXS $PAGE")
    LAST_SIG=$(jq -r '.[-1].signature // empty' <<<"$PAGE")
    [ -z "$LAST_SIG" ] && break
    sleep "$DELAY"
  done
  echo "$ALL_TXS"
}

parse_transfers() {
  local DATA="$1" WALLET="$2" MINT="$3"
  jq -c --arg M "$MINT" --arg W "$WALLET" '
    [ .[]? as $tx
      | ($tx.tokenTransfers // [])[]
      | select(.mint == $M and ((.toUserAccount // "") == $W or (.fromUserAccount // "") == $W))
      | select(.toUserAccount != .fromUserAccount)
      | {
          signature: $tx.signature,
          timestamp_num: (($tx.timestamp // 0) | tonumber),
          amount: ((if ((.toUserAccount // "") == $W) then "+" else "-" end)
                   + ((.tokenAmount | tonumber) | tostring))
        }
    ]
    | group_by(.signature)
    | map(.[0] as $first | (map(.amount | tonumber) | add) as $net
        | $first + {amount: ((if $net >= 0 then "+" else "" end) + ($net | tostring))})
    | map(select((.amount | tonumber) != 0))
    | sort_by(.timestamp_num) | reverse
    | .[:30]
    | map({signature, timestamp: (.timestamp_num | todateiso8601), amount})
  ' <<<"$DATA"
}

# ------------ BILANCI ------------
ZEC_BAL_W1=$(get_balance "$WALLET1" "$MINT_ZEC")
ZEC_BAL_W2=$(get_balance "$WALLET2" "$MINT_ZEC")

# ------------ TRANSAZIONI ------------
XFERS_W1=$(fetch_transactions "$WALLET1" "$HELIUS_PAGES_W1" "$HELIUS_LIMIT" "$HELIUS_DELAY_SEC")
XFERS_W2=$(fetch_transactions "$WALLET2" "$HELIUS_PAGES_W2" "$HELIUS_LIMIT" "$HELIUS_DELAY_SEC")

XFERS_W1_DEDUP=$(echo "$XFERS_W1" | jq 'unique_by(.signature)')
XFERS_W2_DEDUP=$(echo "$XFERS_W2" | jq 'unique_by(.signature)')
MERGED_WALLETS=$(jq -s '[.[] | select(type=="array")] | add // [] | unique_by(.signature)' \
  <<<"$XFERS_W1_DEDUP $XFERS_W2_DEDUP")

LAST_ZEC_W1=$(parse_transfers "$MERGED_WALLETS" "$WALLET1" "$MINT_ZEC")
LAST_ZEC_W2=$(parse_transfers "$MERGED_WALLETS" "$WALLET2" "$MINT_ZEC")

# ------------ PREZZI ------------
PRICE_ZEC=$(curl -fsS --retry 3 --retry-delay 2 --max-time 60 \
  "https://api.dexscreener.com/tokens/v1/solana/$MINT_ZEC" \
  | jq -er --arg m "$MINT_ZEC" '[.[] | select(.chainId == "solana" and .baseToken.address == $m) | select((.priceUsd | tonumber? // 0) > 0)] | sort_by(.liquidity.usd // 0) | last | .priceUsd | tonumber | select(. > 0)')

PRICE_NUMMUS=$(curl -fsS --retry 3 --retry-delay 2 --max-time 60 \
  "https://api.coingecko.com/api/v3/simple/price?ids=nummus-aeternitas&vs_currencies=usd" \
  | jq -er '."nummus-aeternitas".usd | numbers | select(. > 0)')

# ------------ VALORI USD ------------
VALUE_W1=$(jq -nr --argjson b "$ZEC_BAL_W1" --argjson p "$PRICE_ZEC" '$b * $p * 100 | round / 100')
VALUE_W2=$(jq -nr --argjson b "$ZEC_BAL_W2" --argjson p "$PRICE_ZEC" '$b * $p * 100 | round / 100')

# ------------ OUTPUT JSON (compatibile con index) ------------
jq -n \
  --arg zec1 "$ZEC_BAL_W1" \
  --arg last1 "$LAST_ZEC_W1" \
  --arg zec2 "$ZEC_BAL_W2" \
  --arg last2 "$LAST_ZEC_W2" \
  --arg val1 "$VALUE_W1" \
  --arg val2 "$VALUE_W2" \
  --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg mint "$MINT_ZEC" \
  '{
    asset: "ZEC", mint: $mint,
    wallet_1: {
      zec_balance: ($zec1 | tonumber),
      zec_usd_value: ($val1 | tonumber),
      last_zec_transfers: ($last1 | try fromjson catch [])
    },
    vault_wallet_2: {
      zec_balance: ($zec2 | tonumber),
      zec_usd_value: ($val2 | tonumber),
      last_zec_transfers: ($last2 | try fromjson catch [])
    },
    timestamp: $time
  }' > "$OUTPUT_DIR/status.json"

jq -n \
  --arg price "$PRICE_ZEC" \
  --arg nummus "$PRICE_NUMMUS" \
  --arg w1_bal "$ZEC_BAL_W1" \
  --arg w1_val "$VALUE_W1" \
  --arg w2_bal "$ZEC_BAL_W2" \
  --arg w2_val "$VALUE_W2" \
  --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg mint "$MINT_ZEC" \
  '{
    asset: "ZEC", mint: $mint, price_source: "dexscreener",
    zec_price_usd: ($price | tonumber),
    nummus_price_usd: ($nummus | tonumber),
    wallet_1: {
      zec_balance: ($w1_bal | tonumber),
      zec_usd_value: ($w1_val | tonumber)
    },
    wallet_2: {
      zec_balance: ($w2_bal | tonumber),
      zec_usd_value: ($w2_val | tonumber)
    },
    vault_zec_usd_value: ($w2_val | tonumber),
    timestamp: $time
  }' > "$OUTPUT_DIR/prices.json"

# Publish only after every request and both JSON outputs have succeeded.
mv "$OUTPUT_DIR/status.json" data/status.json
mv "$OUTPUT_DIR/prices.json" data/prices.json
