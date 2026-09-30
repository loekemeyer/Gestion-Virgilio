// v1.209.0 (Luis 2026-09-30): la portada muestra "VIRGILIO DICE QUE TE LLEGO ESTO" con lo pendiente de
// GP2.ingreso_virgilio, y no muestra nada si no hay pendientes o si la lectura falla.
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);
const FILAS = [{ id: 1, creado_en: '2026-09-30T15:00:00Z', cod_importado: '1000900', cod_insumo: 'H201Part', descripcion: 'Espiral TN',
  cantidad: 20000, unidad: 'unidades', proveedor: 'Hugo Wong', pedido_ref: 'PI-77', nota: null }];
const stub = (modo) => `window.supabase={createClient:function(){
  var q={select:function(){return q},eq:function(c,v){q._eq=[c,v];return q},order:function(){return q},
    then:function(res){ ${modo === 'error' ? "return Promise.resolve({data:null,error:{message:'x'}}).then(res);" : `return Promise.resolve({data:(q._eq&&q._eq[1]==='pendiente')?${modo === 'vacio' ? '[]' : JSON.stringify(FILAS)}:[],error:null}).then(res);`} }};
  return{rpc:async function(){return{data:null,error:null}},from:function(t){q._t=t;return q}};}};`;
const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) process.exitCode = 1; };
(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  for (const modo of ['con', 'vacio', 'error']) {
    const page = await browser.newPage();
    page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
    await page.route('**/@supabase/supabase-js@2', r => r.fulfill({ contentType: 'application/javascript', body: stub(modo) }));
    await page.route('**/auth-guard.js*', r => r.fulfill({ contentType: 'application/javascript', body: '' }));
    await page.route('**/*.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));
    await page.goto(ROOT + '/GP2_MODULOS.html');
    await page.waitForTimeout(400);
    const r = await page.evaluate(() => { const b = document.getElementById('avisoVirgilio'); return { hidden: b.hidden, t: b.textContent }; });
    if (modo === 'con') {
      ok(!r.hidden, 'con pendientes el cartel se ve');
      ok(/VIRGILIO DICE QUE TE LLEGÓ ESTO/.test(r.t) && /CONFIRMALO Y UBICALO/.test(r.t), 'dice VIRGILIO DICE QUE TE LLEGÓ ESTO — CONFIRMALO Y UBICALO');
      ok(/20\.000 unidades de H201Part/.test(r.t) && /Hugo Wong/.test(r.t) && /PI-77/.test(r.t) && /importado 1000900/.test(r.t), 'detalle: cantidad, insumo, proveedor, pedido e importado (' + r.t.slice(0, 160) + ')');
    } else ok(r.hidden, 'sin pendientes / con error de lectura el cartel NO se ve (' + modo + ')');
    await page.close();
  }
  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
