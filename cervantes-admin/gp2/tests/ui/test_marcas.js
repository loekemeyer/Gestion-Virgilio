const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

/* LAS MARCAS SALEN DE LOS DATOS, NO DE UNA LISTA ESCRITA A MANO.
   [usuario 2026-09-03: "ciento cuatro es marca LOKE. No sé qué tan claro tenés
   qué es la marca LOKE, l-o-k-e. Es una submarca dentro de Loekemeyer"]

   Hasta ese día Recepción de Insumos tenía las marcas hardcodeadas en LOEKE y
   CHEF: un cartón con una marca distinta no entraba en ningún chip y
   DESAPARECÍA de la pantalla — ni siquiera caía en "Sin marca", porque ese chip
   filtra por marca vacía. Con la tercera marca real (LOKE) eso dejaba al Cartón
   104 imposible de recibir.

   Ojo con el choque de nombres: 'LOKE' es también un carton_formato. El formato
   dice cómo se imprime el pliego; la marca, de quién es el producto. */

const BUNDLE = {
  tara: { carton_uni_x_paquete: '250' },
  sectores: [{ id: 10, nombre: 'Sector Cartón' }],
  proveedores: [{ nombre: 'Talleres Gráficos Pol', modo_control: 'ninguno' }],
  recepciones: [], pallets: [], rollos: [],
  insumos: [
    { comp_id: 1, codigo: 'CCE2B', descripcion: 'Cartón 581', sector: 'Sector Cartón', sector_id: 10,
      um: 'unidad', proveedor: 'Talleres Gráficos Pol', marca: 'LOEKE', carton_formato: 'C',
      stock: 0, ultima: null, oc_pend: null },
    // El Cartón 104: marca LOKE, la submarca dentro de Loekemeyer.
    { comp_id: 2, codigo: 'K5D', descripcion: 'Cartón 104', sector: 'Sector Cartón', sector_id: 10,
      um: 'unidad', proveedor: 'Talleres Gráficos Pol', marca: 'LOKE', carton_formato: 'LOKE',
      stock: 0, ultima: null, oc_pend: null },
    { comp_id: 3, codigo: 'N1A', descripcion: 'Cartón Chef', sector: 'Sector Cartón', sector_id: 10,
      um: 'unidad', proveedor: 'Talleres Gráficos Pol', marca: 'CHEF', carton_formato: 'LOKE',
      stock: 0, ultima: null, oc_pend: null },
    // Y uno sin marca, que tiene que seguir cayendo en "Sin marca".
    { comp_id: 4, codigo: 'XX1', descripcion: 'Cartón huérfano', sector: 'Sector Cartón', sector_id: 10,
      um: 'unidad', proveedor: 'Talleres Gráficos Pol', marca: null, carton_formato: 'C',
      stock: 0, ultima: null, oc_pend: null },
  ],
};

const STUB = 'window.supabase={createClient:function(){return{'
  + 'rpc:async function(n){ if(n==="recepcion_bundle") return {data:' + JSON.stringify(BUNDLE) + ',error:null};'
  + ' return {data:{ok:true},error:null}; },'
  + 'from:function(){ var q={select:function(){return q;},'
  + 'in:function(){return Promise.resolve({data:[],error:null});}}; return q; }'
  + '};}};';

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) process.exitCode = 1; };

  await page.route(/supabase-js@2/, r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/auth-guard.js*', r => r.fulfill({ contentType: 'application/javascript', body: 'window.GP2_AUTH_ON=false;' }));
  await page.route('**/GP2_favicon.png*', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));

  await page.goto(ROOT + '/StockFlejes/RecepcionInsumos_GP2.html');
  await page.click('#rubroGrid button:has-text("Cartones")');
  await page.click('#provGrid button:has-text("Pol")');
  await page.click('#btnContinuar');
  await page.waitForSelector('#marcaChips .prov-btn');

  const chips = await page.$$eval('#marcaChips .prov-btn', xs => xs.map(x => x.textContent.trim()));
  ok(chips.length === 4, 'aparecen las 3 marcas + "Sin marca" (' + chips.join(' · ') + ')');
  ok(chips.some(c => /^LOKE\b/.test(c)),
     'LOKE tiene su propio chip: antes no existía y sus cartones desaparecían');
  ok(chips[0].startsWith('LOEKE') && chips[2].startsWith('CHEF'),
     'LOEKE y CHEF siguen primero y último, como estaban');
  ok(chips.some(c => c.startsWith('Sin marca')), 'y el que no tiene marca sigue cayendo en "Sin marca"');

  // Elegir LOKE tiene que mostrar SUS formatos y SU cartón, no vaciar la pantalla.
  await page.click('#marcaChips .prov-btn:text-matches("^LOKE")');
  await page.waitForTimeout(150);
  const fmts = await page.$$eval('#formatoChips .prov-btn', xs => xs.map(x => x.textContent.trim()));
  ok(fmts.length === 1 && fmts[0].startsWith('LOKE'),
     'una marca sin lista propia de formatos muestra los que realmente tiene (' + fmts.join(' · ') + ')');
  await page.click('#formatoChips .prov-btn');
  await page.waitForTimeout(150);
  const items = await page.$$eval('.item-btn', xs => xs.map(x => x.textContent));
  ok(items.length === 1 && items[0].includes('K5D'), 'y el Cartón 104 se puede recibir');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
