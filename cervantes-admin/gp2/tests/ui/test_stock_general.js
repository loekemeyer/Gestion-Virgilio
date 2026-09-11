/* Stocks General v1.1.0: la pantalla hereda los DOS flujos propios de la vieja
   Movimientos/Registrar_Movimiento.html (borrada 2026-08-30): Ajuste +/- y
   Armado en fabrica, construidos por el gp2-motor.js REAL (GP2M.ajuste /
   GP2M.armadoFabrica) — este test fija el PAYLOAD EXACTO que le llega a la RPC
   registrar_movimientos, que no debe cambiar de contrato — y la vista de
   ultimos movimientos. Viewport celular (390px): sin scroll horizontal,
   botones tocables (>=44px) y campos de carga >=18px con inputmode. */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const BUNDLE = {
  sect: { '2': { nom: 'D1', tipo: 'crudo' }, '12': { nom: 'Terminado', tipo: 'terminado' } },
  ubic: {
    '1': { tipo: 'sector', ref: 2, nom: 'D1' },
    '2': { tipo: 'tallerista', ref: 3, nom: 'Cervantes (fábrica)' },
    '3': { tipo: 'tallerista', ref: 6, nom: 'Tall Martin' },
    '4': { tipo: 'virgilio', nom: 'Virgilio' },
    '5': { tipo: 'sector', ref: 12, nom: 'Terminado' },
  },
  tall: { '3': { nom: 'Fabrica' }, '6': { nom: 'Martin' } },
  prov_serv: {},
  comp: {
    '10': { cod: 'A10', d: 'Cpo Una', s: 2, um: 'uni' },
    '20': { cod: 'T1', d: 'Terminado uno', s: 12, um: 'uni' },
    '30': { cod: 'B5', d: 'Parte be', s: 2, um: 'uni' },
  },
  // T1 (comp 20) se arma en fabrica: su unica ruta va directo a virgilio sin
  // tallerista externo -> tiene que aparecer en el modal de Armado.
  rp: { '1': [{ o: 1, tipo: 'virgilio', ce: 20, art: 7 }] },
  c2a: { '20': 7 },
  bom_art: { '7': [{ c: 10, q: 2 }, { c: 30, q: 1 }] },
  bom_comp: {},
  inv: { '10:1': { cant: 100, min: 0 }, '30:1': { cant: 50, min: 0 }, '20:5': { cant: 0, min: 0 } },
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
    if (name === 'registrar_movimientos') return { data: { ok: true, n: (args.p_rows || []).length }, error: null };
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
  await page.route('**/gp2-claro.css**', r => r.fulfill({ contentType: 'text/css', body: '' }));
  await page.route('**/*.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));
  await page.goto(ROOT + '/Stocks%20General/StockGeneral_GP2.html');
  await page.waitForSelector('.grp');

  // ── render base: arbol de stock + botones nuevos ──
  const base = await page.evaluate(() => ({
    grupos: document.querySelectorAll('#tree .grp').length,
    horizontal: document.documentElement.scrollWidth > window.innerWidth,
    hAj: document.querySelector('.btn-acc') ? document.querySelector('.btn-acc').getBoundingClientRect().height : 0,
    status: document.getElementById('status').textContent,
  }));
  ok(base.grupos >= 3, 'el arbol de stock renderiza sus grupos (' + base.grupos + ')');
  ok(!base.horizontal, 'celular 390px: sin scroll horizontal');
  ok(base.hAj >= 44, 'botones Ajuste/Armado tocables (' + Math.round(base.hAj) + 'px, minimo 44)');
  ok(/posiciones/.test(base.status), 'el status muestra las posiciones cargadas');

  // ── ultimos movimientos (vista heredada de Registrar_Movimiento) ──
  await page.click('#grpMovs .gh');
  const movTxt = await page.locator('#tbodyMovs').innerText();
  // el tag se ve en MAYUSCULAS por CSS (text-transform), por eso el /i
  ok(/Ajuste/i.test(movTxt) && /A10/.test(movTxt) && /D1/.test(movTxt), 'ultimos movimientos: fila con tipo, componente y destino');

  // ── AJUSTE: modal con teclado decimal y payload EXACTO ──
  await page.click('.btn-acc:has-text("Ajuste")');
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
  // una sola ubicacion posible -> queda seleccionada sola
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
  await page.waitForSelector('#modalBg.on', { state: 'detached' }).catch(() => {});

  // ── ARMADO EN FABRICA: ocultado a pedido del usuario 2026-08-31 ("por ahora").
  // El markup y la logica openArmado() siguen intactas para poder reactivar; el
  // test verifica que el boton este OCULTO (display:none) — si vuelve, cambiar
  // la asercion por el bloque original de armado que quedo en el git blame. ──
  const armBtnVisible = await page.evaluate(() => {
    const btns = Array.from(document.querySelectorAll('.btn-acc'));
    const b = btns.find(x => /armado/i.test(x.textContent || ''));
    if (!b) return { presente: false, visible: false };
    const cs = getComputedStyle(b);
    return { presente: true, visible: cs.display !== 'none' && cs.visibility !== 'hidden' };
  });
  ok(armBtnVisible.presente, 'armado: el boton sigue en el markup (para poder reactivar)');
  ok(!armBtnVisible.visible, 'armado: el boton esta OCULTO (pedido usuario "por ahora")');

  // el stock se recarga despues de cada registro (reload -> movimientos_bundle de nuevo)
  const nBundle = await page.evaluate(() => window.__rpc.filter(c => c.n === 'movimientos_bundle').length);
  ok(nBundle >= 2, 'despues de cada registro se recarga el bundle (' + nBundle + ' cargas)');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
