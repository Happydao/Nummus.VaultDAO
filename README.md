# NUMMUS → ZEC Monitor

Dashboard: https://happydao.github.io/Nummus.VaultDAO/

Tracks Zcash (ZEC) accumulation and swap-related transfers on Solana from November 22, 2026 (UTC).

- Mint: `A7bdiYdS5GjqGFtxf17ppRHtDKPkkRqbKtR27dxvQXaS`
- Swap wallet: `3X7SW24GtQD3oGKoEhMpk54qqDoy3V7aGg31RdQKf4mh`
- Vault wallet: `HtT3yMsAavLQYmd6VSbXSdbAefyZUrrFeEPoTPivde3s`

Shows ZEC balances, USD values and the latest 30 transactions involving the selected mint per wallet. Multiple transfers in a transaction are summed to the wallet's net flow. The transaction list can include ZEC transfers made during the transition; resuming observations on November 22 does not change their on-chain timestamps.

The hourly GitHub workflow runs `scripts/monitor.sh` using the existing `HELIUS_API_KEY` secret. A push changing the monitor script or workflow also starts a collection; manual runs are available. ZEC is priced using the highest-liquidity DEX Screener pool with this exact Solana base mint. NUMMUS uses CoinGecko. Failed balance, transaction or price requests leave the published snapshot unchanged.

## Frozen history

`data/archive/frozen-period.json` maps November 17–21 inclusive to the original November 17, 2026 18:55:48 UTC snapshot. The archived status and prices retain their original asset and values. The collector never writes this archive. This dashboard has no daily chart; the separate NAV dashboard manages its own daily history.

Until the first successful ZEC collection, the page shows a waiting message rather than relabeling the legacy balances. Live JSON fields use `zec_balance`, `zec_usd_value`, `last_zec_transfers`, `zec_price_usd`, and `vault_zec_usd_value`, with `asset` and `mint` metadata. Downstream consumers must use the ZEC fields.

After successful collection and commit, the existing NAV workflow dispatch runs using `NAV_DISPATCH_TOKEN`.

Governance: https://app.realms.today/dao/2Czvw7p29thfqNJznuicygBKxh33xoCMuGMH7zbPQ2gp

Run offline regression checks with `python3 tests/test_monitor.py` and `node tests/dashboard.cjs`.
