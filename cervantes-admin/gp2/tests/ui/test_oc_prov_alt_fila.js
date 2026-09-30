/* v1.48.0: el alternativo es una fila repetida sin precio (antes, v1.45.1: boton con precio).
   v1.45.1 [Thomas 2026-09-29: "en sector caja, salvo que toque Recicor, no me aparece. Que me aparezca
   la opcion de comprarselo a ellos"]: sin proveedor elegido, la fila muestra el alternativo como boton,
   con su precio, y tocarlo elige ese proveedor. */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const caja = (id, cod, desc, max, alt) => ({ comp_id: id, codigo: cod, descripcion: desc, sector: 'Sector Caja', sector_id: 11,
  proveedor: 'Corrugadora del Plata', proveedores_alt: alt ? ['Recicor'] : [], um: 'unidad', unidad: 'uni', kg_x_uni: null,
  stock: 0, maximo: max, sugerido: max, pendiente_oc: 0, precio: 245.53, moneda: 'ARS', maximo_origen: 'est_madre',
  precios_prov: Object.assign({ 'Corrugadora del Plata': { moneda: 'ARS', precio: 245.53 } }, alt ? { Recicor: { moneda: 'ARS', precio: 199 } } : {}),
  carton_formato: null, pliegos_multiplo: null, codigo_multiplo: null, min_codigo_x_multiplo: null });
const BUNDLE = { paq: 250, ocs: [], pliego_uni_x_paquete: 100, tc: 1500, generado_en: '2026-09-29T10:00:00Z',
  insumos: [caja(456, 'A1', 'Caja N°1', 12738, true), caja(605, 'A7B', 'Caja N°16', 12, false)] };
const STUB = `window.supabase = { createClient: function(){ return {
  rpc: async function(name){ if(name==='oc_bundle') return { data: ${JSON.stringify(BUNDLE)}, error: null };
    return { data: {}, error: null }; } };}};`;

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const page = await browser.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  await page.route('**/@supabase/supabase-js@2', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/GP2_favicon.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));
  await page.goto(ROOT + '/Compras/OC_GP2.html');
  await page.waitForFunction(() => document.getElementById('status').textContent === '');
  const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) process.exitCode = 1; };

  await page.click('#rubros .chip:has-text("Caja")');
  // v1.48.0 [Thomas 2026-09-30]: sin precios en esta pantalla; el alternativo es la fila repetida.
  const filas = await page.$$eval('#tbody tr[data-id], #tbody tr.fila-alt', t => t.map(r => r.cells[0].querySelector('b').textContent + '|' + r.cells[1].textContent));
  ok(JSON.stringify(filas) === JSON.stringify(['A1|Corrugadora del Plata', 'A1|Recicor', 'A7B|Corrugadora del Plata']), 'A1 repetida a nombre de Recicor: ' + JSON.stringify(filas));
  ok(!/\$/.test(await page.textContent('#tbody')), 'la tabla no muestra precios');
  ok((await page.$$('tr.fila-alt input')).length === 0, 'la fila repetida no tiene campo Pedir');
  await page.click('tr.fila-alt');
  ok(await page.$eval('#provs .chip.active', x => x.textContent) === 'Recicor', 'tocarla elige Recicor arriba');
  ok((await page.$$('tr.fila-alt')).length === 0, 'con proveedor elegido no se repite nada');
  ok(/Recicor/.test(await page.textContent('#tbody tr td:nth-child(2)')), 'la fila queda a nombre de Recicor');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
