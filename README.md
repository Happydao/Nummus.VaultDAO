$NUMMUS → tBTC Monitor
A dashboard tracking the accumulation of tBTC through $NUMMUS swaps on the Solana blockchain.

🔗 Live Monitor: https://happydao.github.io/Nummus.VaultDAO/

Features
Frozen snapshot of two key wallets

Swap Wallet: 3X7SW24GtQD3oGKoEhMpk54qqDoy3V7aGg31RdQKf4mh
Vault Wallet: HtT3yMsAavLQYmd6VSbXSdbAefyZUrrFeEPoTPivde3s

Displays tBTC balances, USD value, and the last 30 tBTC transfers (in/out)

Updates are paused during the community-approved transition from tBTC to Zcash (ZEC).
All data files are frozen at the last November 17, 2026 snapshot (UTC), from commit
`6ee2ffd5eda8d60949d8c95698c7825a3bb2cf68`. Later visits display these same values.
The original snapshot timestamps are preserved in `data/status.json` and `data/prices.json`.

The monitor workflow has no schedule and its job is disabled, including manual runs.
To resume collection after maintenance, explicitly remove the job's `if: ${{ false }}`
guard and restore the schedule only once the Zcash data pipeline is ready.

Governance
The Nummus Aeternitas Vault DAO is a decentralized vault governed via on-chain voting.

Voting on Realms: https://app.realms.today/dao/2Czvw7p29thfqNJznuicygBKxh33xoCMuGMH7zbPQ2gp
