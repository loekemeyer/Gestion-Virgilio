/* Caracterizacion de Prov Serv/Entregas/EntregaPS_GP2.html (previo a la unificacion):
   fija filtrado de filas sin SP, tandas, validacion de kg y payload crear_entrega_ps. */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const BUNDLE = {
  ps: [{ id: 5, nombre: 'Becker', cod_prov: '77', proceso: 'Pintado' }],
  partes: { '5': [
    { sc_id: 1, sp_id: 2, sc_cod: 'J2C', sc_desc: 'Cuchilla cruda', sp_cod: 'J2', sp_desc: 'Cuchilla pintada',
      proceso: 'Pintado', online_ps: 1500, online_sp: 50, maximo: 4000, maximo_sp: 500,
      sc_unixcaj: 1000, sp_unixcaj: 100 },
    { sc_id: 9, sp_id: null, sc_cod: 'X1', sc_desc: 'Sin salida', sp_cod: null, sp_desc: null,
      proceso: 'Pintado', online_ps: 0, online_sp: 0, maximo: null, maximo_sp: null,
      sc_unixcaj: null, sp_unixcaj: null },
  ] },
};

const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    window.__calls = window.__calls || [];
    window.__calls.push({name:name, args:args});
    if(name==='envios_ps_bundle') return { data: ${JSON.stringify(BUNDLE)}, error: null };
    if(name==='crear_entrega_ps') return { data: { id: 1 }, error: null };
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

  await page.goto(ROOT + '/Prov%20Serv/Entregas/EntregaPS_GP2.html');
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await page.waitForFunction(() => document.querySelectorAll('#psGrid .prov-btn').length > 0);

  const ok = (c, msg) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + msg); if (!c) process.exitCode = 1; };

  await page.click('#psGrid .prov-btn');
  ok((await page.$eval('#fase1Title', e => e.textContent)) === 'Becker · Pintado', 'titulo Becker · Pintado');

  // la fila sin sp_id NO se lista (la entrega es SC->SP)
  const rows = await page.$$eval('#tbody tr', xs => xs.map(x => x.textContent));
  ok(rows.length === 1 && rows[0].includes('J2') && !rows.join(' ').includes('X1'),
     'solo la fila con SP: ' + rows.length);
  // En PS Cajon = 1500/1000 = 1,5
  ok(rows[0].includes('1,5'), 'En PS 1,5 cajones');

  // tandas: cargar dos tandas suma y deja los inputs readonly
  await page.click('#tbody tr:first-child .tanda-btn');
  await page.waitForSelector('#tandasOverlay.open');
  await page.fill('#tandasBody .tanda-row input[data-fld="caj"]', '1');
  await page.fill('#tandasBody .tanda-row input[data-fld="kg"]', '10');
  await page.click('#tandasOk');
  await page.waitForFunction(() => !document.querySelector('#tandasOverlay.open'));
  const vKg = await page.$eval('#tbody tr:first-child input[data-f="kg"]', e => ({ v: e.value, ro: e.readOnly }));
  ok(vKg.v === '10' && vKg.ro === true, 'tanda aplicada: kg=10 readonly');
  const tBtn = await page.$eval('#tbody tr:first-child .tanda-btn', e => ({ on: e.classList.contains('on'), t: e.textContent }));
  ok(tBtn.on && tBtn.t === '1', 'boton tanda on con contador 1');

  const fecha = await page.$eval('#fFecha', e => e.value);
  await page.click('#btnEnviar');
  await page.waitForFunction(() => !document.getElementById('fase3').classList.contains('hidden'));
  ok(dialogs.some(d => d.type === 'confirm' && d.msg.includes('J2C → J2')), 'confirm con resumen SC → SP');

  const call = await page.evaluate(() => (window.__calls || []).filter(c => c.name === 'crear_entrega_ps'));
  ok(call.length === 1, 'una llamada crear_entrega_ps');
  const a = call[0].args;
  ok(a.p_ps_id === 5 && a.p_comp_sc_id === 1 && a.p_comp_sp_id === 2 && a.p_kg === 10 &&
     a.p_fecha === fecha && a.p_cajones === 1 && a.p_faltante === false,
     'payload crear_entrega_ps: ' + JSON.stringify(a));

  const det = await page.$eval('#successDetail', e => e.textContent);
  ok(det.includes('1 partes recibidas de Becker'), 'detalle exito: ' + det);

  const buf = await page.evaluate(() => JSON.parse(localStorage.getItem('gp2_entregaPS_buffer') || '{}'));
  ok(!buf['5'], 'buffer limpio tras registrar');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
