/* Caracterizacion de Talleristas/Control Tall/ControlTalleristas_GP2.html (previo a
   la unificacion): fija exclusion de Fabrica, modo Todos, derivados kg/caj del
   online y KPIs. Solo lectura. */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const BUNDLE = {
  tall: [
    { id: 6, nombre: 'Martin', cod_prov: '44' },
    { id: 7, nombre: 'Carlos', cod_prov: '45' },
    { id: 3, nombre: 'Fabrica', cod_prov: null },
  ],
  partes: {
    '6': { entrada: [
      { comp_id: 70, cod: 'A10', desc: 'Cpo Una', sector: 'D1', uni_x_cajon: 1000, kg_x_uni: 0.02,
        online_tall: 500, enviado: 800, entregado: 200, devuelto: 100, saldo: 500 },
      { comp_id: 70, cod: 'A10', desc: 'Cpo Una', sector: 'D1', uni_x_cajon: 1000, kg_x_uni: 0.02,
        online_tall: 500, enviado: 800, entregado: 200, devuelto: 100, saldo: 500 },
    ], salida: [] },
    '7': { entrada: [
      { comp_id: 71, cod: 'C10', desc: 'Cpo Saca', sector: 'D2', uni_x_cajon: null, kg_x_uni: null,
        online_tall: 50, enviado: 0, entregado: 60, devuelto: 0, saldo: -60 },
    ], salida: [] },
    '3': { entrada: [
      { comp_id: 72, cod: 'X1', desc: 'Interno', sector: 'D3', uni_x_cajon: 1, kg_x_uni: 1,
        online_tall: 1, enviado: 1, entregado: 1, devuelto: 0, saldo: 0 },
    ], salida: [] },
  },
};

const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    window.__calls = window.__calls || [];
    window.__calls.push({name:name, args:args});
    if(name==='talleristas_bundle') return { data: ${JSON.stringify(BUNDLE)}, error: null };
    return { data: null, error: { message: 'rpc desconocida '+name } };
  }
};}};
`;

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const page = await browser.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });

  await page.route('**/@supabase/supabase-js@2**', r =>
    r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/GP2_favicon.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));

  await page.goto(ROOT + '/Talleristas/Control%20Tall/ControlTalleristas_GP2.html');
  await page.waitForFunction(() => document.querySelectorAll('#tallGrid .prov-btn').length > 0);

  const ok = (c, msg) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + msg); if (!c) process.exitCode = 1; };

  // Todos + 2 talleristas; Fabrica (id 3) afuera; el duplicado de comp_id se deduplica
  const btns = await page.$$eval('#tallGrid .prov-btn', xs => xs.map(x => x.textContent));
  ok(btns.length === 3 && btns[0].includes('Todos') && !btns.join(' ').includes('Fabrica'),
     'grid: Todos + 2 talleristas, sin Fabrica — ' + btns.join(' | '));
  ok(btns[0].includes('2 talleristas') && btns[0].includes('2 partes'), 'Todos: 2 talleristas · 2 partes');

  // elegir Martin: 1 fila (dedup), kg = 500*0.02 = 10, caj = 500/1000 = 0,5
  await page.click('#tallGrid .prov-btn:has-text("Martin")');
  let rows = await page.$$eval('#tbody tr', xs => xs.map(x => x.textContent));
  ok(rows.length === 1, 'Martin: 1 fila (comp duplicado deduplicado)');
  ok(rows[0].includes('10') && rows[0].includes('0,5') && rows[0].includes('500') &&
     rows[0].includes('800') && rows[0].includes('200') && rows[0].includes('100'),
     'fila Martin kg/caj/uni + movimientos: ' + rows[0].replace(/\s+/g, ' '));
  ok(await page.$eval('#colTall', e => e.classList.contains('hidden')), 'columna Tallerista oculta en modo individual');

  // KPIs
  const kpis = await page.$eval('#kpis', e => e.textContent);
  ok(kpis.includes('Partes') && kpis.includes('800') && kpis.includes('200') && kpis.includes('500'),
     'KPIs enviado/entregado/saldo: ' + kpis.replace(/\s+/g, ' '));

  // modo Todos: columna tallerista visible, filas de ambos, saldo negativo con clase neg
  await page.click('#btnVolver');
  await page.click('#tallGrid .prov-btn:has-text("Todos")');
  rows = await page.$$eval('#tbody tr', xs => xs.map(x => x.textContent));
  ok(rows.length === 2 && rows[0].includes('Carlos') && rows[1].includes('Martin'),
     'Todos: 2 filas ordenadas por tallerista');
  ok(!(await page.$eval('#colTall', e => e.classList.contains('hidden'))), 'columna Tallerista visible en Todos');
  const negCls = await page.$eval('#tbody tr:first-child td:last-child', e => e.className);
  ok(negCls.includes('neg'), 'saldo -60 con clase neg');
  // Carlos sin uni_x_cajon ni kg_x_uni -> em-dash en kg y caj
  ok(rows[0].includes('—'), 'Carlos sin factores muestra —');

  // filtro
  await page.fill('#q', 'saca');
  rows = await page.$$eval('#tbody tr', xs => xs.map(x => x.textContent));
  ok(rows.length === 1 && rows[0].includes('C10'), 'filtro por descripcion');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
