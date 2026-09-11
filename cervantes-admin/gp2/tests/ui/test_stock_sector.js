/* StockSector/StockSector_GP2.html?sector=N — UNA pantalla para el stock de cada
   sector (2026-09-04). Reemplazo a 9 HTML casi iguales (Stock SC/SP/en Movimiento
   y Cajas/Cartones/Partes Plasticas/Remaches/Bombillas/Garage) que solo
   cambiaban su STOCK_CFG. Este test fija que, con cada ?sector=, la pantalla
   se vea IGUAL que la vieja: mismo <title> y h1, mismos botones del header en
   el mismo orden (con los "Control ..." destacados en azul), mismos filtros,
   mismo placeholder y mismas columnas de Movimientos; que los links del header
   apunten a archivos que existen; que el menu mande a cada rotulo al sector
   correcto; que el popup de detalle siga andando; y que en un celular (390px)
   no haya scroll horizontal, el buscador tenga >=18px y todo lo tocable >=44px.
   Supabase STUBEADO: no toca la base. */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT_DIR = path.resolve(__dirname, '..', '..');
const ROOT = 'file://' + ROOT_DIR.replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);
const PAGINA = 'StockSector/StockSector_GP2.html';

/* Un mismo juego de filas para todos los sectores: A10 tiene movimientos de
   todos los tipos, asi cada columna de cada sector tiene algo que sumar. */
const FILAS = [
  { comp_id: 10, cod: 'A10', desc: 'Cpo Uña LK', online: 1200, kg_x_uni: 0.0331, uni_x_cajon: 1695, minimo: 2000, maximo: 5000,
    mov: { compra: { ent: 500, sal: 0 }, consumo_prod: { ent: 0, sal: 300 }, fabricacion: { ent: 800, sal: 100 },
           envio_ps: { ent: 0, sal: 200 }, entrega_ps: { ent: 150, sal: 0 }, envio_tallerista: { ent: 0, sal: 50 } } },
  { comp_id: 11, cod: 'B5', desc: 'Parte be', online: 0, kg_x_uni: null, uni_x_cajon: null, minimo: null, maximo: null, mov: {} },
  { comp_id: 12, cod: 'C7', desc: 'Pieza tras M12', online: 40, kg_x_uni: 0.01, uni_x_cajon: 500, minimo: null, maximo: null,
    mov: { produccion: { ent: 100, sal: 60 } } },
];
const MOVS = [
  { fecha: '2026-09-01', tipo: 'fabricacion', contraparte: 'M12', cantidad: 800, signo: 'ent', cajones: 0.5, via: null, faltante: false },
  { fecha: '2026-09-02', tipo: 'envio_ps', contraparte: 'Charcas', cantidad: 200, signo: 'sal', cajones: null, via: null, faltante: false },
  { fecha: '2026-09-03', tipo: 'compra', contraparte: 'Basconia', cantidad: 500, signo: 'ent', cajones: 0.3, via: null, faltante: false },
];
const STUB = `
window.__rpc = [];
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    window.__rpc.push({ n: name, a: args || null });
    if (name === 'stock_sector_bundle') return { data: { filas: JSON.parse(JSON.stringify(${JSON.stringify(FILAS)})),
      sector: { id: args.p_sector_id, nombre: 'Sector ' + args.p_sector_id }, ubicacion_id: 100 + args.p_sector_id }, error: null };
    if (name === 'composicion_stock') return { data: { movs: JSON.parse(JSON.stringify(${JSON.stringify(MOVS)})) }, error: null };
    return { data: null, error: { message: 'rpc desconocida ' + name } };
  },
  from: function(){ throw new Error('la pantalla no usa from()'); }
};}};
`;

/* Lo que mostraba cada HTML viejo (copiado de ellos antes de borrarlos). */
const CSV = '⬇ Exportar CSV', REC = 'Recepción', ATRAS = 'Atrás';
const COLS_INSUMO = ['Compras', 'Consumo', 'Envíos'];
const PH = 'Buscar por código o descripción…';
const ESPERADO = {
  1:  { titulo: 'Stock SC', h1: 'Stock SC · Sector Crudo', botones: [CSV, 'Stock SP', ATRAS],
        cols: ['Fabricación', 'Envíos'], a10: ['700', '250'] },                         // neto 800-100 | sal envio_ps + envio_tallerista
  2:  { titulo: 'Stock SP', h1: 'Stock SP · Sector Procesado', botones: [CSV, 'Stock SC', ATRAS],
        cols: ['Entregas PS', 'Fabricación', 'Envíos Tallerista', 'Recep. Tallerista'], a10: ['150', '700', '50', '—'] },
  3:  { titulo: 'Stock en Movimiento', h1: 'Stock en Movimiento · Sector Movimiento', botones: [ATRAS],
        cols: ['Fabricado', 'Consumido'], a10: ['800', '400'], sin_min_max: true,
        ph: 'Buscar por código, matriz o descripción…' },                              // ent fabricacion | sal fabricacion+consumo_prod
  // insumos: Compras 500 | Consumo 300+100 | Envíos envio_ps 200 + envio_tallerista 50
  6:  { titulo: 'Partes Plásticas', h1: 'Partes Plásticas · Sector Plástico', botones: [CSV, REC, ATRAS], cols: COLS_INSUMO, a10: ['500', '400', '250'] },
  7:  { titulo: 'Bombillas', h1: 'Bombillas · Sector Bombilla', botones: [CSV, REC, ATRAS], cols: COLS_INSUMO, a10: ['500', '400', '250'] },
  8:  { titulo: 'Remaches', h1: 'Remaches · Sector Remache', botones: [CSV, REC, 'Control Remaches', ATRAS],
        destacado: 'Control Remaches', cols: COLS_INSUMO, a10: ['500', '400', '250'] },
  9:  { titulo: 'Garage', h1: 'Garage · Sector Garage', botones: [CSV, REC, ATRAS], cols: COLS_INSUMO, a10: ['500', '400', '250'] },
  10: { titulo: 'Cartones', h1: 'Cartones · Sector Cartón', botones: [CSV, REC, ATRAS], cols: COLS_INSUMO, a10: ['500', '400', '250'] },
  11: { titulo: 'Cajas', h1: 'Cajas · Sector Caja', botones: [CSV, REC, 'Control Cajas', ATRAS],
        destacado: 'Control Cajas', cols: COLS_INSUMO, a10: ['500', '400', '250'] },
};
// rotulo del menu -> sector (mismos rotulos y mismo orden que tenia el menu con los 9 links)
const MENU_ESPERADO = [['Stock SP', 2], ['Stock SC', 1], ['Stock en Movimiento', 3],
  ['Cajas', 11], ['Cartones', 10], ['Partes Plásticas', 6], ['Remaches', 8], ['Bombillas', 7], ['Garage', 9]];
const VIEJOS = ['StockFlejes/Bombillas_GP2.html', 'StockFlejes/Cajas_GP2.html', 'StockFlejes/Cartones_GP2.html',
  'StockFlejes/Garage_GP2.html', 'StockFlejes/Plasticos_GP2.html', 'StockFlejes/Remaches_GP2.html',
  'StockSC/StockSC_GP2.html', 'StockSP/StockSP_GP2.html', 'StockMovimiento/StockMovimiento_GP2.html'];

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) process.exitCode = 1; };
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  page.on('dialog', d => { console.log('DIALOG:', d.message()); d.accept(); });
  await page.route(/supabase-js@2/, r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/supabase-config.js*', r => r.fulfill({ contentType: 'application/javascript', body: 'self.SUPABASE_URL="x";self.SUPABASE_KEY="y";self.GP2_SB=function(o){return self.supabase.createClient("x","y",o||{db:{schema:"GP2"}});};' }));   // el stub de supabase-config.js trae la fabrica GP2_SB (2026-09-05)
  await page.route('**/GP2_favicon.png*', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));

  const abrir = async (query) => {
    await page.goto(ROOT + '/' + PAGINA + query);
    await page.waitForFunction(() => !/Cargando/.test(document.getElementById('status').textContent));
  };

  // ── cada sector se ve como su HTML viejo ──
  for (const [sec, e] of Object.entries(ESPERADO)) {
    await abrir('?sector=' + sec);
    const m = await page.evaluate(() => {
      const txt = el => el.textContent.trim();
      const hb = [...document.querySelectorAll('#hbtns > *')];
      const filaA10 = document.querySelector('#tbody tr');
      return {
        title: document.title,
        h1: txt(document.getElementById('titulo')),
        botones: hb.map(txt),
        links: hb.filter(x => x.tagName === 'A').map(a => ({ t: txt(a), href: a.getAttribute('href'), style: a.getAttribute('style') || '' })),
        tieneCSV: !!document.getElementById('btnCSV'),
        filtros: [...document.querySelectorAll('.seg-btn')].map(txt),
        ph: document.getElementById('q').placeholder,
        cabeceras: [...document.querySelectorAll('#thead tr:nth-child(2) th')].map(txt),
        kpis: document.querySelectorAll('#kpis .kpi').length,
        aviso: !!document.getElementById('avisoFactores'),
        status: txt(document.getElementById('status')),
        filas: document.querySelectorAll('#tbody tr').length,
        a10mov: filaA10 ? [...filaA10.querySelectorAll('td.mov-cell, td.num.cero')].filter(td => !td.classList.contains('stk-cell')).map(txt) : [],
        rpc: window.__rpc.map(c => c.n + ':' + (c.a && c.a.p_sector_id)),
        horizontal: document.documentElement.scrollWidth > window.innerWidth,
        fsQ: parseFloat(getComputedStyle(document.getElementById('q')).fontSize),
        altoMin: Math.min(...[...document.querySelectorAll('#hbtns > *, .seg-btn')].map(x => x.getBoundingClientRect().height)),
      };
    });
    const tag = 'sector ' + sec + ' (' + e.titulo + ')';
    ok(m.title === e.titulo + ' · GP2', tag + ': <title> "' + m.title + '"');
    ok(m.h1 === e.h1, tag + ': h1 "' + m.h1 + '"');
    ok(JSON.stringify(m.botones) === JSON.stringify(e.botones), tag + ': botones del header en orden ' + JSON.stringify(m.botones));
    ok(m.tieneCSV === e.botones.includes(CSV), tag + ': boton Exportar CSV ' + (e.botones.includes(CSV) ? 'presente' : 'ausente'));
    // los links del header van a archivos reales (los "?sector=" a la misma pantalla)
    for (const l of m.links) {
      const sinQuery = l.href.split('?')[0].split('#')[0];
      const existe = sinQuery === '' ? true : fs.existsSync(path.resolve(ROOT_DIR, 'StockSector', sinQuery));
      ok(existe, tag + ': el link "' + l.t + '" -> ' + l.href + ' existe');
      if (l.t === e.destacado) ok(/#0b5cad/.test(l.style), tag + ': "' + l.t + '" va destacado en azul');
      else ok(l.style === '', tag + ': "' + l.t + '" sin estilo propio');
    }
    if (e.destacado) ok(m.links.some(l => l.t === e.destacado), tag + ': tiene el link ' + e.destacado);
    const filtrosEsp = e.sin_min_max ? ['Todos', 'Con stock', 'Sin stock', 'Con movimientos']
                                     : ['Todos', 'Con stock', 'Sin stock', 'Bajo el máximo', 'Con movimientos'];
    ok(JSON.stringify(m.filtros) === JSON.stringify(filtrosEsp), tag + ': filtros ' + JSON.stringify(m.filtros));
    ok(m.ph === (e.ph || PH), tag + ': placeholder "' + m.ph + '"');
    const cabEsp = ['Código', 'Descripción', 'Kg', 'Caj', 'Uni'].concat(e.cols)
      .concat(['Kg × Uni', 'Uni × Cajón']).concat(e.sin_min_max ? [] : ['Máximo', 'Capacidad']);
    ok(JSON.stringify(m.cabeceras) === JSON.stringify(cabEsp), tag + ': columnas ' + JSON.stringify(m.cabeceras));
    ok(m.kpis === (e.sin_min_max ? 4 : 5), tag + ': ' + m.kpis + ' KPIs' + (e.sin_min_max ? ' (sin "Bajo mínimo")' : ''));
    ok(m.aviso === !e.sin_min_max, tag + ': aviso de factores ' + (e.sin_min_max ? 'ausente' : 'presente'));
    ok(m.filas === FILAS.length && /3 componentes en Sector \d+\./.test(m.status), tag + ': ' + m.filas + ' filas, status "' + m.status + '"');
    ok(JSON.stringify(m.a10mov) === JSON.stringify(e.a10), tag + ': movimientos de A10 por columna ' + JSON.stringify(m.a10mov));
    ok(JSON.stringify(m.rpc) === JSON.stringify(['stock_sector_bundle:' + sec]), tag + ': una sola RPC, con p_sector_id=' + sec + ' (' + m.rpc + ')');
    ok(!m.horizontal, tag + ': celular 390px sin scroll horizontal');
    ok(m.fsQ >= 18, tag + ': buscador con letra grande (' + m.fsQ + 'px)');
    ok(m.altoMin >= 44, tag + ': botones del header y filtros tocables (' + Math.round(m.altoMin) + 'px, minimo 44)');
  }

  // ── el popup de detalle sigue andando en la pantalla unica (Stock SC, columna Fabricación) ──
  await abrir('?sector=1');
  await page.click('#tbody tr td.mov-cell');
  await page.waitForSelector('#popup.open #popBody table');
  const pop = await page.evaluate(() => ({
    titulo: document.getElementById('popTitle').textContent.replace(/\s+/g, ' ').trim(),
    filas: document.querySelectorAll('#popBody tbody tr').length,
    cuerpo: document.getElementById('popBody').textContent,
    rpc: window.__rpc.filter(c => c.n === 'composicion_stock').map(c => c.a),
  }));
  ok(/A10/.test(pop.titulo) && /Fabricación/.test(pop.titulo), 'popup: titulo con el componente y la columna (' + pop.titulo + ')');
  ok(pop.filas === 1 && /800/.test(pop.cuerpo) && !/Basconia/.test(pop.cuerpo), 'popup: solo los movimientos de esa columna (1 fila, +800)');
  ok(pop.rpc.length === 1 && pop.rpc[0].p_comp_id === 10 && pop.rpc[0].p_ubic_id === 101,
     'popup: composicion_stock con el comp y la ubicacion del bundle (' + JSON.stringify(pop.rpc[0]) + ')');
  await page.click('#popClose');
  ok(!(await page.evaluate(() => document.getElementById('popup').classList.contains('open'))), 'popup: Cerrar lo cierra');

  // ── sector desconocido o ausente: aviso claro, sin RPC, sin error de JS ──
  await abrir('?sector=99');
  let s = await page.evaluate(() => ({ status: document.getElementById('status').textContent, rpc: window.__rpc.length,
    botones: [...document.querySelectorAll('#hbtns > *')].map(x => x.textContent.trim()) }));
  ok(/desconocido/.test(s.status) && /1 = Stock SC/.test(s.status) && /11 = Cajas/.test(s.status), 'sector 99: avisa que es desconocido y lista los validos');
  ok(s.rpc === 0 && JSON.stringify(s.botones) === JSON.stringify([ATRAS]), 'sector 99: no llama a la base y deja solo Atrás');
  await abrir('');
  s = await page.evaluate(() => ({ status: document.getElementById('status').textContent, rpc: window.__rpc.length }));
  ok(/Falta el sector/.test(s.status) && s.rpc === 0, 'sin ?sector=: avisa que falta y no llama a la base');

  // ── el menu manda cada rotulo al sector correcto, y los 9 HTML viejos no volvieron ──
  const menu = fs.readFileSync(path.join(ROOT_DIR, 'GP2_MODULOS.html'), 'utf8');
  const links = [...menu.matchAll(/\["([^"]+)",\s*"StockSector\/StockSector_GP2\.html\?sector=(\d+)"\]/g)].map(m => [m[1], Number(m[2])]);
  ok(JSON.stringify(links) === JSON.stringify(MENU_ESPERADO), 'menu: los 9 rotulos van a la pantalla unica con su sector, en el orden de siempre ' + JSON.stringify(links));
  ok(links.every(([rot, sec]) => ESPERADO[sec] && ESPERADO[sec].titulo === rot), 'menu: cada rotulo coincide con el titulo de su sector');
  const mapa = await page.evaluate(() => Object.keys(window.GP2StockSector.SECTORES).map(Number).sort((a, b) => a - b));
  ok(JSON.stringify(mapa) === JSON.stringify(Object.keys(ESPERADO).map(Number).sort((a, b) => a - b)), 'el mapa SECTORES tiene exactamente los 9 sectores (' + mapa + ')');
  const vivos = VIEJOS.filter(v => fs.existsSync(path.join(ROOT_DIR, v)));
  ok(vivos.length === 0, 'los 9 HTML viejos siguen borrados' + (vivos.length ? ' — volvieron: ' + vivos.join(', ') : ''));
  ok(!/(Bombillas|Cajas|Cartones|Garage|Plasticos|Remaches|StockSC|StockSP|StockMovimiento)_GP2\.html/.test(menu), 'menu: ningun link a los HTML viejos');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
