/* Prov Serv/Envios/EnviosPS_GP2.html: render de fase0/fase1, calculo de
   cajones/sugerido, validacion de kg, payload de crear_envio_ps y limpieza del
   buffer. Supabase STUBEADO.

   El fixture tiene a proposito una pieza con DOS salidas (la cuchilla cruda
   J2C, que vuelve pintada o azul). Ese es el caso que el 2026-09-03 se
   descubrio roto con Maspoli: la pantalla mostraba una fila por cada salida, o
   sea la MISMA pieza repetida, y como crear_envio_ps no usa el SP para nada
   (solo recibe p_comp_sc_id), cargar las dos filas registraba dos envios de la
   misma pieza. Ahora va UNA fila por pieza enviada, con sus salidas listadas al
   lado y el sugerido sumado. En Entregas es al reves y sigue por par: al
   recibir hay que decir cual de las salidas volvio. */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const BUNDLE = {
  ps: [{ id: 5, nombre: 'Becker', cod_prov: '77', proceso: 'Pintado' }],
  partes: { '5': [
    // una sola pieza enviada, dos salidas distintas
    { sc_id: 1, sp_id: 2, sc_cod: 'J2C', sc_desc: 'Cuchilla cruda', sp_cod: 'J2', sp_desc: 'Cuchilla pintada',
      proceso: 'Pintado', online_ps: 1500, online_sp: 50, maximo: 4000, maximo_sp: 500,
      sc_unixcaj: 1000, sp_unixcaj: 100 },
    { sc_id: 1, sp_id: 3, sc_cod: 'J2C', sc_desc: 'Cuchilla cruda', sp_cod: 'J2B', sp_desc: 'Cuchilla azul',
      proceso: 'Pintado', online_ps: 1500, online_sp: 0, maximo: 4000, maximo_sp: 300,
      sc_unixcaj: 1000, sp_unixcaj: 100 },
    // otra pieza, con una sola salida y sin maximo fisico cargado
    { sc_id: 4, sp_id: 6, sc_cod: 'K1C', sc_desc: 'Manija cruda', sp_cod: 'K1', sp_desc: 'Manija pintada',
      proceso: 'Pintado', online_ps: 0, online_sp: 0, maximo: null, maximo_sp: null,
      sc_unixcaj: 500, sp_unixcaj: 100 },
  ] },
};

const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    window.__calls = window.__calls || [];
    window.__calls.push({name:name, args:args});
    if(name==='envios_ps_bundle') return { data: ${JSON.stringify(BUNDLE)}, error: null };
    if(name==='crear_envio_ps') return { data: { id: 1 }, error: null };
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

  await page.goto(ROOT + '/Prov%20Serv/Envios/EnviosPS_GP2.html');
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await page.waitForFunction(() => document.querySelectorAll('#psGrid .prov-btn').length > 0);

  const ok = (c, msg) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + msg); if (!c) process.exitCode = 1; };

  // fase 0
  const provTxt = await page.$eval('#psGrid .prov-btn', b => b.textContent);
  // El contador dice PIEZAS A ENVIAR, no pares: el fixture tiene 3 pares pero
  // son 2 piezas (la cuchilla cruda sale de dos maneras). Decia 3.
  ok(provTxt.includes('Becker') && provTxt.includes('Pintado') && /\b2 partes\b/.test(provTxt),
     'fase0: el boton cuenta piezas a enviar, no pares — ' + provTxt.trim());
  ok((await page.$eval('#status', e => e.textContent)).includes('1 proveedores'), 'status: 1 proveedores');

  // elegir proveedor
  await page.click('#psGrid .prov-btn');
  ok(await page.$eval('#fase1', e => !e.classList.contains('hidden')), 'fase1 visible al elegir');
  ok((await page.$eval('#fase1Title', e => e.textContent)) === 'Becker · Pintado', 'titulo Becker · Pintado');
  ok(await page.$eval('#btnVolver', e => !e.classList.contains('hidden')), 'btnVolver visible');
  ok((await page.$eval('#fFecha', e => e.value)) !== '', 'fecha con valor por defecto');

  // ── LO CENTRAL: 3 pares, 2 piezas -> 2 filas, no 3 ──────────────────────
  const rows = await page.$$eval('#tbody tr', xs => xs.map(x => x.textContent.replace(/\s+/g, ' ')));
  ok(rows.length === 2, 'una fila por PIEZA enviada, no por salida (' + rows.length + ' filas de 3 pares)');
  // se cuenta por la descripcion, no por el codigo: "J2C" matchea de casualidad
  // dentro de "J2Cuchilla pintada" al concatenarse el texto de la celda
  ok((rows[0].match(/Cuchilla cruda/g) || []).length === 1, 'la pieza enviada aparece UNA sola vez');
  ok(rows[0].includes('J2') && rows[0].includes('J2B'),
     'la fila lista sus dos salidas: ' + rows[0].slice(0, 70));

  // onPS 1,5 caj · onSP 0,5 caj · max 4 caj
  // sugerido = (5 - 0,5 - 1,5) + (3 - 0 - 1,5) = 3 + 1,5 = 4,5  (suma las salidas)
  ok(rows[0].includes('1,5') && rows[0].includes('0,5') && rows[0].includes('4,5'),
     'sugerido suma las dos salidas (4,5): ' + rows[0].slice(-45));
  const sugHtml = await page.$eval('#tbody tr:first-child td:last-child', e => e.innerHTML);
  ok(sugHtml.includes('<b') && sugHtml.includes('4,5'), 'sugerido > 0 en negrita roja');
  ok(rows[1].includes('—'), 'sin maximo fisico cargado el sugerido dice — en vez de inventar');

  // boton enviar arranca deshabilitado
  ok(await page.$eval('#btnEnviar', e => e.disabled), 'Enviar deshabilitado sin carga');

  // cargar caj sin kg -> al Enviar alerta de kg faltante
  await page.fill('#tbody tr:first-child input[data-f="caj"]', '2');
  ok(!(await page.$eval('#btnEnviar', e => e.disabled)), 'Enviar habilitado con caj');
  ok((await page.$eval('#btnEnviar', e => e.textContent)) === 'Enviar (1)', 'texto Enviar (1)');
  await page.click('#btnEnviar');
  ok(dialogs.length === 1 && dialogs[0].type === 'alert' && dialogs[0].msg.includes('Kg neto') && dialogs[0].msg.includes('J2C'),
     'alerta falta kg neto: ' + (dialogs[0] || {}).msg);

  // marca F en la segunda pieza (queda sin cantidad) + kg en la primera
  await page.click('#tbody tr:nth-child(2) .falt-box');
  ok(await page.$eval('#tbody tr:nth-child(2)', e => e.classList.contains('falt')), 'fila 2 marcada falt');
  // la F ademas se persiste (best-effort): marcar_faltante del SC de la fila
  await page.waitForFunction(() => (window.__calls || []).some(c => c.name === 'marcar_faltante'));
  const mf = await page.evaluate(() => (window.__calls || []).filter(c => c.name === 'marcar_faltante'));
  ok(mf.length === 1 && mf[0].args.p_comp_id === 4 && mf[0].args.p_origen === 'envios_ps' &&
     mf[0].args.p_nota === 'Envio a Becker',
     'F activada persiste: marcar_faltante(sc 4, envios_ps): ' + JSON.stringify(mf[0].args));
  await page.fill('#tbody tr:first-child input[data-f="kg"]', '12,5');

  // buffer persistido por PIEZA enviada (antes era por par sc:sp)
  const buf = await page.evaluate(() => JSON.parse(localStorage.getItem('gp2_enviosPS_buffer2') || '{}'));
  ok(buf['5'] && buf['5']['1'] && buf['5']['1'].caj === '2' && buf['5']['1'].kg === '12,5' &&
     buf['5']['4'] && buf['5']['4'].falt === true, 'buffer localStorage por pieza enviada');

  const fecha = await page.$eval('#fFecha', e => e.value);
  await page.click('#btnEnviar');
  await page.waitForFunction(() => !document.getElementById('fase3').classList.contains('hidden'));

  // UNA sola llamada aunque la pieza tenga dos salidas: se envia la pieza, no el par
  const call = await page.evaluate(() => (window.__calls || []).filter(c => c.name === 'crear_envio_ps'));
  ok(call.length === 1, 'una sola llamada crear_envio_ps aunque la pieza tenga dos salidas');
  const a = call[0].args;
  ok(a.p_ps_id === 5 && a.p_comp_sc_id === 1 && a.p_cantidad === 12.5 && a.p_unidad === 'kg' &&
     a.p_fecha === fecha && a.p_cajones === 2 && a.p_faltante === false,
     'payload crear_envio_ps: ' + JSON.stringify(a));

  // exito: codigo de 4 digitos y detalle con aviso de la marca F sin cantidad
  const code = await page.$eval('#successCode', e => e.textContent);
  ok(/^\d{4}$/.test(code), 'codigo de 4 digitos: ' + code);
  const det = await page.$eval('#successDetail', e => e.textContent);
  ok(det.includes('1 partes enviadas a Becker') && det.includes('1 marca(s) F'), 'detalle exito: ' + det);

  // la marca F sin cantidad sigue en el buffer; lo enviado salio
  const buf2 = await page.evaluate(() => JSON.parse(localStorage.getItem('gp2_enviosPS_buffer2') || '{}'));
  ok(buf2['5'] && !buf2['5']['1'] && buf2['5']['4'] && buf2['5']['4'].falt === true,
     'buffer: enviado afuera, marca F conservada');

  // volver a fase 0
  await page.click('#btnVolverPS');
  ok(await page.$eval('#fase0', e => !e.classList.contains('hidden')), 'volver a fase0');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
