const fs=require('fs'),vm=require('vm'),assert=require('assert');
const html=fs.readFileSync('index.html','utf8');
const script=html.match(/<script>([\s\S]*?)<\/script>/)[1];
const mint='A7bdiYdS5GjqGFtxf17ppRHtDKPkkRqbKtR27dxvQXaS';
async function render(legacy){
 const elements=new Map();
 const wallet={zec_balance:2.5,zec_usd_value:250,last_zec_transfers:[{timestamp:'2026-11-22T12:00:00Z',amount:'+2'}]};
 vm.runInNewContext(script,{document:{getElementById(id){if(!elements.has(id))elements.set(id,{});return elements.get(id)},querySelector(){return null}},window:{addEventListener(){}},console:{error(){}},fetch:async url=>({ok:true,json:async()=>legacy?JSON.parse(fs.readFileSync('data/archive/2026-11-17/'+url.split('/').pop(),'utf8')):{asset:'ZEC',mint,timestamp:'2026-11-22T12:00:00Z',zec_price_usd:100,nummus_price_usd:0.01,vault_zec_usd_value:250,wallet_1:wallet,vault_wallet_2:wallet}})});
 await new Promise(setImmediate);return elements;
}
(async()=>{
 const live=await render(false);
 assert.match(live.get('swap-balance').textContent,/2.50000000 ZEC/);
 assert.match(live.get('vault-balance').innerHTML,/images\/zcash.png/);
 assert.match(live.get('timestamp').innerHTML,/Last update: 2026-11-22/);
 const waiting=await render(true);
 assert.match(waiting.get('timestamp').textContent,/Awaiting the first ZEC update/);
 assert(!waiting.has('swap-balance'));
 assert(!/tbtc/i.test(html));
 assert(fs.existsSync('images/zcash.png'));
 console.log('PASS: ZEC figures and image render; legacy snapshot is never relabeled; no tBTC copy remains.');
})();
