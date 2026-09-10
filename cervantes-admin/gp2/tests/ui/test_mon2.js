const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
// Raiz del repo (los tests viven en tests/ui/) y Chromium portable si existe.
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const ROWS = [
  // premio directo del espejo
  { legajo: '19', nombre_empleado: 'Eduardo B', matriz_raw: '28', nombre_matriz: 'Pinza',
    uni: 400, fecha: '2026-08-29T14:00:00-03:00', premio: 3.5, tiempo_toma: null, tiempo_historico: null, eliminar: null },
  // premio calculado: tt=1.3 th=1 -> (-(1.3)+1)*10 = -3
  { legajo: '22', nombre_empleado: 'Otro Op', matriz_raw: '62', nombre_matriz: 'Cuchilla',
    uni: 200, fecha: '2026-08-29T13:00:00-03:00', premio: null, tiempo_toma: 1.3, tiempo_historico: 1, eliminar: null },
  // sin datos de premio
  { legajo: '30', nombre_empleado: 'Tercero', matriz_raw: '99', nombre_matriz: 'Otra',
    uni: 100, fecha: '2026-08-29T12:00:00-03:00', premio: null, tiempo_toma: null, tiempo_historico: null, eliminar: null },
  // eliminada: no debe aparecer
  { legajo: '31', nombre_empleado: 'Borrado', matriz_raw: '11', nombre_matriz: 'X',
    uni: 50, fecha: '2026-08-29T11:00:00-03:00', premio: 5, tiempo_toma: null, tiempo_historico: null, eliminar: 'S' },
];

const STUB = `
var chain = function(result){
  var o = { };
  ['select','gte','lte','gt','order','limit','eq'].forEach(function(m){ o[m] = function(){ return o; }; });
  o.then = function(res, rej){ return Promise.resolve(result).then(res, rej); };
  return o;
};
window.supabase = { createClient: function(){ return {
  from: function(t){ window.__from = (window.__from||[]); window.__from.push(t);
    return chain({ data: ${JSON.stringify(ROWS)}, error: null }); },
  rpc: async function(){ return { data: null, error: { message: 'no rpc' } }; }
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

  await page.goto(ROOT + '/Produccion/monitor2_GP2.html');
  await page.waitForFunction(() => document.querySelectorAll('#tbody tr').length > 0);

  const ok = (c, msg) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + msg); if (!c) process.exitCode = 1; };

  const rows = await page.$$eval('#tbody tr', xs => xs.map(x => x.textContent));
  ok(rows.length === 3, '3 filas (la eliminada no aparece): ' + rows.length);
  ok(rows[0].includes('3,5') && rows[0].includes('Eduardo'), 'premio del espejo 3,5');
  ok(rows[1].includes('-3') && rows[1].includes('Otro Op'), 'premio calculado -3,0');
  ok(rows[2].includes('—'), 'sin premio: —');

  const alertas = await page.textContent('#alertas');
  ok(alertas.includes('≤ -3 (1)') && alertas.includes('Otro Op'), 'alerta mala con Otro Op');
  ok(alertas.includes('≥ 3 (1)') && alertas.includes('Eduardo'), 'alerta buena con Eduardo');
  ok((await page.textContent('#status')).includes('3 cajones'), 'status 3 cajones');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
