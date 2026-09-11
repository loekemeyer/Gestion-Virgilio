const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
// Raiz del repo (los tests viven en tests/ui/) y Chromium portable si existe.
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);
const BUNDLE = { dia:{uni:10,registros:2,empleados:1,matrices:1}, mes:{uni:100,registros:20,empleados:3,matrices:5},
  alertas: { disruptivas_mes: 0, matrices_sin_tiempo: 0, espejo_pend: 2,
    espejo_pend_detalle: [ { id: 2, motivo: 'alias desconocido: XX' }, { id: 1, motivo: 'articulo 999 inexistente' } ] } };
const STUB = `window.supabase={createClient:function(){return{rpc:async function(n){ return {data:${JSON.stringify(BUNDLE)},error:null}; }}}};`;
(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const page = await browser.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  await page.route('**/@supabase/supabase-js@2', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/auth-guard.js*', r => r.fulfill({ contentType: 'application/javascript', body: '' }));
  await page.route('**/version.js*', r => r.fulfill({ contentType: 'application/javascript', body: 'window.APP_VERSION="vTEST";' }));
  await page.route('**/*.css*', r => r.fulfill({ contentType: 'text/css', body: '' }));
  await page.route('**/*.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));
  // El aviso se mudo al menu: Inicio/index_GP2.html quedo como redirect.
  await page.goto(ROOT + '/GP2_MODULOS.html');
  // ya no hay banner: espero a que el menu termine de renderizar (delay corto).
  await page.waitForTimeout(500);
  const t = await page.textContent('body');
  const ok = (c,m)=>{ console.log((c?'OK  ':'FAIL')+' '+m); if(!c) process.exitCode=1; };
    ok(!/2 cargas de Virgilio SIN aplicar/.test(t), 'ya no aparece el banner espejo_pend (pedido usuario 2026-08-31)');
  const hay = await page.evaluate(()=>!!document.querySelector('#avisoEspejo')); ok(!hay, 'no existe #avisoEspejo en el DOM');
  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
