const { chromium } = require('playwright-core');
const path = require('path');
(async () => {
  const url = process.argv[2], outDir = process.argv[3];
  const b = await chromium.launch({ headless: true });
  const ctx = await b.newContext({ acceptDownloads: true });
  const p = await ctx.newPage();
  let saved = null;
  p.on('download', async d => {
    const f = path.join(outDir, d.suggestedFilename());
    await d.saveAs(f); saved = f; console.log('  SAVED ' + f);
  });
  try {
    await p.goto(url, { waitUntil:'domcontentloaded', timeout:60000 });
    await p.waitForTimeout(4000);
    const c0 = await p.$('#onetrust-accept-btn-handler');
    if (c0) { await c0.click().catch(()=>{}); await p.waitForTimeout(1500); }
    for (const c of await p.$$('a,button')) {
      const t = ((await c.textContent().catch(()=>'')) || '').trim();
      if (/^download/i.test(t)) { await c.click({timeout:8000}).catch(()=>{}); await p.waitForTimeout(15000); break; }
    }
  } catch(e) { console.log('  err: '+e.message.split('\n')[0]); }
  if (!saved) console.log('  no download captured');
  await b.close();
})();
