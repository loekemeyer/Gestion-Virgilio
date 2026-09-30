/* Al tocar el Máximo en Generar OC se abre el desglose (RPC oc_maximo_desglose): meses,
   consumo, consumo×meses y la tabla de lo que lo arma. [usuario 2026-09-14: "al tocar en
   maximo, pueda ver de que se compone... que articulos y que venta... primero en unidades
   para despues pasarse a kilos"]. */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const base = { sector: 'Sector Fleje', sector_id: 5, proveedor: 'Basconia', um: 'kg', unidad: 'kg',
  kg_x_uni: 0.02, precio: 1, moneda: 'USD', maximo_origen: 'est_madre',
  carton_formato: null, pliegos_multiplo: null, codigo_multiplo: null, min_codigo_x_multiplo: null };

const BUNDLE = { paq: 250, ocs: [], pliego_uni_x_paquete: 100, tc: 1500, generado_en: '2026-09-14T10:00:00Z',
  insumos: [ Object.assign({ comp_id: 7, codigo: 'IF11', descripcion: 'Fleje N° 19',
      stock: 100, maximo: 1769, pendiente_oc: 0, sugerido: 1669 }, base) ] };

// Lo que devuelve la RPC del desglose para IF11 (fleje -> por articulo, con kg).
const DESGLOSE = {
  comp: { id: 7, codigo: 'IF11', descripcion: 'Fleje N° 19', sector_id: 5, unidad: 'kg', kg_x_uni: 0.02, es_resina: false, es_fleje: true },
  meses: 6, maximo: 1769, maximo_origen: 'est_madre', consumo_uni_mes: null, consumo_kg_mes: 294.9,
  desperdicio_pct: null, consumo_x_meses: 1769, base: 'articulos',
  filas: [ { cod: '505', desc: 'Pelador Mgo Plástico', venta_uni_mes: 27854, aporte_uni_mes: 27875, aporte_kg: 190.7 },
           { cod: '513', desc: 'Pelador Mgo Metálico', venta_uni_mes: 13586, aporte_uni_mes: 13658, aporte_kg: 93.44 } ],
  generado_en: '2026-09-14T10:00:00Z' };

const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name){
    if(name==='oc_bundle') return { data: ${JSON.stringify(BUNDLE)}, error: null };
    if(name==='oc_maximo_desglose') return { data: ${JSON.stringify(DESGLOSE)}, error: null };
    return { data: { ok:true }, error: null };
  }
};}};
`;

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const page = await browser.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  await page.route('**/@supabase/supabase-js@2', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/gp2-modulo.css**', r => r.fulfill({ contentType: 'text/css', body: '.hidden{display:none!important} [hidden]{display:none!important}' }));
  await page.route('**/GP2_favicon.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));
  await page.goto(ROOT + '/Compras/OC_GP2.html');
  await page.waitForFunction(() => document.getElementById('status').textContent === '');
  const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) process.exitCode = 1; };

  await page.click('#rubros .chip:has-text("Fleje")');
  ok(await page.$('td.max-cell') !== null, 'la celda Máximo tiene desglose (max-cell)');
  ok(await page.$eval('#dsgPop', x => x.hidden), 'la ventanita arranca oculta');

  // v1.36.0 [Thomas: "que me aparezca cuando me pongo arriba, sin tener que clickear"]
  await page.hover('td.max-cell');
  await page.waitForFunction(() => { const p = document.getElementById('dsgPop'); return !p.hidden && p.querySelector('table'); });
  const cuerpo = await page.textContent('#dsgPop');
  ok(/505/.test(cuerpo) && /Pelador Mgo Plástico/.test(cuerpo), 'al pasar el mouse lista el artículo que consume el insumo');
  ok(/27\.854/.test(cuerpo), 'muestra la venta (uni/mes) del artículo');
  ok(/190/.test(cuerpo), 'y los kg');
  // "solo esos datos. El resto no lo quiero"
  ok(!/Meses|Origen|Máximo|Consumo ×/.test(cuerpo), 'sin Máximo/Origen/Meses/Consumo × meses: ' + cuerpo.slice(0, 80));
  ok((await page.$$('#dsgPop table')).length === 1, 'una sola tabla');
  const fila1 = await page.$eval('#dsgPop tbody tr', x => x.textContent);
  ok(/505/.test(fila1), 'ordenado mayor → menor (505 primero)');

  await page.mouse.move(5, 5);
  ok(await page.$eval('#dsgPop', x => x.hidden), 'al salir de la celda se cierra');

  // v1.45.1 [Thomas: "que si hago click me quede fijo y lo saco haciendo un click afuera"]
  await page.click('td.max-cell');
  await page.waitForFunction(() => !document.getElementById('dsgPop').hidden);
  ok(await page.$eval('#dsgPop', x => x.classList.contains('fija') && getComputedStyle(x).pointerEvents === 'auto'), 'con mouse, el clic la fija y recibe el mouse');
  await page.mouse.move(5, 5);
  ok(!(await page.$eval('#dsgPop', x => x.hidden)), 'fijada, salir de la celda NO la cierra');
  await page.$eval('#dsgPop', x => { x.scrollTop = 20; x.dispatchEvent(new Event('scroll')); });
  ok(!(await page.$eval('#dsgPop', x => x.hidden)), 'scrollear adentro NO la cierra');
  await page.click('#dsgPop');
  ok(!(await page.$eval('#dsgPop', x => x.hidden)), 'clic adentro NO la cierra');
  await page.mouse.click(5, 5);
  ok(await page.$eval('#dsgPop', x => x.hidden && !x.classList.contains('fija')), 'clic afuera la cierra');

  // Tablet: sin hover, un toque la abre, otro la cierra, y tocar afuera tambien.
  await page.evaluate(() => document.querySelector('td.max-cell').click());
  await page.waitForFunction(() => { const p = document.getElementById('dsgPop'); return !p.hidden && p.querySelector('table'); });
  ok(true, 'tablet: el toque la abre');
  await page.evaluate(() => document.querySelector('td.max-cell').click());
  ok(await page.$eval('#dsgPop', x => x.hidden), 'tablet: el segundo toque la cierra');
  await page.evaluate(() => document.querySelector('td.max-cell').click());
  await page.evaluate(() => document.body.click());
  ok(await page.$eval('#dsgPop', x => x.hidden), 'tablet: tocar afuera la cierra');

  // v1.45.1 [Thomas: "hay mas blanco de un lado que de otro"]: con la tabla a la vista la tarjeta la abraza.
  const anchos = await page.evaluate(() => [document.querySelector('.card').getBoundingClientRect().width,
    document.querySelector('#panGen .table-wrap').getBoundingClientRect().width]);
  ok(anchos[0] - anchos[1] < 60, 'la tarjeta abraza la tabla (sin blanco de un solo lado): ' + anchos.map(Math.round).join(' vs '));

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
