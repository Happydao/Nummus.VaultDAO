async function updateDashboard() {
  const ts = document.getElementById("timestamp");

  const numusStatus = document.getElementById("numus-status");
  const numusBalance = document.getElementById("numus-balance");

  const vaultStatus = document.getElementById("vault-status");
  const vaultBalance = document.getElementById("vault-balance");

  try {
    const res = await fetch('data/status.json', { cache: "no-store" });
    const data = await res.json();

    // Stato testuale
    switch (data.status) {
      case 'swap_pending':
        numusStatus.innerText = '⏳ Waiting for swap...';
        break;
      case 'awaiting_transfer':
        numusStatus.innerText = '💱 Swap done – waiting transfer';
        break;
      case 'transferred':
        numusStatus.innerText = '✅ TBTC transferred from NUMUS';
        break;
      default:
        numusStatus.innerText = '❓ Unknown';
    }

    // Balance visuali
    if (data.numus_balance) {
      numusBalance.innerText = `${data.numus_balance} TBTC`;
    }
    if (data.vault_balance) {
      vaultBalance.innerText = `${data.vault_balance} TBTC`;
    }

    // Vault status
    if (data.vault_balance && parseFloat(data.vault_balance) > 0) {
      vaultStatus.innerText = '✅ TBTC present in vault';
    } else {
      vaultStatus.innerText = '🚫 No TBTC in vault';
    }

    ts.innerText = `Last update: ${data.timestamp}`;
  } catch (err) {
    numusStatus.innerText = vaultStatus.innerText = '⚠️ Error fetching data';
    console.error(err);
  }
}

updateDashboard();

