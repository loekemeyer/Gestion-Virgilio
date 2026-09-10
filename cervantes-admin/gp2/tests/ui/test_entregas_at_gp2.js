/* Entrega Prov AT nativa de GP2 (idea 7216). La pantalla vieja escribia en el
   esquema del vecino; esta escribe en GP2 por RPC. El test fija: que use el
   cliente con schema GP2, la carga por proveedor, el buffer en memoria (y su
   aviso al cambiar de proveedor), el payload de crear_entrega_prov_at, que lo
   registrado salga del buffer para que un reintento no duplique, y las reglas
   de pantalla de la casa (letra grande, tactil 44px, 390px sin desborde). */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

let fallas = 0;
const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) { fallas++; process.exitCode = 1; } };

const BUNDLE = {
  provs: [ { id: 2, nombre: 'Carriero', arts: 2 }, { id: 10, nombre: 'Pintos', arts: 1 } ],
  arts: [
    { id: 1, prov_id: 2,  cod_art: '122', descripcion: 'Rallador Cilin Loke', n_caja: 2, marca: null },
    { id: 2, prov_id: 2,  cod_art: '321', descripcion: 'Rallador Cilindrico', n_caja: 2, marca: null },
    { id: 3, prov_id: 10, cod_art: '225', descripcion: 'Pava 1L', n_caja: 6, marca: null },
  ],
  ultimas: [ { id: 125, fecha: '2026-08-28', prov: 'Carriero', cod_art: '321',
               descripcion: 'Rallador Cilindrico', cajas: 50, remito: '01740', facturada: true } ],
};

const STUB = `
window.__rpc = [];
window.__schema = null;
window.supabase = { createClient: function(u, k, o){
  window.__schema = o && o.db ? o.db.schema : null;
  return { rpc: function(nombre, args){
    window.__rpc.push({ nombre: nombre, args: args });
    if (nombre === 'entregas_prov_at_bundle') return Promise.resolve({ data: ${JSON.stringify(BUNDLE)}, error: null });
    return Promise.resolve({ data: { ok: true, id: 999 }, error: null });
  } };
} };
`;

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  page.on('pageerror', e => { console.log('PAGEERROR: ' + e.message); process.exitCode = 1; fallas++; });
  const dialogos = [];
  page.on('dialog', d => { dialogos.push(d.message()); d.accept(); });
  await page.addInitScript(STUB);
  await page.route('**/cdn.jsdelivr.net/**', r => r.fulfill({ status: 200, contentType: 'application/javascript', body: '' }));
  await page.goto(ROOT + '/Prov%20Art%20Terminado/Entregas/EntregasAT_GP2.html', { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(500);

  ok(await page.evaluate(() => window.__schema) === 'GP2',
     'el cliente apunta al esquema GP2, no a public');
  ok((await page.evaluate(() => window.__rpc))[0].nombre === 'entregas_prov_at_bundle',
     'arranca pidiendo el bundle por RPC (un solo viaje)');

  const provs = await page.$$eval('.prov-btn', bs => bs.map(b => b.textContent.replace(/\s+/g, ' ').trim()));
  ok(provs.length === 2 && /Carriero/.test(provs[0]), 'pinta los proveedores con su cantidad de articulos');

  // fecha de hoy precargada
  ok(/^\d{4}-\d{2}-\d{2}$/.test(await page.inputValue('#fecha')), 'la fecha viene con el dia de hoy');

  await page.click('.prov-btn');                      // Carriero
  await page.waitForTimeout(200);
  ok((await page.$$('#tbody tr')).length === 2, 'muestra solo los articulos de ese proveedor');

  // el buscador filtra
  await page.fill('#q', '321'); await page.waitForTimeout(150);
  ok((await page.$$('#tbody tr')).length === 1, 'el buscador filtra por codigo');
  await page.fill('#q', ''); await page.waitForTimeout(150);

  // separador de miles al tipear (regla de la casa, gp2-numero.js)
  const inp = await page.$('.caj-in');
  await inp.click();
  await page.keyboard.type('1200', { delay: 10 });
  ok(await inp.inputValue() === '1.200', 'el campo de cajas pone el separador de miles solo');

  await page.keyboard.press('Tab');
  await page.waitForTimeout(200);
  ok(/\(1 art\.\)/.test(await page.textContent('#btnConf')), 'el boton cuenta lo cargado');
  ok(await page.getAttribute('#btnConf', 'disabled') === null, 'el boton se habilita con carga');

  // avisa antes de perder lo cargado al cambiar de proveedor
  await page.click('.prov-btn:nth-child(2)');
  await page.waitForTimeout(200);
  ok(dialogos.some(d => /se pierden/.test(d)), 'avisa antes de borrar el buffer al cambiar de proveedor');

  // volver a Carriero y registrar
  await page.click('.prov-btn:nth-child(1)');
  await page.waitForTimeout(200);
  const inp2 = await page.$('.caj-in');
  await inp2.click(); await page.keyboard.type('12', { delay: 10 });
  await page.keyboard.press('Tab'); await page.waitForTimeout(200);
  await page.fill('#remito', 'R-88');
  await page.click('#btnConf');
  await page.waitForTimeout(600);

  const llamadas = await page.evaluate(() => window.__rpc);
  const alta = llamadas.filter(c => c.nombre === 'crear_entrega_prov_at');
  ok(alta.length === 1, 'registra una llamada por articulo (' + alta.length + ')');
  if (alta.length) {
    const a = alta[0].args;
    ok(a.p_prov_at_id === 2 && a.p_cod_art === '122' && a.p_cajas === 12 && a.p_remito === 'R-88',
       'payload correcto — ' + JSON.stringify(a));
    ok(/^\d{4}-\d{2}-\d{2}$/.test(a.p_fecha), 'la fecha viaja como fecha, no como texto libre');
  }
  ok(/registrada/.test(await page.textContent('#status')), 'avisa que quedo registrada');
  ok(await page.evaluate(() => Object.keys(window.CARGA || {}).length) === 0 ||
     await page.getAttribute('#btnConf', 'disabled') !== null,
     'lo registrado sale del buffer (un reintento no duplica)');

  // reglas de pantalla de la casa
  const chicos = await page.$$eval('input, select', els => els
    .filter(e => e.offsetParent && parseFloat(getComputedStyle(e).fontSize) < 18)
    .map(e => (e.id || e.className) + ':' + getComputedStyle(e).fontSize));
  ok(chicos.length === 0, 'ningun campo por debajo de 18px' + (chicos.length ? ' — ' + chicos.join(', ') : ''));

  const chicosTactil = await page.$$eval('button, a.btn', els => els
    .filter(e => e.offsetParent && e.getBoundingClientRect().height > 0 && e.getBoundingClientRect().height < 44)
    .map(e => (e.id || e.className) + ':' + Math.round(e.getBoundingClientRect().height)));
  ok(chicosTactil.length === 0, 'ninguna zona tactil por debajo de 44px' + (chicosTactil.length ? ' — ' + chicosTactil.join(', ') : ''));

  const sw = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  ok(sw === 0, 'sin scroll horizontal a 390px (desborde=' + sw + ')');

  await browser.close();
  console.log(fallas ? 'HAY FALLOS' : 'TODO OK');
})();
