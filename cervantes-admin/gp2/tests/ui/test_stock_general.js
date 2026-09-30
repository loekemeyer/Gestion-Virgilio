/* Stocks General v2.0.0 (2026-09-15): la pantalla se rediseñó de un árbol plano
   (Cód/Descripción/Cantidad SIN unidad) al mismo diseño de "Stock por Sector":
   arriba un SELECTOR DE RUBROS y abajo la tabla rica Base | Online (Kg/Caj/Uni) |
   Movimientos | Info, con las columnas adaptadas a cada rubro. Este test fija:
     - que el stock se separe por Kg / Caj / Uni (el pedido central del usuario),
     - que Flejes NO tenga Caj ni Uni×Cajón (y sí N° Fleje),
     - que los rubros que no son sector (Prov AT, Tránsito) rendericen su tabla,
     - el PAYLOAD EXACTO del Ajuste +/- (heredado, contrato que no cambia),
     - los últimos movimientos, y el render celular (390px, tocable, 18px).  */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const BUNDLE = {
  sect: { '1': { nom: 'Sector Crudo', tipo: 'crudo' }, '2': { nom: 'D1', tipo: 'crudo' }, '12': { nom: 'Terminado', tipo: 'terminado' } },
  ubic: {
    '1': { tipo: 'sector', ref: 2, nom: 'D1' },
    '2': { tipo: 'tallerista', ref: 3, nom: 'Cervantes (fábrica)' },
    '3': { tipo: 'tallerista', ref: 6, nom: 'Tall Martin' },
    '4': { tipo: 'virgilio', nom: 'Virgilio' },
    '5': { tipo: 'sector', ref: 12, nom: 'Terminado' },
    '6': { tipo: 'proveedor_servicio', ref: 9, nom: 'Pedernera Ilario' },
  },
  tall: { '3': { nom: 'Fabrica' }, '6': { nom: 'Martin' } },
  prov_serv: { '9': { nom: 'Pedernera Ilario', proceso: 'Cromado' } },
  comp: {
    '10': { cod: 'A10', d: 'Cpo Una', s: 2, um: 'uni', kg_x_uni: 0.05, uxc: 100 },
    '20': { cod: 'T1', d: 'Terminado uno', s: 12, um: 'uni' },
    '30': { cod: 'B5', d: 'Parte be', s: 2, um: 'uni' },
    '50': { cod: 'CAJ1', d: 'Caja 510', s: 11, um: 'uni' }, // sector Caja = insumo de empaque
  },
  rp: {},
  c2a: {},
  bom_art: {},
  bom_comp: {},
  // el ajuste opera sobre A10 (comp 10) en el sector D1 (ubic 1): una sola ubicacion.
  // Pedernera (ubic 6, PS): A10 procesado en 0 (se muestra) y CAJ1 caja en 0 (SEED, se oculta).
  // B5 (comp 30) esta en DOS lados -el sector y el taller de Martin-: es el caso del usuario,
  // "no se a que sector pertenece el componente". T1 (comp 20) vive en el sector Terminado,
  // que NO tiene boton propio: sin el rubro global no se ve en ningun lado.
  inv: {
    '10:1': { cant: 100, max: 200 }, '30:1': { cant: 50, max: 0 }, '20:5': { cant: 0, max: 0 },
    '10:6': { cant: 0, max: null }, '50:6': { cant: 0, max: null }, '30:3': { cant: 20, max: null },
  },
};
/* Prov AT y transito salen de su propia RPC. */
const EXTRA = {
  prov_at: [{ id: 1, nom: 'Cabral', ubic: 34, filas: [{ cid: 10, cant: 0, max: null }] }],
  transito: [{ cid: 30, ps1: 'Laboratorio FAAT', ps2: 'Guazzaroni Patricio', cant: 7 }],
};
/* stock_sector_bundle por sector: SC (1) es el rubro por defecto; Flejes (5) prueba
   que NO salen las columnas de cajones (pedido del usuario, textual). */
const SECTOR = {
  1: {
    sector: { id: 1, nombre: 'Sector Crudo' }, ubicacion_id: 1, ubicacion_virgilio_id: null,
    filas: [{
      comp_id: 10, cod: 'A10', desc: 'Cpo Una', um: 'uni', kg_x_uni: 0.05, uni_x_cajon: 100,
      online: 100, en_virgilio: null, maximo: 200, n_fleje: null,
      mov: { fabricacion: { ent: 120, sal: 20, n: 3 }, envio_ps: { ent: 0, sal: 80, n: 2 } },
    }],
  },
  5: {
    sector: { id: 5, nombre: 'Sector Fleje' }, ubicacion_id: 9, ubicacion_virgilio_id: null,
    filas: [{
      comp_id: 40, cod: 'F1', desc: 'Fleje uno', um: 'kg', kg_x_uni: 1, uni_x_cajon: null,
      online: 30, en_virgilio: null, maximo: 50, n_fleje: '12',
      mov: { compra: { ent: 60, sal: 0, n: 1 } },
    }],
  },
};
const MOVS = [{
  id: 1, fecha: '2026-08-30T12:00:00', tipo_mov: 'ajuste', comp_id: 10,
  ubic_origen_id: null, ubic_destino_id: 1, cantidad: -5, unidad_origen: 'uni',
  comp_transformado_id: null, cantidad_transformada: null, unidad_destino: 'uni',
}];

const STUB = `
window.__rpc = [];
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    window.__rpc.push({ n: name, a: args || null });
    if (name === 'movimientos_bundle') return { data: JSON.parse(JSON.stringify(${JSON.stringify(BUNDLE)})), error: null };
    if (name === 'stock_general_extra_bundle') return { data: JSON.parse(JSON.stringify(${JSON.stringify(EXTRA)})), error: null };
    if (name === 'stock_sector_bundle') { var S = ${JSON.stringify(SECTOR)}; return { data: S[args.p_sector_id] || { filas: [], ubicacion_id: null }, error: null }; }
    if (name === 'registrar_movimientos') return { data: { ok: true, n: (args.p_rows || []).length }, error: null };
    if (name === 'composicion_stock') return { data: { movs: [] }, error: null };
    return { data: null, error: { message: 'rpc desconocida ' + name } };
  },
  from: function(){ return { select: function(){ return { order: function(){ return { limit: async function(){
    return { data: JSON.parse(JSON.stringify(${JSON.stringify(MOVS)})), error: null };
  } }; } }; } }; }
};}};
`;

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) process.exitCode = 1; };
  const ctx = await browser.newContext({ viewport: { width: 390, height: 800 }, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  page.on('dialog', d => { console.log('DIALOG:', d.message()); d.accept(); });
  await page.route('**/@supabase/supabase-js@2', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/auth-guard.js*', r => r.fulfill({ contentType: 'application/javascript', body: 'window.GP2_AUTH_ON=false;' }));
  await page.route('**/*.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));
  await page.goto(ROOT + '/Stocks%20General/StockGeneral_GP2.html');
  await page.waitForSelector('.rubro-btn');
  // el rubro por defecto (SC) tiene que haber renderizado su fila
  await page.waitForFunction(() => document.querySelectorAll('#tbody tr').length > 0);

  // ── selector de rubros (foto 1) + tabla rica (foto 2) ──
  const base = await page.evaluate(() => ({
    rubros: document.querySelectorAll('.rubro-btn').length,
    horizontal: document.documentElement.scrollWidth > window.innerWidth,
    hAj: document.querySelector('.hlink') ? document.querySelector('.hlink').getBoundingClientRect().height : 0,
    thead: document.getElementById('thead').innerText,
    row: document.querySelector('#tbody tr').innerText,
  }));
  ok(base.rubros >= 12, 'la grilla de rubros renderiza sus botones (' + base.rubros + ')');
  ok(!base.horizontal, 'celular 390px: sin scroll horizontal');
  ok(base.hAj >= 44, 'boton Ajuste tocable (' + Math.round(base.hAj) + 'px, minimo 44)');

  // el pedido central: el stock separado por Kg / Caj / Uni + Info con Uni×Cajón
  ok(/ONLINE/i.test(base.thead) && /\bKG\b/i.test(base.thead) && /\bCAJ\b/i.test(base.thead) && /\bUNI\b/i.test(base.thead),
     'SC: el stock se separa en Kg / Caj / Uni (no una "cantidad" cruda)');
  ok(/KG × UNI/i.test(base.thead) && /UNI × CAJÓN/i.test(base.thead) && /MÁXIMO/i.test(base.thead),
     'SC: bloque Info con Kg×Uni, Uni×Cajón y Máximo');
  ok(/FABRICACIÓN/i.test(base.thead), 'SC: columnas de movimiento propias del sector (Fabricación)');
  // A10: 100 uni, kg_x_uni 0.05 -> 5 kg, uni_x_cajon 100 -> 1 caj
  ok(/A10/.test(base.row) && /\b100\b/.test(base.row) && /\b5\b/.test(base.row),
     'SC: la fila A10 muestra sus Kg/Caj/Uni — ' + base.row.replace(/\s+/g, ' '));

  // ── FLEJES: sin cajones ni Uni×Cajón, con N° Fleje (pedido textual del usuario) ──
  await page.click('.rubro-btn:has-text("Flejes")');
  await page.waitForFunction(() => /F1/.test(document.getElementById('tbody').innerText));
  const fle = await page.evaluate(() => document.getElementById('thead').innerText);
  ok(!/\bCAJ\b/i.test(fle) && !/UNI × CAJÓN/i.test(fle), 'Flejes: NO hay columna de cajones ni Uni×Cajón');
  ok(/N° FLEJE/i.test(fle), 'Flejes: sí aparece N° Fleje');

  // ── Prov. Art. Terminado y Tránsito PS como rubros con su tabla ──
  await page.click('.rubro-btn:has-text("Prov. Art. Term.")');
  await page.waitForFunction(() => /Cabral/.test(document.getElementById('tbody').innerText));
  ok(true, 'Prov. Art. Terminado: aparece el proveedor con sus cajas/cartones (Cabral)');

  await page.click('.rubro-btn:has-text("Tránsito PS")');
  await page.waitForFunction(() => /Laboratorio FAAT → Guazzaroni Patricio/.test(document.getElementById('tbody').innerText));
  ok(true, 'Tránsito PS: aparece el par PS origen → PS siguiente');

  // ── Prov. Servicio: SIN Máximo, y SIN cajas (insumo de empaque sembrado en 0) ──
  await page.click('.rubro-btn:has-text("Prov. Servicio")');
  await page.waitForFunction(() => /Pedernera Ilario/.test(document.getElementById('tbody').innerText));
  const ps = await page.evaluate(() => ({
    thead: document.getElementById('thead').innerText,
    body: document.getElementById('tbody').innerText,
  }));
  ok(!/MÁXIMO/i.test(ps.thead), 'PS: la tabla NO tiene columna Máximo (el maximo vive en el sector procesado)');
  ok(/A10/.test(ps.body), 'PS: se ve la pieza procesada que el PS cromaria (A10)');
  ok(!/CAJ1/.test(ps.body), 'PS: NO aparece la caja (insumo de empaque sembrado en 0 en el PS)');

  // ── BUSCAR SIN SABER EL RUBRO (v2.1.0) ──
  // 1) el rubro "Todos": una tabla con todo el inventario, con Rubro + Dónde y sin movimientos
  await page.click('.rubro-btn:has-text("Todos los rubros")');
  await page.waitForFunction(() => /Martin/.test(document.getElementById('tbody').innerText));
  const glo = await page.evaluate(() => ({
    thead: document.getElementById('thead').innerText,
    body: document.getElementById('tbody').innerText,
    horizontal: document.documentElement.scrollWidth > window.innerWidth,
  }));
  ok(/RUBRO/i.test(glo.thead) && /DÓNDE/i.test(glo.thead), 'Todos: la tabla dice en qué rubro y en qué lugar está cada fila');
  ok(!/FABRICACIÓN/i.test(glo.thead), 'Todos: sin columnas de movimiento (cada rubro tiene las suyas)');
  ok(!glo.horizontal, 'Todos: celular 390px sin scroll horizontal');
  ok(/T1/.test(glo.body) && /Terminado/.test(glo.body),
     'Todos: aparece lo que NO tiene botón propio (T1 en el sector Terminado), antes invisible');

  // 2) el mismo código en dos lugares distintos, de un saque
  await page.fill('#q', 'B5');
  await page.waitForFunction(() => document.querySelectorAll('#tbody tr').length === 3);
  const b5 = await page.locator('#tbody').innerText();
  ok(/Martin/.test(b5) && /D1/.test(b5) && /Laboratorio FAAT/.test(b5),
     'Todos: B5 se ve de un saque en sus tres lugares (sector, tallerista y tránsito) — ' + b5.replace(/\s+/g, ' '));

  // 3) desde adentro de un rubro, el renglón "También en: …" y el salto en un click
  await page.click('.rubro-btn:has-text("Stock SC")');
  await page.waitForFunction(() => !document.getElementById('hintOtros').classList.contains('hidden'));
  const hint = await page.locator('#hintOtros').innerText();
  ok(/También en otros rubros/i.test(hint) && /Talleristas/.test(hint),
     'dentro de SC, buscar B5 avisa en qué otros rubros está — ' + hint.replace(/\s+/g, ' '));
  ok(await page.locator('#tblEmpty').isVisible(), 'SC no tiene B5: antes la pantalla solo decía "Sin resultados"');
  await page.click('#hintOtros a:has-text("Talleristas")');
  await page.waitForFunction(() => /Martin/.test(document.getElementById('tbody').innerText));
  const salto = await page.evaluate(() => ({ q: document.getElementById('q').value, body: document.getElementById('tbody').innerText }));
  ok(salto.q === 'B5' && /B5/.test(salto.body), 'el salto conserva lo buscado y muestra la fila en el otro rubro');

  // 4) en "Todos", la celda del rubro también lleva a esa pantalla
  await page.click('.rubro-btn:has-text("Todos los rubros")');
  await page.waitForFunction(() => document.querySelectorAll('#tbody td.rub-cell').length > 0);
  await page.click('#tbody td.rub-cell:has-text("Talleristas")');
  await page.waitForFunction(() => document.title.indexOf('Talleristas') >= 0);
  ok(true, 'Todos: click en el rubro de la fila abre ese rubro');
  await page.fill('#q', '');

  // ── ultimos movimientos (vista heredada de Registrar_Movimiento) ──
  await page.click('#grpMovs > summary');
  const movTxt = await page.locator('#tbodyMovs').innerText();
  ok(/Ajuste/i.test(movTxt) && /A10/.test(movTxt) && /D1/.test(movTxt), 'ultimos movimientos: fila con tipo, componente y destino');

  // ── AJUSTE: modal con teclado decimal y payload EXACTO ──
  await page.click('.hlink:has-text("Ajuste")');
  await page.waitForSelector('#modalBg.on');
  const accA = await page.evaluate(() => {
    const q = document.getElementById('f_qty');
    return {
      inputmode: q.getAttribute('inputmode'),
      fs: parseFloat(getComputedStyle(q).fontSize),
      fsSel: parseFloat(getComputedStyle(document.getElementById('f_comp')).fontSize),
    };
  });
  ok(accA.inputmode === 'decimal', 'ajuste: la cantidad abre teclado decimal (admite -/+ con coma)');
  ok(accA.fs >= 18 && accA.fsSel >= 18, 'ajuste: campos de carga >=18px (' + accA.fs + '/' + accA.fsSel + ')');
  await page.selectOption('#f_comp', '10');
  const ubicVal = await page.evaluate(() => document.getElementById('f_ubic').value);
  ok(ubicVal === '1', 'ajuste: la unica ubicacion del componente queda elegida sola (' + ubicVal + ')');
  await page.fill('#f_qty', '-5');
  await page.click('#btnSave');
  await page.waitForFunction(() => window.__rpc.some(c => c.n === 'registrar_movimientos'));
  const call1 = await page.evaluate(() => window.__rpc.find(c => c.n === 'registrar_movimientos'));
  const rowsA = call1.a.p_rows;
  ok(rowsA.length === 1, 'ajuste: 1 sola fila de movimiento');
  const rA = rowsA[0] || {};
  ok(rA.tipo_mov === 'ajuste' && rA.comp_id === 10 && rA.ubic_origen_id === null &&
     rA.ubic_destino_id === 1 && rA.cantidad === -5 && rA.unidad_origen === 'uni' &&
     rA.unidad_destino === 'uni' && rA.comp_transformado_id === null,
     'ajuste: payload identico al de Registrar_Movimiento — ' + JSON.stringify(rA));
  ok(/T12:00:00$/.test(rA.fecha || ''), 'ajuste: la fecha viaja con T12:00:00 como siempre (' + rA.fecha + ')');

  // el stock se recarga despues de cada registro (reload -> movimientos_bundle de nuevo)
  const nBundle = await page.evaluate(() => window.__rpc.filter(c => c.n === 'movimientos_bundle').length);
  ok(nBundle >= 2, 'despues de cada registro se recarga el bundle (' + nBundle + ' cargas)');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
