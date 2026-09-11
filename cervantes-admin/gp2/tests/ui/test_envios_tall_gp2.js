/* Caracterizacion de Talleristas/Envios/EnviosTalleristas_GP2.html (previo a la
   unificacion): fija render, calculo Cjn a Env / Uni, validacion de kg, payload
   crear_envio_tallerista, remito de fase 3 y limpieza del buffer. */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const BUNDLE = {
  tall: [{ id: 6, nombre: 'Martin', cod_prov: '44' }],
  partes: { '6': { entrada: [
    { comp_id: 70, cod: 'A10', desc: 'Cpo Una', sector: 'D1', uni_x_cajon: 1000, online_sector: 2500, kg_x_uni: 0.02 },
    { comp_id: 71, cod: 'C10', desc: 'Cpo Sacacorcho', sector: 'D2', uni_x_cajon: null, online_sector: 0, kg_x_uni: null },
  ], salida: [] } },
};

const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    window.__calls = window.__calls || [];
    window.__calls.push({name:name, args:args});
    if(name==='talleristas_bundle') return { data: ${JSON.stringify(BUNDLE)}, error: null };
    if(name==='crear_envio_tallerista') return { data: { id: 1 }, error: null };
    if(name==='marcar_faltante') return { data: { ok: true, id: 7 }, error: null };
    if(name==='resolver_faltante') return { data: { ok: true, resueltos: 1 }, error: null };
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

  await page.goto(ROOT + '/Talleristas/Envios/EnviosTalleristas_GP2.html');
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await page.waitForFunction(() => document.querySelectorAll('#tallGrid .prov-btn').length > 0);

  const ok = (c, msg) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + msg); if (!c) process.exitCode = 1; };

  const btnTxt = await page.$eval('#tallGrid .prov-btn', b => b.textContent);
  ok(btnTxt.includes('Martin') && btnTxt.includes('44') && btnTxt.includes('2 partes'),
     'fase0: boton Martin con cod y 2 partes — ' + btnTxt.trim());

  await page.click('#tallGrid .prov-btn');
  ok((await page.$eval('#fase1Title', e => e.textContent)) === 'Martin · cod 44', 'titulo Martin · cod 44');

  // fila 1: Cjn a Env = 2500/1000 = 2,5 ; fila 2 sin uni_x_cajon = em-dash
  let rows = await page.$$eval('#tbody tr', xs => xs.map(x => x.textContent));
  ok(rows.length === 2 && rows[0].includes('2,5'), 'Cjn a Env 2,5: ' + rows[0].replace(/\s+/g, ' '));
  ok(rows[1].includes('—'), 'fila sin uni_x_cajon muestra —');

  // cargar kg -> la col Uni se recalcula en vivo (10 kg / 0.02 = 500)
  await page.fill('#tbody tr:first-child input[data-f="kg"]', '10');
  const uniTxt = await page.$eval('#tbody tr:first-child td:last-child', e => e.textContent);
  ok(uniTxt === '500', 'Uni en vivo = 500 (10kg / 0,02): ' + uniTxt);
  await page.fill('#tbody tr:first-child input[data-f="caj"]', '3');

  // marca falt en fila 2 -> ademas del buffer, se persiste via marcar_faltante (best-effort)
  await page.click('#tbody tr:nth-child(2) .falt-box');
  ok(await page.$eval('#tbody tr:nth-child(2)', e => e.classList.contains('falt')), 'fila 2 falt');
  await page.waitForFunction(() => (window.__calls || []).some(c => c.name === 'marcar_faltante'));
  let mf = await page.evaluate(() => (window.__calls || []).filter(c => c.name === 'marcar_faltante'));
  ok(mf.length === 1 && mf[0].args.p_comp_id === 71 && mf[0].args.p_origen === 'envios_tall' &&
     mf[0].args.p_nota === 'Envio a Martin' && mf[0].args.p_usuario === null,
     'F activada persiste: marcar_faltante(71, envios_tall): ' + JSON.stringify(mf[0].args));

  // desmarcar -> resuelve el ultimo abierto de ese componente+origen
  await page.click('#tbody tr:nth-child(2) .falt-box');
  await page.waitForFunction(() => (window.__calls || []).some(c => c.name === 'resolver_faltante'));
  const rf = await page.evaluate(() => (window.__calls || []).filter(c => c.name === 'resolver_faltante'));
  ok(rf.length === 1 && rf[0].args.p_comp_id === 71 && rf[0].args.p_origen === 'envios_tall',
     'F desactivada resuelve: resolver_faltante(71, envios_tall): ' + JSON.stringify(rf[0].args));

  // volver a marcarla (la semantica del resto del test: fila 2 queda con F)
  await page.click('#tbody tr:nth-child(2) .falt-box');
  await page.waitForFunction(() => (window.__calls || []).filter(c => c.name === 'marcar_faltante').length === 2);
  ok(await page.$eval('#tbody tr:nth-child(2)', e => e.classList.contains('falt')), 'fila 2 falt de nuevo');

  // buscar filtra
  await page.fill('#q', 'sacacorcho');
  rows = await page.$$eval('#tbody tr', xs => xs.map(x => x.textContent));
  ok(rows.length === 1 && rows[0].includes('C10'), 'filtro por descripcion');
  await page.fill('#q', '');

  const fecha = await page.$eval('#fFecha', e => e.value);
  await page.click('#btnEnviar');
  await page.waitForFunction(() => !document.getElementById('fase3').classList.contains('hidden'));
  ok(dialogs.some(d => d.type === 'confirm' && d.msg.includes('Enviar a Martin')), 'confirm de envio');

  const call = await page.evaluate(() => (window.__calls || []).filter(c => c.name === 'crear_envio_tallerista'));
  ok(call.length === 1, 'una llamada crear_envio_tallerista');
  const a = call[0].args;
  ok(a.p_tallerista_id === 6 && a.p_comp_id === 70 && a.p_cantidad === 10 && a.p_unidad === 'kg' &&
     a.p_fecha === fecha + 'T12:00:00-03:00',
     'payload crear_envio_tallerista: ' + JSON.stringify(a));

  // fase 3: remito con la fila y totales
  const remito = await page.$eval('#tbodyPrint', e => e.textContent);
  ok(remito.includes('A10') && remito.includes('3') && remito.includes('10') && remito.includes('500'),
     'remito: A10 3caj 10kg 500uni — ' + remito.replace(/\s+/g, ' '));
  const foot = await page.$eval('#tfootPrint', e => e.textContent);
  ok(foot.includes('1 partes'), 'pie remito 1 partes');
  ok((await page.$eval('#printTitle', e => e.textContent)).includes('Remito · Martin'), 'titulo remito');
  ok(/^\d{4}$/.test(await page.$eval('#successCode', e => e.textContent)), 'codigo 4 digitos');

  // regresion del parser (bug historico eliminado 2026-08-30): "1.234,5" es 1234,5
  const nParse = await page.evaluate(() => GP2EE.num('1.234,5'));
  ok(nParse === 1234.5, 'parser: "1.234,5" = 1234,5 (dio ' + nParse + ')');

  // v2026-08-30 (OK del usuario): lo ENVIADO sale del buffer, pero la marca F
  // SIN cantidad se CONSERVA para la proxima (igual que las pantallas PS), con aviso.
  const buf = await page.evaluate(() => JSON.parse(localStorage.getItem('gp2_enviosTall_buffer') || '{}'));
  const b6 = buf['6'] || {};
  ok(!b6['70'], 'lo enviado (comp 70) salio del buffer');
  const soloF = Object.values(b6);
  ok(soloF.length === 1 && soloF[0].falt === true && !(Number(soloF[0].kg) > 0),
     'la marca F sin cantidad sigue cargada: ' + JSON.stringify(b6));
  ok((await page.$eval('#successDetail', e => e.textContent)).includes('marca(s) F sin cantidad'),
     'el exito avisa que la marca F no se registro y sigue cargada');

  await page.click('#btnVolverTall');
  ok(await page.$eval('#fase0', e => !e.classList.contains('hidden')), 'volver a fase0');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
