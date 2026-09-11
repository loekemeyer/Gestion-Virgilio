/* Faltantes/Faltantes_GP2.html — faltantes automaticos por stock online +
   marcas manuales persistidas. Fija: orden por gravedad (falt auto > marca >
   resto), pills de faltante y "la ubicacion no alcanza", tabs Crudo/Procesado,
   aviso de pendientes sin uni_x_cajon, Resolver y + Marcar faltante (RPCs), y
   render en 390px sin scroll horizontal. Supabase STUBEADO. */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const BUNDLE = {
  max_cajones: 5,
  umbral_cajones: 1,
  estado: [
    { comp_id: 36, cod: 'K5', desc: 'Cpo Sacacorcho LK p/Armar', sector_id: 1, stock: 0, uxc: 957,
      caj_stock: 0, consumo_mes: 4153, maximo: 4785, cob_dias: 0, cob_llena_dias: 34.6,
      falt_auto: true, ubic_corta: false },
    { comp_id: 29, cod: 'J2', desc: 'Cuerpo Una c/M p/Pintar', sector_id: 1, stock: 0, uxc: 1685,
      caj_stock: 0, consumo_mes: 12627, maximo: 8425, cob_dias: 0, cob_llena_dias: 20,
      falt_auto: true, ubic_corta: true },
    { comp_id: 50, cod: 'M6', desc: 'Mango Pelapapa LK', sector_id: 1, stock: 5000, uxc: 1000,
      caj_stock: 5, consumo_mes: 3000, maximo: 5000, cob_dias: 50, cob_llena_dias: 50,
      falt_auto: false, ubic_corta: false },
    { comp_id: 60, cod: 'N1', desc: 'Ahuecafruta', sector_id: 1, stock: 2000, uxc: 1000,
      caj_stock: 2, consumo_mes: 1000, maximo: 5000, cob_dias: 60, cob_llena_dias: 150,
      falt_auto: false, ubic_corta: false },
    { comp_id: 85, cod: 'A10', desc: 'Cpo Una LK C/M Pint.', sector_id: 2, stock: 180, uxc: 1695,
      caj_stock: 0.11, consumo_mes: 12627, maximo: 8475, cob_dias: 0.4, cob_llena_dias: 20.1,
      falt_auto: true, ubic_corta: true },
  ],
  marcas: [
    { id: 9, comp_id: 60, cod: 'N1', desc: 'Ahuecafruta', sector_id: 1,
      origen: 'envios_tall', nota: 'no hay', por: 'martin', creado_en: '2026-08-31T10:00:00-03:00' },
  ],
  pendientes_uxc: [
    { comp_id: 99, cod: 'Z12', desc: 'Tapa Espumadera', sector_id: 2 },
  ],
};

const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    window.__calls = window.__calls || [];
    window.__calls.push({name:name, args:args});
    if(name==='faltantes_estado_bundle') return { data: ${JSON.stringify(BUNDLE)}, error: null };
    if(name==='marcar_faltante') return { data: { ok: true, id: 11 }, error: null };
    if(name==='resolver_faltante') return { data: { ok: true, resueltos: 1 }, error: null };
    return { data: null, error: { message: 'rpc desconocida '+name } };
  }
};}};
`;

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  const dialogs = [];
  page.on('dialog', d => { dialogs.push({ type: d.type(), msg: d.message() }); d.accept(); });

  await page.route('**/@supabase/supabase-js@2**', r =>
    r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/GP2_favicon.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));

  await page.goto(ROOT + '/Faltantes/Faltantes_GP2.html');
  await page.waitForFunction(() => document.querySelectorAll('#tbody tr').length > 0);

  const ok = (c, msg) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + msg); if (!c) process.exitCode = 1; };

  // tab Crudo por defecto: 4 filas ordenadas por gravedad (falt auto > marca > resto)
  let cods = await page.$$eval('#tbody tr td:first-child .cod', xs => xs.map(x => x.textContent));
  ok(cods.join(',') === 'J2,K5,N1,M6', 'orden por gravedad J2,K5,N1,M6 — dio ' + cods.join(','));
  ok((await page.$eval('#status', e => e.textContent)).includes('4 componentes de Crudo'), 'status 4 de Crudo');

  // KPIs
  ok((await page.$eval('#kFalt', e => e.textContent)) === '2', 'KPI faltantes autom = 2');
  ok((await page.$eval('#kMarcas', e => e.textContent)) === '1', 'KPI marcas abiertas = 1');
  ok((await page.$eval('#kCortas', e => e.textContent)) === '1', 'KPI ubicacion corta = 1');

  // fila J2 (faltante + ubicacion corta): pill roja + diagnostico
  const j2 = await page.$eval('#tbody tr:first-child', e => e.textContent);
  ok(j2.includes('menos de 1 cajón: 0 uni'), 'pill faltante "menos de 1 cajon: 0 uni"');
  ok(j2.includes('la ubicación no alcanza') && j2.includes('20 días'), 'J2: llena alcanza 20 dias + ⚠ no alcanza');
  ok(await page.$eval('#tbody tr:first-child', e => e.classList.contains('r-falt')), 'fila J2 en rojo');

  // K5: llena alcanza 34,6 dias y SIN etiqueta de ubicacion corta
  const k5 = await page.$eval('#tbody tr:nth-child(2)', e => e.textContent);
  ok(k5.includes('34,6 días') && !k5.includes('no alcanza'), 'K5: 34,6 dias llena, sin ⚠');
  ok(k5.includes('4.785'), 'K5: maximo 4.785 uni (5 cajones x 957)');

  // N1: marca manual abierta con origen, nota, quien y boton Resolver
  const n1 = await page.$eval('#tbody tr:nth-child(3)', e => e.textContent);
  ok(n1.includes('Envíos Tallerista') && n1.includes('no hay') && n1.includes('martin'), 'N1: badge de la marca');
  ok(await page.$eval('#tbody tr:nth-child(3)', e => e.classList.contains('r-marca')), 'fila N1 en ambar');

  // accesibilidad: sin scroll horizontal en 390px, touch >= 44px
  const scrollW = await page.evaluate(() => document.documentElement.scrollWidth);
  ok(scrollW <= 390, 'sin scroll horizontal en 390px (scrollWidth=' + scrollW + ')');
  const hTab = await page.$eval('#tabCrudo', e => e.getBoundingClientRect().height);
  ok(hTab >= 44, 'tab tocable >= 44px (' + hTab + ')');
  const hRes = await page.$eval('.btn-resolver', e => e.getBoundingClientRect().height);
  ok(hRes >= 44, 'Resolver tocable >= 44px (' + hRes + ')');

  // tab Procesado: 1 fila (A10) + aviso del pendiente sin uni_x_cajon (Z12)
  await page.click('#tabProc');
  cods = await page.$$eval('#tbody tr td:first-child .cod', xs => xs.map(x => x.textContent));
  ok(cods.join(',') === 'A10', 'tab Procesado: solo A10');
  ok(!(await page.$eval('#avisoUxc', e => e.classList.contains('hidden'))), 'aviso pendientes visible');
  ok((await page.$eval('#avisoUxc', e => e.textContent)).includes('Z12'), 'aviso lista Z12 sin uni x cajon');

  // volver a Crudo y resolver la marca de N1
  await page.click('#tabCrudo');
  await page.click('.btn-resolver');
  await page.waitForFunction(() => (window.__calls || []).some(c => c.name === 'resolver_faltante'));
  ok(dialogs.some(d => d.type === 'confirm' && d.msg.includes('N1')), 'confirm de resolver nombra N1');
  const rf = await page.evaluate(() => (window.__calls || []).filter(c => c.name === 'resolver_faltante'));
  ok(rf.length === 1 && rf[0].args.p_id === 9, 'resolver_faltante(p_id 9): ' + JSON.stringify(rf[0].args));
  await page.waitForFunction(() => (window.__calls || []).filter(c => c.name === 'faltantes_estado_bundle').length >= 2);
  ok(true, 'recarga el bundle tras resolver');

  // + Marcar faltante: popup, select con los del tab, nota y usuario -> RPC manual
  await page.click('#btnMarcar');
  ok(!(await page.$eval('#ovMarcar', e => e.classList.contains('hidden'))), 'popup marcar visible');
  const opts = await page.$$eval('#mComp option', xs => xs.map(x => x.textContent));
  ok(opts.length === 4 && opts[0].startsWith('J2'), 'select con 4 componentes de Crudo, orden alfabetico');
  await page.selectOption('#mComp', '36');
  await page.fill('#mNota', 'se acabo');
  await page.fill('#mUser', 'thomas');
  await page.click('#mConfirmar');
  await page.waitForFunction(() => (window.__calls || []).some(c => c.name === 'marcar_faltante'));
  const mf = await page.evaluate(() => (window.__calls || []).filter(c => c.name === 'marcar_faltante'));
  ok(mf.length === 1 && mf[0].args.p_comp_id === 36 && mf[0].args.p_origen === 'manual' &&
     mf[0].args.p_nota === 'se acabo' && mf[0].args.p_usuario === 'thomas',
     'marcar_faltante manual: ' + JSON.stringify(mf[0].args));
  await page.waitForFunction(() => document.getElementById('ovMarcar').classList.contains('hidden'));
  ok(true, 'popup se cierra y recarga');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
