async function updateStatus() {
  const box = document.getElementById('status-box');
  const time = document.getElementById('timestamp');

  try {
    const res = await fetch('data/status.json', { cache: "no-store" });
    const data = await res.json();

    let label = "❓ Unknown";
    switch (data.status) {
      case 'swap_pending':
        label = '⏳ Waiting for swap...';
        break;
      case 'awaiting_transfer':
        label = '💱 Swap done – waiting for transfer';
        break;
      case 'transferred':
        label = '✅ TBTC received in vault';
        break;
    }

    box.innerText = label;
    time.innerText = `Last update: ${data.timestamp}`;
  } catch (e) {
    box.innerText = '⚠️ Error loading status';
    console.error(e);
  }
}

updateStatus();

