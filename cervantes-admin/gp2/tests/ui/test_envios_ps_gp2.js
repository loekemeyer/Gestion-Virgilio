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
  // Ester tiene unidad de envio propia: bolsas de 1800 mangos, y la cantidad se carga en KG
  // (GP2.proveedor_servicio.envio_unidad / envio_uni_x / envio_carga_unidad, usuario 2026-09-17)
  // el PS "comun", sin unidad de envio propia. Al 2026-09-18 ninguno de los que tienen piezas
  // quedo asi (7 van por el cajon de cada pieza, AJ por paquetes, Julio por peso): Blist-Pack es
  // de los que siguen sin definir, y aca representa el render de siempre (cajon + kg).
  ps: [{ id: 20, nombre: 'Blist-Pack', cod_prov: '77', proceso: 'Pintado' },
       { id: 14, nombre: 'Ester', cod_prov: null, proceso: 'Calado',
         envio_unidad: 'bolsas', envio_uni_x: 1800, envio_carga_unidad: 'kg' },
       // Guazzaroni: el envase NO es uno del proveedor (envio_uni_x null), es el cajon de cada SC
       { id: 4, nombre: 'Guazzaroni Patricio', cod_prov: null, proceso: 'Niquelado',
         envio_unidad: 'cajones', envio_uni_x: null, envio_carga_unidad: 'kg' },
       // FASONERO (pedido_por_oc): Maspoli pone la madera y nos VENDE el mango, asi que se le
       // emite O.C. y lo que se le manda (la virola) sale de esa O.C., no del maximo.
       { id: 15, nombre: 'Maspoli SRL', cod_prov: '2339', proceso: 'Armado Mango',
         envio_unidad: 'cajones', envio_uni_x: null, envio_carga_unidad: 'kg', pedido_por_oc: true },
       // mismo caso pero SIN O.C. abierta: no tiene que aparecer en la pantalla de envio
       { id: 16, nombre: 'Fasonero Sin OC', cod_prov: null, proceso: 'Armado',
         envio_unidad: 'cajones', envio_uni_x: null, envio_carga_unidad: 'kg', pedido_por_oc: true }],
  partes: { '20': [
    // una sola pieza enviada, dos salidas distintas
    { sc_id: 1, sp_id: 2, sc_cod: 'J2C', sc_desc: 'Cuchilla cruda', sp_cod: 'J2', sp_desc: 'Cuchilla pintada',
      proceso: 'Pintado', online_ps: 1500, online_sp: 50, maximo: 4000, maximo_sp: 500,
      sc_unixcaj: 1000, sc_kgxuni: 0.01, sp_unixcaj: 100 },
    { sc_id: 1, sp_id: 3, sc_cod: 'J2C', sc_desc: 'Cuchilla cruda', sp_cod: 'J2B', sp_desc: 'Cuchilla azul',
      proceso: 'Pintado', online_ps: 1500, online_sp: 0, maximo: 4000, maximo_sp: 300,
      sc_unixcaj: 1000, sc_kgxuni: 0.01, sp_unixcaj: 100 },
    // otra pieza, con una sola salida y sin maximo fisico cargado
    { sc_id: 4, sp_id: 6, sc_cod: 'K1C', sc_desc: 'Manija cruda', sp_cod: 'K1', sp_desc: 'Manija pintada',
      proceso: 'Pintado', online_ps: 0, online_sp: 0, maximo: null, maximo_sp: null,
      sc_unixcaj: 500, sc_kgxuni: 0.02, sp_unixcaj: 100 },
  ], '14': [
    // datos reales: PC2 (mango 505 sin calar) -> PC1A calado; 1852 uni/cajon, 0,0054 kg/uni
    { sc_id: 622, sp_id: 623, sc_cod: 'PC2', sc_desc: 'Mgo Pelapapa 505 Sin Calar',
      sp_cod: 'PC1A', sp_desc: 'Mgo Pelapapa 505 Calado', proceso: 'Calado',
      online_ps: 0, online_sp: 0, maximo: null, maximo_sp: 112432,
      sc_unixcaj: 1852, sc_kgxuni: 0.0054, sp_unixcaj: 1852 },
  ], '4': [
    // datos reales: CV1 (remache espiral crudo) -> niquelado; 57.143 uni/cajon, 0,00035 kg/uni
    { sc_id: 601, sp_id: 602, sc_cod: 'CV1', sc_desc: 'Remache Espiral p/Niquelar',
      sp_cod: 'CV1N', sp_desc: 'Remache Espiral Niq', proceso: 'Niquelado',
      online_ps: 0, online_sp: 0, maximo: null, maximo_sp: 114286,
      // el cajon del niquelado (V1) es 10 veces mas chico: el sugerido tiene que salir en cajones
      // del CRUDO que se manda (2), no del SP que vuelve (20) [Thomas 2026-09-25]
      sc_unixcaj: 57143, sc_kgxuni: 0.00035, sp_unixcaj: 5714 },
    // CV9 no tiene cajon cargado: no hay con que pasar a cajones, pero la tabla NO se deforma
    { sc_id: 609, sp_id: 610, sc_cod: 'CV9', sc_desc: 'Remache uña niq. p/Niquelar',
      sp_cod: 'CV9N', sp_desc: 'Remache uña Niq', proceso: 'Niquelado',
      online_ps: 0, online_sp: 0, maximo: null, maximo_sp: 50000,
      sc_unixcaj: null, sc_kgxuni: 0.000567, sp_unixcaj: null },
  ], '15': [
    // una sola virola D13 que vuelve como TRES mangos distintos; solo el PC12 tiene O.C. abierta
    { sc_id: 111, sp_id: 221, sc_cod: 'D13', sc_desc: 'Virola Sacafuente Niq', sp_cod: 'PC12',
      sp_desc: 'Mgo Sacafuente Articulado', proceso: 'Armado Mango',
      online_ps: 0, online_sp: 0, maximo: null, maximo_sp: 2448,
      sc_unixcaj: 3125, sc_kgxuni: 0.0032, sp_unixcaj: 250, oc_pend: 10 },
    { sc_id: 111, sp_id: 222, sc_cod: 'D13', sc_desc: 'Virola Sacafuente Niq', sp_cod: 'PEP7',
      sp_desc: 'Mgo sacafuente pizzero', proceso: 'Armado Mango',
      online_ps: 0, online_sp: 0, maximo: null, maximo_sp: 2864,
      sc_unixcaj: 3125, sc_kgxuni: 0.0032, sp_unixcaj: 250, oc_pend: 0 },
    { sc_id: 111, sp_id: 223, sc_cod: 'D13', sc_desc: 'Virola Sacafuente Niq', sp_cod: 'PEP8',
      sp_desc: 'Mango Madera Pizza', proceso: 'Armado Mango',
      online_ps: 0, online_sp: 0, maximo: null, maximo_sp: 2552,
      sc_unixcaj: 3125, sc_kgxuni: 0.0032, sp_unixcaj: 250, oc_pend: 0 },
  ], '16': [
    { sc_id: 700, sp_id: 701, sc_cod: 'XX1', sc_desc: 'Pieza cruda', sp_cod: 'XX2',
      sp_desc: 'Pieza armada', proceso: 'Armado',
      online_ps: 0, online_sp: 0, maximo: null, maximo_sp: 5000,
      sc_unixcaj: 100, sc_kgxuni: 0.01, sp_unixcaj: 100, oc_pend: 0 },
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
  ok(provTxt.includes('Blist-Pack') && provTxt.includes('Pintado') && /\b2 partes\b/.test(provTxt),
     'fase0: el boton cuenta piezas a enviar, no pares — ' + provTxt.trim());
  ok((await page.$eval('#status', e => e.textContent)).includes('5 proveedores'), 'status: 5 proveedores');
  // FASONERO: aparece SIEMPRE, con O.C. o sin ella (igual que el inyector, usuario 2026-09-18).
  // Sin orden el sugerido es 0; no se esconde, porque un proveedor que desaparece no se distingue
  // de una pantalla rota.
  const nombresPS = await page.$$eval('#psGrid .prov-btn', xs => xs.map(x => x.textContent));
  ok(nombresPS.length === 5 && nombresPS.some(t => t.includes('Fasonero Sin OC')),
     'el fasonero sin O.C. TAMBIEN aparece en Envio — ' + nombresPS.length + ' botones');
  ok(nombresPS.some(t => t.includes('Maspoli SRL') && /\b1 partes\b/.test(t)),
     'el fasonero con O.C. aparece con su unica pieza');

  // elegir proveedor
  await page.click('#psGrid .prov-btn');
  ok(await page.$eval('#fase1', e => !e.classList.contains('hidden')), 'fase1 visible al elegir');
  ok((await page.$eval('#fase1Title', e => e.textContent)) === 'Blist-Pack · Pintado', 'titulo Blist-Pack · Pintado');
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

  // la tabla ya NO muestra Online PS / Online SP / Maximo: solo cantidad a enviar + Sugerido
  const heads = await page.$$eval('#tbody', () =>
    Array.from(document.querySelectorAll('thead th')).map(t => t.textContent));
  ok(!heads.some(h => /Online|Max/.test(h)), 'sin encabezados Online PS/SP ni Max: ' + heads.join(' | '));
  ok(heads.some(h => /Sugerido/.test(h)), 'queda el encabezado Sugerido');
  const cells0 = await page.$$eval('#tbody tr:first-child td', xs => xs.length);
  ok(cells0 === 7, 'la fila tiene 7 columnas (se sacaron Online PS/SP y Maximo): ' + cells0);

  // sugerido = (5 - 0,5 - 1,5) + (3 - 0 - 1,5) = 3 + 1,5 = 4,5 caj (suma las salidas)
  // y en kg = 4,5 x 1000 x 0,01 = 45,00 kg (se envia el SC: uni_x_cajon x kg_x_uni)
  ok(rows[0].includes('4,5 caj') && rows[0].includes('45 kg'),
     'sugerido en cajones y kg: ' + rows[0].slice(-55));
  const sugHtml = await page.$eval('#tbody tr:first-child td:last-child', e => e.innerHTML);
  ok(sugHtml.includes('<b') && sugHtml.includes('4,5 caj') && sugHtml.includes('45 kg'),
     'sugerido > 0 en negrita roja, en caj + kg');
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
     mf[0].args.p_nota === 'Envio a Blist-Pack',
     'F activada persiste: marcar_faltante(sc 4, envios_ps): ' + JSON.stringify(mf[0].args));
  await page.fill('#tbody tr:first-child input[data-f="kg"]', '12,5');

  // buffer persistido por PIEZA enviada (antes era por par sc:sp)
  const buf = await page.evaluate(() => JSON.parse(localStorage.getItem('gp2_enviosPS_buffer2') || '{}'));
  ok(buf['20'] && buf['20']['1'] && buf['20']['1'].caj === '2' && buf['20']['1'].kg === '12,5' &&
     buf['20']['4'] && buf['20']['4'].falt === true, 'buffer localStorage por pieza enviada');

  const fecha = await page.$eval('#fFecha', e => e.value);
  await page.click('#btnEnviar');
  await page.waitForFunction(() => !document.getElementById('fase3').classList.contains('hidden'));

  // UNA sola llamada aunque la pieza tenga dos salidas: se envia la pieza, no el par
  const call = await page.evaluate(() => (window.__calls || []).filter(c => c.name === 'crear_envio_ps'));
  ok(call.length === 1, 'una sola llamada crear_envio_ps aunque la pieza tenga dos salidas');
  const a = call[0].args;
  ok(a.p_ps_id === 20 && a.p_comp_sc_id === 1 && a.p_cantidad === 12.5 && a.p_unidad === 'kg' &&
     a.p_fecha === fecha && a.p_cajones === 2 && a.p_faltante === false,
     'payload crear_envio_ps: ' + JSON.stringify(a));

  // exito: codigo de 4 digitos y detalle con aviso de la marca F sin cantidad
  const code = await page.$eval('#successCode', e => e.textContent);
  ok(/^\d{4}$/.test(code), 'codigo de 4 digitos: ' + code);
  const det = await page.$eval('#successDetail', e => e.textContent);
  ok(det.includes('1 partes enviadas a Blist-Pack') && det.includes('1 marca(s) F'), 'detalle exito: ' + det);

  // la marca F sin cantidad sigue en el buffer; lo enviado salio
  const buf2 = await page.evaluate(() => JSON.parse(localStorage.getItem('gp2_enviosPS_buffer2') || '{}'));
  ok(buf2['20'] && !buf2['20']['1'] && buf2['20']['4'] && buf2['20']['4'].falt === true,
     'buffer: enviado afuera, marca F conservada');

  // volver a fase 0
  await page.click('#btnVolverPS');
  ok(await page.$eval('#fase0', e => !e.classList.contains('hidden')), 'volver a fase0');

  // ── Ester: sugerido en BOLSAS de 1800, un solo campo en KG con las bolsas debajo ──────────
  await page.click('#psGrid .prov-btn:has-text("Ester")');
  const thEs = await page.$$eval('#thead th', xs => xs.map(x => x.textContent.replace(/\s+/g, '').trim()));
  ok(thEs.join('|') === 'SC|CantidadKG Neto|T|F|Parte|Sugeridobolsas'.replace(/\s+/g, ''),
     'Ester: se va la columna del cajon y el sugerido se rotula en bolsas — ' + thEs.join(' | '));
  ok((await page.$$eval('#tbody tr:first-child td', xs => xs.length)) === 6,
     'Ester: 6 columnas (sin Cajon envio)');
  const sugEs = await page.$eval('#tbody tr:first-child td:last-child', e => e.textContent.trim());
  ok(sugEs === '63 bolsas', 'Ester: 112.432 mangos / 1800 -> 63 bolsas (techo) — ' + sugEs);
  await page.fill('#tbody input.cell-in[data-f="kg"]', '612,36');
  ok((await page.$eval('#tbody .env-eq', e => e.textContent.trim())) === '= 63 bolsas',
     'Ester: debajo del kg se ven las bolsas y se recalculan al tipear — ' +
     (await page.$eval('#tbody .env-eq', e => e.textContent.trim())));
  await page.click('#btnEnviar');
  await page.waitForFunction(() => !document.getElementById('fase3').classList.contains('hidden'));
  const callEs = await page.evaluate(() => (window.__calls || []).filter(c => c.name === 'crear_envio_ps'));
  const aEs = callEs[callEs.length - 1].args;
  ok(aEs.p_ps_id === 14 && aEs.p_comp_sc_id === 622 && aEs.p_cantidad === 612.36 &&
     aEs.p_unidad === 'kg' && aEs.p_cajones === 63,
     'Ester: viaja el kg (la base lo pasa a mangos con kg_x_uni) y quedan anotadas las 63 bolsas — ' + JSON.stringify(aEs));
  ok(dialogs.some(d => d.type === 'confirm' && d.msg.includes('612,36 kg (63 bolsas)')),
     'Ester: el confirm dice los kg y las bolsas');

  // ── Guazzaroni: sugerido en CAJONES (el de cada pieza) y un solo campo en KG ──────────────
  await page.click('#btnVolverPS');
  await page.click('#psGrid .prov-btn:has-text("Guazzaroni")');
  const thGz = await page.$$eval('#thead th', xs => xs.map(x => x.textContent.replace(/\s+/g, '').trim()));
  ok(thGz.join('|') === 'SC|CantidadKGNeto|T|F|Parte|Sugeridocajones',
     'Guazzaroni: sin columna de cajon y el sugerido rotulado en cajones — ' + thGz.join(' | '));
  const celdasGz = await page.$$eval('#tbody tr', xs => xs.map(x => x.querySelectorAll('td').length));
  ok(celdasGz.length === 2 && celdasGz.every(n => n === 6),
     'Guazzaroni: las 2 filas con 6 columnas, aunque una no se pueda pasar a cajones — ' + celdasGz.join(','));
  const sugsGz = await page.$$eval('#tbody tr td:last-child', xs => xs.map(x => x.textContent.trim()));
  ok(sugsGz[0] === '2 cajones', 'Guazzaroni: 114.286 uni de maximo / 57.143 (cajon del CRUDO, no el 5.714 del niquelado) -> 2 cajones — ' + sugsGz[0]);
  ok(sugsGz[1] === '—', 'Guazzaroni: sin uni_x_cajon el sugerido no se inventa — ' + sugsGz[1]);
  await page.fill('#tbody tr:first-child input.cell-in[data-f="kg"]', '40');
  ok((await page.$eval('#tbody .env-eq', e => e.textContent.trim())) === '= 2 cajones',
     'Guazzaroni: 40 kg = 2 cajones exactos');
  await page.fill('#tbody tr:first-child input.cell-in[data-f="kg"]', '70');
  const eqsGz = await page.$$eval('#tbody .env-eq', xs => xs.map(x => x.textContent.trim()));
  ok(eqsGz.length === 1 && eqsGz[0] === '= 3,5 cajones',
     'Guazzaroni: los cajones van CON DECIMALES y solo en la fila convertible — ' + eqsGz.join(' | '));
  await page.click('#btnEnviar');
  await page.waitForFunction(() => !document.getElementById('fase3').classList.contains('hidden'));
  const callGz = await page.evaluate(() => (window.__calls || []).filter(c => c.name === 'crear_envio_ps'));
  const aGz = callGz[callGz.length - 1].args;
  ok(aGz.p_ps_id === 4 && aGz.p_comp_sc_id === 601 && aGz.p_cantidad === 70 && aGz.p_unidad === 'kg' &&
     aGz.p_cajones === 3.5,
     'Guazzaroni: viaja el kg y quedan anotados los 3,5 cajones — ' + JSON.stringify(aGz));
  const cfGz = dialogs.filter(d => d.type === 'confirm').pop();
  ok(cfGz && cfGz.msg.includes('CV1: 70 kg (3,5 cajones)') && !cfGz.msg.includes('caj /'),
     'Guazzaroni: el confirm dice los kg con los cajones con decimales y no nombra la columna de cajón — ' +
     (cfGz ? cfGz.msg.replace(/\n/g, ' / ') : 'sin confirm'));

  // ── FASONERO: el sugerido sale de la O.C., en UNIDADES de la pieza que se le manda ─────────
  // [usuario 2026-09-18: "por 10 mangos hay que mandarle 10 virolas... el equivalente a 10
  // unidades de virola"]. Las otras dos salidas (PEP7/PEP8) no tienen O.C. y no suman.
  await page.click('#btnVolverPS');
  await page.click('#psGrid .prov-btn:has-text("Maspoli")');
  const thMa = await page.$$eval('#thead th', xs => xs.map(x => x.textContent.replace(/\s+/g, '').trim()));
  ok(thMa.join('|') === 'SC|CantidadKGNeto|T|F|Parte|Sugeridoseg\u00fanO.C.',
     'Maspoli: la columna se rotula por la O.C., no por el maximo — ' + thMa.join(' | '));
  const filasMa = await page.$$eval('#tbody tr', xs => xs.map(x => x.textContent.replace(/\s+/g, ' ')));
  ok(filasMa.length === 1, 'Maspoli: una sola fila (la virola), aunque devuelva 3 mangos — ' + filasMa.length);
  ok(filasMa[0].includes('PC12') && filasMa[0].includes('PEP7') && filasMa[0].includes('PEP8'),
     'Maspoli: la fila lista sus tres salidas');
  const sugMa = await page.$eval('#tbody tr:first-child td:last-child', e => e.textContent.trim());
  ok(sugMa.includes('10 uni'), 'Maspoli: O.C. de 10 mangos -> sugerido 10 virolas — ' + sugMa);
  ok(sugMa.includes('0,032 kg'), 'Maspoli: los kg al lado, que es como se le carga la cantidad — ' + sugMa);

  // el fasonero SIN O.C.: misma pantalla, misma fila, sugerido en 0
  await page.click('#btnVolver');
  await page.click('#psGrid .prov-btn:has-text("Fasonero Sin OC")');
  const filasSin = await page.$$eval('#tbody tr', xs => xs.length);
  ok(filasSin === 1, 'fasonero sin O.C.: la fila se muestra igual — ' + filasSin);
  const sugSin = await page.$eval('#tbody tr:first-child td:last-child', e => e.textContent.trim());
  ok(sugSin.startsWith('0 uni'), 'fasonero sin O.C.: sugerido 0, no escondido — ' + sugSin);

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
