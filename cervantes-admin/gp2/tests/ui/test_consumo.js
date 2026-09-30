/* Consumo x Componente v1.1.0 (2026-09-23).
 *
 * El pedido del usuario, textual: "un modulo que pueda ver por componente, por sector, el
 * consumo... en PB6 cuando toco el maximo me dice en que articulo se usa. Bueno, lo quiero
 * eso, pero afuera. Otro modulo aparte". Este test fija lo que hace que el modulo sirva:
 *   - el selector por SECTOR con la cuenta de componentes, mas "Todos los sectores";
 *   - la UNIDAD no se mezcla: fleje y resina en kg, el resto en unidades;
 *   - el orden es por consumo de MAYOR a MENOR (dentro del sector), nunca alfabetico;
 *   - la columna Sector aparece solo en "Todos" (adentro de un sector seria una columna
 *     con el mismo valor en todas las filas);
 *   - tocar la fila abre el sustento por ARTICULO (el popup compartido consumo-detalle.js);
 *   - y en una RESINA ese mismo popup muestra PIEZAS, no articulos: una resina no esta en
 *     ninguna receta, y antes de este cambio el popup decia "ningun articulo llega a esta
 *     parte" justo donde hay mas kg en juego;
 *   - render celular 390px: sin scroll horizontal y con los botones tocables;
 *   - y NO hay columna ni KPI de "Cajones / mes" (sacada el 23/09 por pedido del usuario:
 *     uni_x_cajon no esta cargado en todos los componentes y hay partes que no van en cajon,
 *     asi que la columna era una fila de guiones). El fixture SIGUE trayendo cajones_mes,
 *     porque consumo_bundle lo sigue devolviendo: lo que se fija es que la pantalla lo ignore.
 */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

/* Volumen de juguete con la forma real: un sector de unidades (Cartón, 2 filas), uno de kg
   por fleje y uno de kg por resina. Los sectores vienen ordenados por cantidad, como la RPC. */
const BUNDLE = {
  sectores: [
    { id: 10, nombre: 'Sector Cartón', n: 2, unidad: 'uni', uni_mes: 1500, kg_mes: null, cajones_mes: null },
    { id: 5, nombre: 'Sector Fleje', n: 1, unidad: 'kg', uni_mes: 23750, kg_mes: 871.5, cajones_mes: null },
    { id: 14, nombre: 'Sector Bolsas Plásticas', n: 1, unidad: 'kg', uni_mes: null, kg_mes: 807, cajones_mes: null },
  ],
  filas: [
    // a proposito PRIMERO el mas chico: si la pantalla no ordena, E3B queda arriba de T3B
    { comp_id: 2, cod: 'E3B', desc: 'Carton Espatula', sector_id: 10, sector: 'Sector Cartón',
      um: 'uni', kg_x_uni: null, uni_x_cajon: null, es_fleje: false, es_resina: false,
      base: 'articulos', uni_mes: 300, kg_mes: null, cajones_mes: null, en_articulos: 1 },
    { comp_id: 1, cod: 'T3B', desc: 'Carton Sacacorcho', sector_id: 10, sector: 'Sector Cartón',
      um: 'uni', kg_x_uni: null, uni_x_cajon: 600, es_fleje: false, es_resina: false,
      base: 'articulos', uni_mes: 1200, kg_mes: null, cajones_mes: 2, en_articulos: 3 },
    { comp_id: 3, cod: 'IE11', desc: 'Fleje N° 30', sector_id: 5, sector: 'Sector Fleje',
      um: 'kg', kg_x_uni: 1, uni_x_cajon: null, es_fleje: true, es_resina: false,
      base: 'articulos', uni_mes: 23750, kg_mes: 871.5, cajones_mes: null, en_articulos: 2 },
    { comp_id: 4, cod: '2405', desc: 'PP 2630 (Polipropileno)', sector_id: 14, sector: 'Sector Bolsas Plásticas',
      um: 'kg', kg_x_uni: null, uni_x_cajon: null, es_fleje: false, es_resina: true,
      base: 'piezas', uni_mes: null, kg_mes: 807, cajones_mes: null, en_articulos: 20 },
  ],
};

const DETALLE = {
  1: {
    comp_id: 1, codigo: 'T3B', descripcion: 'Carton Sacacorcho', sector: 'Sector Cartón',
    es_fleje: false, es_resina: false, base: 'articulos', desperdicio_pct: null,
    uni_x_cajon: 600, total_uni_mes: 1200, total_kg_mes: null, piezas: [],
    articulos: [
      { articulo: '531', familia: 'Sacacorchos', proy_uni_mes: 900, uni_mes: 900, kg_mes: null, receta_directa: true },
      { articulo: '731', familia: 'Sacacorchos', proy_uni_mes: 300, uni_mes: 300, kg_mes: null, receta_directa: true },
    ],
  },
  4: {
    comp_id: 4, codigo: '2405', descripcion: 'PP 2630 (Polipropileno)', sector: 'Sector Bolsas Plásticas',
    es_fleje: false, es_resina: true, base: 'piezas', desperdicio_pct: 4,
    uni_x_cajon: null, total_uni_mes: null, total_kg_mes: 807, articulos: [],
    piezas: [
      { codigo: 'PC10', descripcion: 'Mango LK Espatula', kg_x_uni: 0.015, uni_mes: 14450, kg_mes: 225.42 },
      { codigo: 'PB6', descripcion: 'Inser. Neg. Espat', kg_x_uni: 0.005, uni_mes: 90, kg_mes: 0.47 },
    ],
  },
};

const STUB = `
window.__rpc = [];
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    window.__rpc.push({ n: name, a: args || null });
    if (name === 'consumo_bundle') return { data: JSON.parse(JSON.stringify(${JSON.stringify(BUNDLE)})), error: null };
    if (name === 'consumo_detalle') { var D = ${JSON.stringify(DETALLE)}; return { data: D[args.p_comp_id] || null, error: null }; }
    return { data: null, error: { message: 'rpc desconocida ' + name } };
  },
  from: function(){ return { select: function(){ return { then: function(r){ return Promise.resolve({ data: [], error: null }).then(r); } }; } }; }
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
  await page.goto(ROOT + '/Consumo/Consumo_GP2.html');
  await page.waitForSelector('.sec-btn');
  await page.waitForFunction(() => document.querySelectorAll('#tbody tr').length > 0);

  // ── una sola llamada, sin parametros ──────────────────────────────────
  const rpcs = await page.evaluate(() => window.__rpc.map(x => x.n));
  ok(rpcs.filter(n => n === 'consumo_bundle').length === 1, 'carga con UNA llamada a consumo_bundle');

  // ── selector por SECTOR (lo que pidio el usuario) ─────────────────────
  const secs = await page.evaluate(() => ({
    botones: [...document.querySelectorAll('.sec-btn')].map(b => b.innerText.replace(/\s+/g, ' ').trim()),
    alto: Math.min(...[...document.querySelectorAll('.sec-btn')].map(b => b.getBoundingClientRect().height)),
    horizontal: document.documentElement.scrollWidth > window.innerWidth,
  }));
  ok(secs.botones.length === 4, 'hay un boton por sector mas "Todos" (' + secs.botones.length + ')');
  ok(/Todos los sectores\s*4/.test(secs.botones[0]), 'el primero es Todos, con los 4 componentes — ' + secs.botones[0]);
  ok(secs.botones.some(b => /Sector Cartón\s*2/.test(b)), 'cada sector muestra cuantos componentes tiene');
  ok(secs.alto >= 44, 'botones de sector tocables (' + Math.round(secs.alto) + 'px, minimo 44)');
  ok(!secs.horizontal, 'celular 390px: sin scroll horizontal');

  // ── "Todos": columna Sector, y orden por sector y por consumo ─────────
  const todos = await page.evaluate(() => ({
    thead: document.getElementById('thead').innerText,
    cods: [...document.querySelectorAll('#tbody tr td:first-child')].map(td => td.innerText.trim()),
    filas: [...document.querySelectorAll('#tbody tr')].map(tr => tr.innerText.replace(/\s+/g, ' ').trim()),
    fuente: parseFloat(getComputedStyle(document.querySelector('#tbody td')).fontSize),
    celdas: document.querySelectorAll('#tbody tr:first-child td').length,
    kpis: document.getElementById('kpis').innerText.replace(/\s+/g, ' '),
  }));
  ok(/SECTOR/i.test(todos.thead), 'Todos: la tabla dice de que sector es cada componente');
  ok(todos.cods.join(',') === 'T3B,E3B,IE11,2405',
     'Todos: ordenado por sector y, adentro, por consumo de mayor a menor — ' + todos.cods.join(','));
  ok(todos.fuente >= 16, 'letra de tabla >= 16px (' + todos.fuente + ')');

  // ── "Cajones / mes" NO existe mas (23/09) ─────────────────────────────
  ok(!/CAJON/i.test(todos.thead), 'no hay columna "Cajones / mes" — ' + todos.thead.replace(/\s+/g, ' '));
  ok(todos.celdas === 5, 'Todos: 5 columnas (codigo, desc, sector, consumo, en) — ' + todos.celdas);
  ok(!/Cajon/i.test(todos.kpis), 'Todos: ningun KPI de cajones — ' + todos.kpis);
  ok(!/\bcajones\b/i.test(todos.filas.join(' | ')),
     'ninguna fila muestra cajones, ni la que los tiene cargados (T3B, 2 cajones en el bundle)');

  // ── la unidad no se mezcla: kg donde es kg, uni donde es uni ──────────
  ok(/1\.200 uni/.test(todos.filas[0]), 'Cartón: el consumo va en unidades — ' + todos.filas[0]);
  ok(/871,5 kg/.test(todos.filas[2]), 'Fleje: el consumo va en kg, no en piezas — ' + todos.filas[2]);
  ok(/807 kg/.test(todos.filas[3]), 'Resina: el consumo va en kg — ' + todos.filas[3]);
  ok(/20 pzas/.test(todos.filas[3]) && /3 art/.test(todos.filas[0]),
     'la columna "En" dice artículos para una parte y piezas para una resina');

  // ── adentro de un sector: sin la columna Sector, y solo sus filas ─────
  await page.click('.sec-btn:has-text("Sector Cartón")');
  await page.waitForFunction(() => document.querySelectorAll('#tbody tr').length === 2);
  const cart = await page.evaluate(() => ({
    thead: document.getElementById('thead').innerText,
    kpis: document.getElementById('kpis').innerText.replace(/\s+/g, ' '),
  }));
  ok(!/SECTOR/i.test(cart.thead), 'dentro de un sector NO se repite la columna Sector');
  ok(/1\.500 uni/.test(cart.kpis), 'el sector muestra su consumo total del mes — ' + cart.kpis);
  ok(!/Cajon/i.test(cart.kpis), 'dentro de un sector tampoco hay KPI de cajones — ' + cart.kpis);
  ok(!/CAJON/i.test(cart.thead), 'dentro de un sector tampoco esta la columna de cajones');

  // ── buscar ────────────────────────────────────────────────────────────
  await page.fill('#q', 'E3B');
  await page.waitForFunction(() => document.querySelectorAll('#tbody tr').length === 1);
  ok(true, 'la busqueda filtra dentro del sector abierto');
  await page.fill('#q', '');

  // ── el sustento POR ARTICULO (lo que el usuario queria sacar de la O.C.) ──
  await page.click('#tbody tr:first-child');
  await page.waitForSelector('#cdOverlay');
  const pop = await page.evaluate(() => document.getElementById('cdCard').innerText.replace(/\s+/g, ' '));
  ok(/T3B/.test(pop) && /artículo que lo usa/i.test(pop), 'tocar la fila abre el sustento por articulo');
  ok(/531/.test(pop) && /731/.test(pop), 'el popup lista los articulos que piden la parte — ' + pop.slice(0, 90));
  await page.click('#cdCard .cd-cerrar');

  // ── RESINA: el mismo popup, pero por PIEZA ────────────────────────────
  await page.click('.sec-btn:has-text("Bolsas Plásticas")');
  await page.waitForFunction(() => /2405/.test(document.getElementById('tbody').innerText));
  await page.click('#tbody tr:first-child');
  await page.waitForSelector('#cdOverlay');
  const res = await page.evaluate(() => document.getElementById('cdCard').innerText.replace(/\s+/g, ' '));
  ok(/pieza que se inyecta con ella/i.test(res), 'resina: el sustento son las piezas, no los articulos');
  ok(/PC10/.test(res) && /225,42 kg/.test(res), 'resina: cada pieza con sus kg/mes — ' + res.slice(0, 110));
  ok(/desperdicio 4%/.test(res), 'resina: el total avisa que el desperdicio ya esta adentro');
  ok(!/Ningún artículo/.test(res), 'resina: ya NO dice "ningún artículo llega a esta parte"');

  await browser.close();
})();
