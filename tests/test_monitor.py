import json, os, pathlib, subprocess, tempfile, unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MINT = 'A7bdiYdS5GjqGFtxf17ppRHtDKPkkRqbKtR27dxvQXaS'
MOCK = '''#!/usr/bin/env python3
import json,os,sys
args=sys.argv[1:]
mode=os.environ.get('FAIL','')
url=next(x for x in args if x.startswith('https://'))
if 'helius-rpc' in url:
 if mode=='balance': print('{"error":{"message":"unavailable"}}'); sys.exit()
 print(json.dumps({'result':{'value':[{'account':{'data':{'parsed':{'info':{'tokenAmount':{'amount':'250000000','decimals':8}}}}}}]}}))
elif '/transactions?' in url:
 if mode=='transactions': print('{"error":"unavailable"}'); sys.exit()
 if 'before=' in url: print('[]'); sys.exit()
 w='3X7SW24GtQD3oGKoEhMpk54qqDoy3V7aGg31RdQKf4mh'
 m='A7bdiYdS5GjqGFtxf17ppRHtDKPkkRqbKtR27dxvQXaS'
 print(json.dumps([{'signature':'swap','timestamp':1795305600,'tokenTransfers':[
 {'mint':m,'toUserAccount':w,'fromUserAccount':'pool','tokenAmount':3},
 {'mint':m,'fromUserAccount':w,'toUserAccount':'pool','tokenAmount':1},
 {'mint':'old-mint','toUserAccount':w,'fromUserAccount':'pool','tokenAmount':999}]},
 {'signature':'self','timestamp':1795305601,'tokenTransfers':[{'mint':m,'toUserAccount':w,'fromUserAccount':w,'tokenAmount':8}]}]))
elif 'dexscreener' in url:
 if mode=='price': print('[]'); sys.exit()
 print(json.dumps([{'chainId':'solana','baseToken':{'address':'wrong'},'priceUsd':'999','liquidity':{'usd':999999}}, {'chainId':'solana','baseToken':{'address':'A7bdiYdS5GjqGFtxf17ppRHtDKPkkRqbKtR27dxvQXaS'},'priceUsd':'100','liquidity':{'usd':1000}}]))
else: print('{"nummus-aeternitas":{"usd":0.01}}')
'''

class MonitorTests(unittest.TestCase):
 def run_monitor(self, failure=''):
  with tempfile.TemporaryDirectory() as tmp:
   p=pathlib.Path(tmp); (p/'bin').mkdir(); (p/'data').mkdir()
   for name in ('status.json','prices.json'): (p/'data'/name).write_text('{"original":true}')
   (p/'bin/curl').write_text(MOCK); (p/'bin/curl').chmod(0o755)
   (p/'bin/date').write_text('#!/bin/sh\ncase "$*" in *%F*) echo 2026-11-22;; *) echo 2026-11-22T12:00:00Z;; esac\n'); (p/'bin/date').chmod(0o755)
   result=subprocess.run(['bash',str(ROOT/'scripts/monitor.sh')],cwd=p,env={**os.environ,'PATH':str(p/'bin')+':'+os.environ['PATH'],'HELIUS_API_KEY':'fixture','FAIL':failure},capture_output=True,text=True)
   data={name:json.loads((p/'data'/name).read_text()) for name in ('status.json','prices.json')}
   return result,data
 def test_zec_only_and_net_transfers(self):
  r,d=self.run_monitor(); self.assertEqual(r.returncode,0,r.stderr)
  s=d['status.json']; self.assertEqual(s['mint'],MINT)
  self.assertEqual(s['wallet_1']['zec_balance'],2.5)
  self.assertEqual(s['wallet_1']['last_zec_transfers'][0]['amount'],'+2')
  self.assertEqual(len(s['wallet_1']['last_zec_transfers']),1)
  self.assertEqual(d['prices.json']['vault_zec_usd_value'],250)
 def test_failures_preserve_published_data(self):
  for mode in ('balance','transactions','price'):
   with self.subTest(mode=mode):
    r,d=self.run_monitor(mode); self.assertNotEqual(r.returncode,0)
    self.assertTrue(all(x=={'original':True} for x in d.values()))
 def test_frozen_archive(self):
  manifest=json.loads((ROOT/'data/archive/frozen-period.json').read_text())
  self.assertEqual(list(manifest['dates']),[f'2026-11-{d}' for d in range(17,22)])
  for name in ('status.json','prices.json'):
   original=subprocess.check_output(['git','show',f'6ee2ffd5:data/{name}'],cwd=ROOT)
   self.assertEqual((ROOT/'data/archive/2026-11-17'/name).read_bytes(),original)

if __name__=='__main__': unittest.main()
