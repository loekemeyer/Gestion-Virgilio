const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
// Raiz del repo (los tests viven en tests/ui/) y Chromium portable si existe.
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const BUNDLE = {
  sect: { '1': { tipo: 'crudo', nom: 'Sector Crudo' }, '2': { tipo: 'procesado', nom: 'Sector Procesado' },
          '10': { tipo: 'carton', nom: 'Sector Cartón' } },
  partes: [
    { id: 85, cod: 'A10', d: 'Cpo Una LK', s: 2 },
    { id: 90, cod: 'V9', d: 'Remache', s: 2 },
    { id: 99, cod: 'CART506', d: 'Carton 506', s: 10 },
  ],
  art: [
    { id: 1, cod: '506', fam: 'Pelapapas', por: 12, caja: null, caja_cod: null, caja_desc: null, est: 35000,
      comp: [ { cid: 85, cod: 'A10', d: 'Cpo Una LK', s: 2, um: 'unidad', q: 1, kg: 0.0177, uxc: 1695 },
              { cid: 90, cod: 'V9', d: 'Remache', s: 2, um: 'unidad', q: 2, kg: null, uxc: null } ] },
  ],
};

const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    window.__calls = (window.__calls||[]); window.__calls.push({name:name, args:args});
    if(name==='abm_articulos_bundle') return { data: ${JSON.stringify(BUNDLE)}, error: null };
    if(name==='abm_bom_guardar') return { data: { ok:true, articulo:'506', altas:1, cambios:1, bajas:1,
      avisos:['La parte X esta en la receta pero NINGUNA ruta del articulo la produce (completar ruta/ruta_paso).'] }, error: null };
    return { data: null, error: { message: 'rpc '+name } };
  },
  from: function(){ var o={}; ['select','eq','order','single'].forEach(m=>o[m]=()=>o);
    o.then=(res)=>Promise.resolve({data:[],error:null}).then(res); return o; }
};}};
`;

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const page = await browser.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });

  await page.route('**/@supabase/supabase-js@2', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/*.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));
  await page.route('**/*.css*', r => r.fulfill({ contentType: 'text/css', body: '' }));

  await page.goto(ROOT + '/Talleristas/ABM%20Articulos/ABM_Articulos_GP2.html');
  await page.waitForSelector('#art-506');

  const ok = (c, m) => { console.log((c?'OK  ':'FAIL')+' '+m); if(!c) process.exitCode = 1; };

  // abrir seccion y entrar a editar BOM
  await page.click('#art-506 .art-head');
  await page.click('button[data-act="bom"]');
  await page.waitForSelector('.bom-edit');
  ok(await page.$$eval('.bom-edit tbody tr', x => x.length) === 2, 'editor con 2 lineas');

  // cambiar cantidad de A10 a 3
  await page.fill('input[data-bq="0"]', '3');

  // agregar CART506
  await page.fill('#bomAdd', 'CART506');
  await page.click('button[data-act="bomadd"]');
  await page.waitForFunction(() => document.querySelectorAll('.bom-edit tbody tr').length === 3);
  ok(true, 'parte agregada (3 lineas)');
  ok(await page.$eval('input[data-bq="0"]', x => x.value) === '3', 'cantidad editada sobrevive el re-render');

  // sacar V9 (indice 1)
  await page.click('button[data-act="bomrm"][data-i="1"]');
  await page.waitForFunction(() => document.querySelectorAll('.bom-edit tbody tr').length === 2);

  // guardar
  await page.click('button[data-act="bomsave"]');
  await page.waitForFunction(() => (window.__calls||[]).some(c => c.name === 'abm_bom_guardar'));
  const call = await page.evaluate(() => window.__calls.filter(c => c.name === 'abm_bom_guardar')[0].args.p);
  ok(call.articulo_id === 1, 'articulo_id ok');
  ok(JSON.stringify(call.lineas) === JSON.stringify([{comp_id:85,cantidad:3},{comp_id:99,cantidad:1}]),
     'payload lineas ok: ' + JSON.stringify(call.lineas));

  await page.waitForFunction(() => document.getElementById('topMsg').textContent.includes('guardada'));
  const t = await page.textContent('#topMsg');
  ok(t.includes('1 altas, 1 cambios, 1 bajas') && t.includes('NORMALIZACIÓN'), 'mensaje con avisos de normalizacion');

  // duplicado rechazado (la seccion quedo abierta tras guardar)
  await page.click('button[data-act="bom"]');
  await page.waitForSelector('.bom-edit');
  await page.fill('#bomAdd', 'A10');
  await page.click('button[data-act="bomadd"]');
  ok((await page.textContent('#bomMsg')).includes('ya está'), 'duplicado rechazado');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
