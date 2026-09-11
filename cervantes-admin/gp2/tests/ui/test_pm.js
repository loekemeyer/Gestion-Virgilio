const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
// Raiz del repo (los tests viven en tests/ui/) y Chromium portable si existe.
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const BUNDLE = {
  eventos: [
    { fecha: '2026-08-29', hora_inicio: '12:30:00', hora_fin: '12:35:00', tipo: 'RM', legajo: '19',
      empleado: 'Eduardo B', matriz: '28', nombre_matriz: 'Pinza Grande', segundos: 300, uni_acum: 100, uni_x_golpe: 2, golpes: 50 },
    { fecha: '2026-08-29', hora_inicio: '11:30:00', hora_fin: null, tipo: 'RM', legajo: '19',
      empleado: 'Eduardo B', matriz: '28', nombre_matriz: 'Pinza Grande', segundos: null, uni_acum: 700, uni_x_golpe: 0, golpes: null },
    { fecha: '2026-08-28', hora_inicio: '10:30:00', hora_fin: '10:40:00', tipo: 'PM', legajo: '22',
      empleado: 'Otro Op', matriz: '62', nombre_matriz: 'Cuchilla', segundos: 600, uni_acum: 400, uni_x_golpe: 4, golpes: 100 },
  ],
  empleados: [ { legajo: '19', nombre: 'Eduardo B' }, { legajo: '22', nombre: 'Otro Op' } ],
};

const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    window.__calls = window.__calls || [];
    window.__calls.push({name:name, args:args});
    if(name==='problemas_matrices_bundle') return { data: ${JSON.stringify(BUNDLE)}, error: null };
    return { data: null, error: { message: 'rpc desconocida '+name } };
  }
};}};
`;

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const page = await browser.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });

  await page.route('**/@supabase/supabase-js@2', r =>
    r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/gp2-modulo.css**', r => r.fulfill({ contentType: 'text/css', body: '.hidden{display:none!important}' }));
  await page.route('**/GP2_favicon.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));

  await page.goto(ROOT + '/Produccion/ProblemasMatrices/ProblemasMatrices_GP2.html');
  await page.waitForFunction(() => document.querySelectorAll('#tbody tr').length === 3);

  const ok = (c, msg) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + msg); if (!c) process.exitCode = 1; };

  const args = await page.evaluate(() => window.__calls[0].args);
  ok(!!args.p_desde && !!args.p_hasta, 'rango enviado: ' + args.p_desde + ' a ' + args.p_hasta);

  ok((await page.textContent('#kRM')) === '2' && (await page.textContent('#kPM')) === '1', 'KPIs RM=2 PM=1');
  let rows = await page.$$eval('#tbody tr', xs => xs.map(x => x.textContent));
  ok(rows[0].includes('100') && rows[0].includes('5m') && rows[0].includes('28'), 'fila RM: acum 100, dur 5m 00s');
  ok(rows[1].includes('700') && rows[1].includes('—'), 'fila sin duracion: —');

  // filtro tipo PM
  await page.selectOption('#tipo', 'PM');
  rows = await page.$$eval('#tbody tr', xs => xs.map(x => x.textContent));
  ok(rows.length === 1 && rows[0].includes('400') && rows[0].includes('62'), 'filtro PM: 1 fila matriz 62');
  ok((await page.textContent('#kTot')) === '1', 'KPI total refleja filtro');

  // filtro operario
  await page.selectOption('#tipo', '');
  await page.selectOption('#oper', '19');
  rows = await page.$$eval('#tbody tr', xs => xs.map(x => x.textContent));
  ok(rows.length === 2, 'filtro operario 19: 2 filas');

  // filtro matriz
  await page.selectOption('#oper', '');
  await page.fill('#mat', '62');
  await page.$eval('#mat', x => x.dispatchEvent(new Event('input')));
  rows = await page.$$eval('#tbody tr', xs => xs.map(x => x.textContent));
  ok(rows.length === 1 && rows[0].includes('Cuchilla'), 'filtro matriz 62: 1 fila');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
