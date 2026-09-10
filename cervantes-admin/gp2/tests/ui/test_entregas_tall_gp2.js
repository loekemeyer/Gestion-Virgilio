/* Caracterizacion de Talleristas/Recepcion/EntregasTalleristas_GP2.html (previo a
   la unificacion): usa el gp2-motor.js REAL con movimientos_bundle stubeado. Fija
   la deduccion de que consume cada parte, el stock en poder del tallerista y el
   payload de registrar_movimientos. */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const BUNDLE = {
  comp: {
    '70': { cod: 'A10', d: 'Cpo Una', s: 5, uxc: 1000 },
    '71': { cod: 'A11', d: 'Una Armada', s: 5, uxc: 500 },
    '75': { cod: 'F7', d: 'Fleje doblado', s: 6, uxc: null },
    '80': { cod: 'T1', d: 'Terminado', s: 12, uxc: 12 },
  },
  sect: { '5': { nom: 'D1' }, '6': { nom: 'D2' }, '12': { nom: 'Terminado' } },
  rp: {
    '1': [{ o: 1, tipo: 'tallerista', tall: 6, ce: 70, cs: 71 }],
    '2': [{ o: 1, tipo: 'tallerista', tall: 6, ce: 75, cs: 75 }],
    '3': [{ o: 1, tipo: 'tallerista', tall: 6, ce: 70, cs: 80 }],
  },
  ubic: {
    '1': { tipo: 'tallerista', ref: 6, nom: 'Tall Martin' },
    '2': { tipo: 'sector', ref: 5, nom: 'D1' },
    '3': { tipo: 'sector', ref: 6, nom: 'D2' },
    '4': { tipo: 'virgilio', nom: 'Virgilio' },
  },
  tall: { '6': { nom: 'Martin' }, '3': { nom: 'Fabrica' } },
  bom_comp: {},
  inv: { '71:1': { cant: 120 }, '75:1': { cant: 30 } },
};

const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    window.__calls = window.__calls || [];
    window.__calls.push({name:name, args:args});
    if(name==='movimientos_bundle') return { data: JSON.parse(JSON.stringify(${JSON.stringify(BUNDLE)})), error: null };
    if(name==='registrar_movimientos') return { data: { n: (args.p_rows||[]).length }, error: null };
    return { data: null, error: { message: 'rpc desconocida '+name } };
  }
};}};
`;

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const page = await browser.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  const dialogs = [];
  page.on('dialog', d => { dialogs.push({ type: d.type(), msg: d.message() }); d.accept(); });

  await page.route('**/@supabase/supabase-js@2**', r =>
    r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/GP2_favicon.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));

  await page.goto(ROOT + '/Talleristas/Recepcion/EntregasTalleristas_GP2.html');
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await page.waitForFunction(() => document.querySelectorAll('#tallGrid .prov-btn').length > 0);

  const ok = (c, msg) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + msg); if (!c) process.exitCode = 1; };

  // solo Martin (Fabrica no tiene partes no-terminadas); el terminado T1 no cuenta
  const btns = await page.$$eval('#tallGrid .prov-btn', xs => xs.map(x => x.textContent));
  ok(btns.length === 1 && btns[0].includes('Martin') && btns[0].includes('2 partes'),
     'fase0: solo Martin con 2 partes (terminado excluido) — ' + btns.join('|'));
  ok((await page.$eval('#status', e => e.textContent)).includes('1 de 2 talleristas'),
     'status 1 de 2 talleristas');

  await page.click('#tallGrid .prov-btn');
  // filas ordenadas por cod: A11 (consume A10), F7 (in-place)
  const rows = await page.$$eval('#tbody tr', xs => xs.map(x => x.textContent));
  ok(rows.length === 2, '2 filas');
  ok(rows[0].includes('A11') && rows[0].includes('A10') && rows[0].includes('120'),
     'fila A11: consume A10, en poder 120 — ' + rows[0].replace(/\s+/g, ' '));
  ok(rows[1].includes('F7') && rows[1].includes('devuelve lo mismo que recibe') && rows[1].includes('30'),
     'fila F7 in-place, en poder 30');

  // cargar 50 uni de A11 y registrar
  await page.fill('#tbody tr:first-child input[data-f="uni"]', '50');
  ok((await page.$eval('#btnEnviar', e => e.textContent)) === 'Registrar (1)', 'boton Registrar (1)');

  const fecha = await page.$eval('#fFecha', e => e.value);
  await page.click('#btnEnviar');
  await page.waitForFunction(() => !document.getElementById('fase3').classList.contains('hidden'));
  ok(dialogs.some(d => d.type === 'confirm' && d.msg.includes('Registrar recepción de Martin') && d.msg.includes('1 movimientos')),
     'confirm con resumen y cantidad de movimientos');

  const call = await page.evaluate(() => (window.__calls || []).filter(c => c.name === 'registrar_movimientos'));
  ok(call.length === 1 && call[0].args.p_rows.length === 1, 'una llamada registrar_movimientos con 1 fila');
  const m = call[0].args.p_rows[0];
  ok(m.tipo_mov === 'entrega_tallerista' && m.comp_id === 70 && m.ubic_origen_id === 1 && m.ubic_destino_id === 2 &&
     m.cantidad === 50 && m.comp_transformado_id === 71 && m.cantidad_transformada === 50 &&
     m.fecha === fecha + 'T12:00:00' && m.unidad_origen === 'uni' && m.unidad_destino === 'uni',
     'payload entrega_tallerista: ' + JSON.stringify(m));

  // recarga del motor despues de registrar (movimientos_bundle 2 veces) + exito
  const nBundle = await page.evaluate(() => (window.__calls || []).filter(c => c.name === 'movimientos_bundle').length);
  ok(nBundle === 2, 'movimientos_bundle recargado tras registrar');
  const det = await page.$eval('#successDetail', e => e.textContent);
  ok(det.includes('1 partes recibidas de Martin') && det.includes('1 movimientos'), 'detalle exito: ' + det);
  const buf = await page.evaluate(() => JSON.parse(localStorage.getItem('gp2_recepcionTall_buffer') || '{}'));
  ok(!buf['6'], 'buffer limpio');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
