/* Valorizacion GP2: el stock y el pedido-a-maximo salen VALORIZADOS con el motor
 * de costos (monedas separadas + total en pesos con el dolar del cron).
 * Numeros del stub calculados A MANO (mismos casos verificados contra la BD):
 *  - K5 (crudo): mat US$ 0,03135 (31,35 g de fleje a 1 USD/kg) + MO $ 9,60
 *    (1,2+1,8+1,8 = 4,8 s x $2). total = 0,03135x1535 + 9,6 = $ 57,72.
 *    stock 100 -> US$ 3,135 + $ 960 = $ 5.772. pedido 10 -> $ 577,2.
 *  - B4 (procesado) = K5 + pintado 1 USD. total = 1,03135x1535+9,6 = $ 1.592,72.
 *  - A8 (caja): $ 1.000 ARS. stock 5 -> $ 5.000.
 */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const BUNDLE = {
  tc: 1535,
  tc_info: { fecha: '2026-08-28', venta: 1535, fuente: 'dolarapi.com/oficial' },
  costo_seg: 2,
  comps: [
    { comp_id: 1, codigo: 'K5', descripcion: 'Cpo Sacacorcho', sector_id: 1, sector: 'Sector Crudo',
      sector_tipo: 'crudo', origen: 'ruta',
      material_usd: 0.03135, material_pesos: 0, servicios_usd: 0, servicios_pesos: 0,
      segundos_matriz: 4.8, mano_obra_pesos: 9.6, total_pesos: 57.72,
      faltan_precios: 0, faltan_kg: 0, faltan_tiempos: 0,
      stock: 100, maximo: 110, pedido: 10 },
    { comp_id: 2, codigo: 'B4', descripcion: 'Cpo Sacacorcho Pint Azul LK', sector_id: 2, sector: 'Sector Procesado',
      sector_tipo: 'procesado', origen: 'ruta',
      material_usd: 0.03135, material_pesos: 0, servicios_usd: 1, servicios_pesos: 0,
      segundos_matriz: 4.8, mano_obra_pesos: 9.6, total_pesos: 1592.72,
      faltan_precios: 0, faltan_kg: 0, faltan_tiempos: 0,
      stock: 0, maximo: 200, pedido: 200 },
    { comp_id: 3, codigo: 'A8', descripcion: 'Caja x12', sector_id: 11, sector: 'Sector Caja',
      sector_tipo: 'caja', origen: 'precio',
      material_usd: 0, material_pesos: 1000, servicios_usd: 0, servicios_pesos: 0,
      segundos_matriz: 0, mano_obra_pesos: 0, total_pesos: 1000,
      faltan_precios: 0, faltan_kg: 0, faltan_tiempos: 0,
      stock: 5, maximo: 5, pedido: 0 },
    { comp_id: 4, codigo: 'XX', descripcion: 'Sin datos maestros', sector_id: 1, sector: 'Sector Crudo',
      sector_tipo: 'crudo', origen: 'ruta',
      material_usd: 0, material_pesos: 0, servicios_usd: 0, servicios_pesos: 0,
      segundos_matriz: 0, mano_obra_pesos: 0, total_pesos: 0,
      faltan_precios: 1, faltan_kg: 1, faltan_tiempos: 0,
      stock: 0, maximo: 0, pedido: 0 },
  ],
  generado_en: '2026-08-30T10:00:00Z',
};

const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name){
    if(name==='valorizacion_bundle') return { data: ${JSON.stringify(BUNDLE)}, error: null };
    return { data: null, error: { message: 'rpc desconocida '+name } };
  }
};}};
`;

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  page.on('console', m => { if (m.type() === 'error') console.log('CONSOLE:', m.text()); });

  await page.route('**/@supabase/supabase-js@2', r =>
    r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/GP2_favicon.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));

  await page.goto(ROOT + '/Compras/Valorizacion_GP2.html');
  await page.waitForFunction(() => document.getElementById('status').textContent === '');

  const ok = (c, msg) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + msg); if (!c) process.exitCode = 1; };

  // tipo de cambio y $/seg visibles (con que dolar esta valuado)
  const tc = await page.textContent('#tcbar');
  ok(tc.includes('$ 1.535') && tc.includes('28/8/2026') && tc.includes('dolarapi'), 'dolar del cron visible: ' + tc.trim().slice(0, 80));
  ok(tc.includes('$ 2/seg'), 'costo por segundo visible');

  // KPI stock, a mano:
  //   K5: 100 x 0,03135 = US$ 3,135 ; 100 x 9,6 = $ 960 ; total 100 x 57,72 = $ 5.772
  //   A8: 5 x $1000 = $ 5.000 ; total $ 5.000
  //   => US$ 3,14 + $ 5.960 ; total combinado $ 10.772
  const kS = await page.textContent('#kStock');
  ok(kS.includes('US$ 3') && kS.includes('$ 5.960'), 'KPI stock monedas separadas: ' + kS);
  ok((await page.textContent('#kStockConv')).includes('10.772'), 'KPI stock combinado $ 10.772');

  // KPI pedido: K5 10 x 57,72 = 577,2 ; B4 200 x 1.592,72 = 318.544 => $ 319.121
  //   USD: 10x0,03135 + 200x1,03135 = US$ 206,58 ; ARS: 10x9,6 + 200x9,6 = $ 2.016
  const kP = await page.textContent('#kPedido');
  ok(kP.includes('US$ 207') && kP.includes('$ 2.016'), 'KPI pedido monedas separadas: ' + kP);
  ok((await page.textContent('#kPedidoConv')).includes('319.121'), 'KPI pedido combinado $ 319.121');

  // resumen por sector: 3 sectores + fila TOTAL
  ok(await page.$$eval('#tbodySect tr', x => x.length) === 3, '3 sectores en el resumen');
  const foot = await page.textContent('#footSect');
  ok(foot.includes('US$ 3') && foot.includes('10.772') && foot.includes('319.121'), 'fila TOTAL del resumen');

  // por componente: desglose material + servicios + mano de obra
  const filaK5 = await page.textContent('#tbody tr:has-text("K5")');
  ok(filaK5.includes('Mat US$ 0,031') && filaK5.includes('MO $ 9,6') && filaK5.includes('4,8'),
     'desglose K5 (material + MO con segundos)');
  ok(filaK5.includes('$ 57,72'), 'costo unitario combinado K5 $ 57,72');
  ok(filaK5.includes('$ 5.772'), 'valor stock K5 $ 5.772');
  const filaB4 = await page.textContent('#tbody tr:has-text("B4")');
  ok(filaB4.includes('Serv US$ 1'), 'desglose B4 incluye el servicio de pintado');
  ok(filaB4.includes('$ 318.544'), 'valor pedido B4 = 200 x 1.592,72');
  const filaA8 = await page.textContent('#tbody tr:has-text("A8")');
  ok(filaA8.includes('Mat $ 1.000'), 'caja en pesos (ARS) va a la columna de pesos');
  // el que no tiene datos avisa, no inventa
  const filaXX = await page.textContent('#tbody tr:has-text("XX")');
  ok(filaXX.includes('sin precio') && filaXX.includes('sin kg'), 'faltantes marcados con aviso');

  // chip de sector filtra
  await page.click('#sectores .chip:has-text("Caja")');
  ok(await page.$$eval('#tbody tr', x => x.length) === 1, 'chip de sector filtra a 1 fila');
  await page.click('#sectores .chip:has-text("Caja")');

  // buscador
  await page.fill('#q', 'sacacorcho');
  ok(await page.$$eval('#tbody tr', x => x.length) === 2, 'buscador filtra (2 sacacorchos)');
  await page.fill('#q', '');

  // prolijidad 390px: la pagina no scrollea horizontal (las tablas anchas van en .table-wrap)
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  ok(overflow <= 0, 'sin scroll horizontal en 390px (overflow=' + overflow + ')');
  const atras = await page.$eval('.header a', a => a.getBoundingClientRect().height);
  ok(atras >= 40, 'boton Atras tocable (' + Math.round(atras) + 'px)');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
