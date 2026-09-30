const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

// Lo que devuelve GP2.matriz_racha_bundle (misma forma que en la base real).
const BUNDLE = {
  matrices: [
    { matriz:'72', descripcion:'Corte Arandela Chica', unidades:82500, golpes:16500, uni_x_golpe:5,
      accidentes:2, record:363300, es_record:false, ultimo_accidente:'2026-08-20T15:14:04-03:00',
      ultimo_tipo:'PM', ultimo_detalle:'Barrionuevo Eduardo', dias_sin_accidente:27 },
    { matriz:'16', descripcion:'Corte Arandela manguito', unidades:80000, golpes:20000, uni_x_golpe:4,
      accidentes:1, record:80000, es_record:true, ultimo_accidente:'2026-06-19T09:08:27-03:00',
      ultimo_tipo:'RM', ultimo_detalle:'Barrionuevo Eduardo', dias_sin_accidente:89 },
    { matriz:'90', descripcion:'Doblado Cabezal', unidades:1200, golpes:null, uni_x_golpe:null,
      accidentes:1, record:5000, es_record:false, ultimo_accidente:'2026-09-16T10:00:00-03:00',
      ultimo_tipo:'INGRESO', ultimo_detalle:'Se rompió la guía', dias_sin_accidente:0 },
    { matriz:'8', descripcion:'Despunte Cuchilla', unidades:261712, golpes:261712, uni_x_golpe:1,
      accidentes:0, record:261712, es_record:false, ultimo_accidente:null, ultimo_tipo:null,
      ultimo_detalle:null, dias_sin_accidente:null }
  ],
  totales: { matrices:4, unidades:425412, accidentes:4, en_record:1 },
  actualizado_en: '2026-09-16T15:00:00-03:00'
};

const STUB = `
window.supabase = { createClient: function(){ return {
  from: function(){ throw new Error('esta pantalla NO lee tablas sueltas, va por la RPC'); },
  rpc: async function(n, args){ window.__rpc = [n, args]; return { data: ${JSON.stringify(BUNDLE)}, error: null }; }
};}};
`;

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const page = await browser.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });

  await page.route('**/@supabase/supabase-js@2', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/gp2-modulo.css**', r => r.fulfill({ contentType: 'text/css', body: '.hidden{display:none!important}' }));
  await page.route('**/GP2_favicon.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));

  await page.goto(ROOT + '/Produccion/UnidadesSinAccidente/UnidadesSinAccidente_GP2.html');
  await page.waitForFunction(() => document.querySelectorAll('#tbody tr').length > 0);

  const ok = (c, msg) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + msg); if (!c) process.exitCode = 1; };

  const rpc = await page.evaluate(() => window.__rpc);
  ok(rpc[0] === 'matriz_racha_bundle', 'llama a la RPC del schema GP2: ' + rpc[0]);

  const rows = await page.$$eval('#tbody tr', xs => xs.map(x => x.textContent));
  ok(rows.length === 4, '4 matrices: ' + rows.length);
  ok(rows[0].includes('82.500') && rows[0].includes('Corte Arandela Chica'), 'unidades con separador de miles');
  ok(rows[1].includes('🏆'), 'trofeo en la que esta en su mejor racha');
  ok(!rows[0].includes('🏆'), 'sin trofeo la que no lo esta');
  ok(rows[2].includes('Se rompió la guía'), 'el ingreso de Planify muestra su motivo');
  ok(rows[3].includes('Nunca') && rows[3].includes('—'), 'la que nunca se rompio: Nunca y golpes —');

  ok((await page.textContent('#kUni')) === '425.412', 'KPI unidades: ' + (await page.textContent('#kUni')));
  ok((await page.textContent('#kAcc')) === '4', 'KPI accidentes');
  ok((await page.textContent('#kRec')) === '1', 'KPI en su mejor racha');

  // filtro "solo las que ya tuvieron un accidente"
  await page.check('#soloAcc');
  ok((await page.$$('#tbody tr')).length === 3, 'el filtro deja fuera la que nunca se rompio');
  await page.uncheck('#soloAcc');

  // filtro por descripcion
  await page.fill('#desc', 'arandela');
  ok((await page.$$('#tbody tr')).length === 2, 'filtro por descripcion: 2');
  await page.fill('#desc', '');

  // filtro por numero
  await page.fill('#mat', '72');
  ok((await page.$$('#tbody tr')).length === 1, 'filtro por numero de matriz: 1');

  const html = await page.innerHTML('#tbody');
  ok(!/undefined|NaN/.test(html), 'sin undefined ni NaN en la tabla');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
