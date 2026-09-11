const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

/* Despiece x Articulo v2.0.0 = fusion de Verificacion + VerifMadres (pedido del
   usuario: "Que funcione mergeado todo en despiece x articulo"). Este test fija:
   al elegir un articulo se ven receta + ruta trazada + avisos; Confirmar dispara
   la RPC ruta_confirmar con la MISMA firma de deduplicacion de siempre; el
   resumen global cuenta pendientes y el filtro "solo con pendientes" filtra.
   Corre tambien en viewport de celular (390px): sin scroll horizontal y botones
   tocables.
   v2.1.0 suma el bloque "Faltantes del artículo" (el prorrateo portado de la
   pantalla Faltantes borrada): RPC faltantes_bundle LAZY y la matematica exacta
   (reparto ÷N entre talleristas y firma anti-duplicado de rutas alternativas). */

// firma esperada: F:<fleje>|tp:(actor||cs||ce)|...  (identica a la de Verificacion_GP2)
const FIRMA_101 = 'F:F1|ingreso:F1|matriz:62|tallerista:Carlos|virgilio:';
const FIRMA_202 = 'F:F2|ingreso:F2|tallerista:Martin|virgilio:';

const BUNDLE = {
  sect: { '1': { tipo: 'Fleje', nom: 'Sector Fleje' }, '2': { tipo: 'Crudo', nom: 'Sector Crudo' } },
  art: [
    { id: 1, cod: '101', fam: 'Cuchillos', por: 12, comp: [
      { cod: 'F1', d: 'Fleje uno', s: 1, um: 'kg', q: 1, kg: 0.05, uxc: 100, fkg: false, fuxc: false },
      { cod: 'C9', d: 'Resorte U Crom', s: 2, um: 'uni', q: 2, kg: null, uxc: null, fkg: true, fuxc: true },
    ] },
    { id: 2, cod: '202', fam: 'Tenedores', por: 24, comp: [
      { cod: 'F2', d: 'Fleje dos', s: 1, um: 'kg', q: 1, kg: 0.03, uxc: 50, fkg: false, fuxc: false },
    ] },
  ],
  rutas: [
    { id: 10, nom: 'r1', art: '101', fam: 'Cuchillos', fleje: 'F1', fleje_desc: 'Fleje uno', pasos: [
      { o: 1, tp: 'ingreso', ce: 'F1' },
      { o: 2, tp: 'matriz', actor: '62', actor_desc: 'Corte', ce: 'F1', cs: 'C1', cs_d: 'Cuchilla cortada' },
      { o: 3, tp: 'tallerista', actor: 'Carlos', ce: 'C1', cs: 'Z1' },
      { o: 4, tp: 'virgilio', art: '101' },
    ] },
    { id: 11, nom: 'r2', art: '202', fam: 'Tenedores', fleje: 'F2', fleje_desc: 'Fleje dos', pasos: [
      { o: 1, tp: 'ingreso', ce: 'F2' },
      { o: 2, tp: 'tallerista', actor: 'Martin', ce: 'F2', cs: 'Z2' },
      { o: 3, tp: 'virgilio', art: '202' },
    ] },
  ],
  // la ruta del 202 ya esta confirmada -> el 202 queda "al dia" (sin pendientes)
  confirmadas: [{ firma: FIRMA_202, articulo: '202', fleje: 'F2', por: 'test', en: '2026-08-30T10:00:00Z' }],
  problemas: [],
  madres: { total_comp: 10, sin_kg: 3, sin_uxc: 4 },
};

/* bundle de faltantes (v2.1.0: el prorrateo portado de la vieja pantalla Faltantes).
   Numeros elegidos para poder verificar la matematica A MANO:
   - art 101 (est 100) y art 202 (est 50) comparten el C9 (comp 10) y el fleje F1 (comp 11).
   - C9 en sector D1 (meses 2): aporte 101 = 100x1x2 = 200; aporte 202 = 100; min 100,
     stock 40 -> falta 60; falta art 101 = 60 x 200/300 = 40.
   - C9 en el tallerista Carlos (meses 1): el 101 lo arman Carlos O Martin (2 rutas
     alternativas) -> REPARTO ÷2: aporte 101 = 100/2 = 50; el 202 lo arma solo Carlos:
     50. min 50, stock 0 -> falta 50; falta art 101 = 50 x 50/100 = 25.
   - F1 (kg, ppk 100 de la matriz 62): las DOS rutas del 101 (Carlos/Martin) tienen la
     MISMA firma anti-duplicado -> kg cuentan UNA vez: 100/100 = 1 kg x 2 meses = 2.
     El 202 aporta 1. min 10 -> falta 10; falta art 101 = 10 x 2/3 = 6.67.
   Si el reparto ÷2 o la firma anti-dup se rompen, estos numeros cambian (33 / 4 / 8). */
const FALT = {
  sect: { '1': { tipo: 'Fleje', nom: 'Sector Fleje' }, '2': { tipo: 'Crudo', nom: 'Sector Crudo' }, '12': { tipo: 'Terminado', nom: 'Terminado' } },
  ubic: {
    '1': { tipo: 'sector', ref: 2, nom: 'D1', meses: 2 },
    '2': { tipo: 'tallerista', ref: 1, nom: 'Tallerista Carlos', meses: 1 },
    '3': { tipo: 'tallerista', ref: 2, nom: 'Tallerista Martin', meses: 1 },
    '4': { tipo: 'sector', ref: 1, nom: 'Flejes', meses: 2 },
  },
  art: [{ id: 1, cod: '101', fam: 'Cuchillos', est: 100 }, { id: 2, cod: '202', fam: 'Tenedores', est: 50 }],
  comp: {
    '10': { cod: 'C9', d: 'Resorte U Crom', s: 2, um: 'uni' },
    '11': { cod: 'F1', d: 'Fleje uno', s: 1, um: 'kg' },
    '12': { cod: 'Z1', d: 'Cuchillo armado', s: 12, um: 'uni' },
    '13': { cod: 'Z2', d: 'Tenedor armado', s: 12, um: 'uni' },
  },
  prov_serv: {},
  tall: { '1': { nom: 'Carlos' }, '2': { nom: 'Martin' } },
  mat: { '5': { n: '62', d: 'Corte', ppk: 100, primera: true } },
  bom_art: { '1': [{ c: 10, q: 1 }], '2': [{ c: 10, q: 1 }] },
  bom_comp: {},
  rp: {
    '10': [{ o: 1, tipo: 'ingreso', ce: 11, flje: 11 }, { o: 2, tipo: 'matriz', mat: 5, ce: 11, cs: 10 }, { o: 3, tipo: 'tallerista', tall: 1, ce: 10, cs: 12 }, { o: 4, tipo: 'virgilio', ce: 12, art: 1 }],
    '11': [{ o: 1, tipo: 'ingreso', ce: 11, flje: 11 }, { o: 2, tipo: 'matriz', mat: 5, ce: 11, cs: 10 }, { o: 3, tipo: 'tallerista', tall: 2, ce: 10, cs: 12 }, { o: 4, tipo: 'virgilio', ce: 12, art: 1 }],
    '20': [{ o: 1, tipo: 'ingreso', ce: 11, flje: 11 }, { o: 2, tipo: 'matriz', mat: 5, ce: 11, cs: 10 }, { o: 3, tipo: 'tallerista', tall: 1, ce: 10, cs: 13 }, { o: 4, tipo: 'virgilio', ce: 13, art: 2 }],
  },
  inv: { '10:1': { cant: 40, min: 100 }, '10:2': { cant: 0, min: 50 }, '11:4': { cant: 0, min: 10 } },
  c2a: {},
};

const STUB = 'window.__rpc=[];window.supabase={createClient:function(){return{rpc:async function(n,a){' +
  'window.__rpc.push({n:n,a:a||null});' +
  'if(n==="despiece_verif_bundle")return{data:' + JSON.stringify(BUNDLE) + ',error:null};' +
  'if(n==="faltantes_bundle")return{data:' + JSON.stringify(FALT) + ',error:null};' +
  'return{data:99,error:null};}}}};';

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) process.exitCode = 1; };
  const ctx = await browser.newContext({ viewport: { width: 390, height: 800 }, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  page.on('dialog', d => d.accept());
  await page.route('**/@supabase/supabase-js@2', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/gp2-claro.css**', r => r.fulfill({ contentType: 'text/css', body: '' }));
  await page.route('**/*.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));
  await page.goto(ROOT + '/Despiece%20x%20Articulo/Despiece_GP2.html');
  await page.waitForSelector('.art-section');

  // ── resumen global: cuenta pendientes ──
  let kpis = await page.locator('#kpis').innerText();
  ok((await page.locator('#kpiSinConf').innerText()).trim() === '1', 'KPI: 1 ruta sin confirmar (de 2)');
  ok(/3/.test(kpis) && /Comp\. sin Kg x Uni/i.test(kpis), 'KPI: comp sin Kg x Uni (global, viene de madres)');
  ok(/4/.test(kpis) && /Comp\. sin Uni x Caj/i.test(kpis), 'KPI: comp sin Uni x Cajon (global)');

  // ── filtro "solo articulos con pendientes": el 202 (confirmado y sin faltas) se oculta ──
  await page.check('#chkPend');
  let cods = await page.$$eval('.art-head .cod', xs => xs.map(x => x.textContent.trim()));
  ok(cods.length === 1 && cods[0] === '101', 'filtro pendientes: queda solo el 101 (' + cods.join(',') + ')');
  await page.uncheck('#chkPend');

  // ── faltantes: la RPC es LAZY (no se pide hasta abrir un articulo) ──
  ok(!(await page.evaluate(() => window.__rpc.some(c => c.n === 'faltantes_bundle'))),
     'faltantes_bundle NO se pide al cargar (lazy)');

  // ── elegir un articulo: receta + ruta + avisos en la misma pantalla ──
  await page.selectOption('#selArt', '101');
  await page.waitForSelector('.art-section.open');
  const sec = page.locator('.art-section.open');
  const txt = await sec.innerText();
  ok(/Receta/i.test(txt) && /C9/.test(txt) && /Resorte U Crom/.test(txt), 'receta: componentes del articulo');
  ok((await sec.locator('td.falta').count()) === 2, 'receta: kg y uxc faltantes marcados FALTA');
  ok((await sec.locator('.ruta-card').count()) === 1, 'ruta trazada del articulo presente');
  ok(/Carlos/.test(txt) && /Matriz|62/.test(txt), 'la ruta muestra sus pasos (matriz 62, Carlos)');
  ok(/Avisos/i.test(txt) && /falta Kg x Uni y Uni x Caj/i.test(txt), 'avisos: el C9 sin datos maestros aparece');

  // ── bloque "Faltantes del artículo": el prorrateo de la vieja pantalla Faltantes ──
  await page.waitForSelector('.art-section.open .falt-tabla');
  ok((await page.evaluate(() => window.__rpc.filter(c => c.n === 'faltantes_bundle').length)) === 1,
     'faltantes_bundle se pidio UNA vez al abrir el articulo');
  const filas = await page.$$eval('.art-section.open .falt-tabla tbody tr', trs =>
    trs.map(tr => [...tr.children].map(td => td.textContent.trim())));
  // columnas: Cod, Componente, Ubicacion, Min ubic, Stock, Falta total, Aporte art, Falta art, Un
  ok(filas.length === 3, 'faltantes: 3 filas (F1 en Flejes, C9 en D1, C9 en Carlos) — hay ' + filas.length);
  const fF1 = filas.find(f => f[0].indexOf('F1') === 0 && f[2] === 'Flejes');
  const fD1 = filas.find(f => f[0].indexOf('C9') === 0 && f[2] === 'D1');
  const fCar = filas.find(f => f[0].indexOf('C9') === 0 && f[2] === 'Carlos');
  ok(!!fD1 && fD1[3] === '100' && fD1[4] === '40' && fD1[5] === '60' && fD1[6] === '200' && fD1[7] === '40',
     'prorrateo C9 en D1: min 100, stock 40, falta 60, aporte art 200, falta art 40 (60 x 200/300) — ' + JSON.stringify(fD1));
  ok(!!fCar && fCar[3] === '50' && fCar[5] === '50' && fCar[6] === '50' && fCar[7] === '25',
     'reparto ÷2 talleristas: C9 en Carlos aporta 50 (100/2) y falta art 25 (50 x 50/100) — ' + JSON.stringify(fCar));
  ok(!!fF1 && fF1[6] === '2' && fF1[7] === '6.67',
     'firma anti-duplicado: las 2 rutas alternativas del fleje cuentan UNA vez (aporte 2 kg, falta art 6.67) — ' + JSON.stringify(fF1));
  ok(!!fD1 && /×2/.test(fD1[0]), 'el C9 marca que lo comparten 2 articulos (×2)');

  // ── sin scroll horizontal y botones tocables en celular ──
  const mob = await page.evaluate(() => ({
    horizontal: document.documentElement.scrollWidth > window.innerWidth,
    nBtnConf: document.querySelectorAll('.art-section.open .btn-conf').length,
  }));
  ok(!mob.horizontal, 'celular 390px: sin scroll horizontal');
  ok(mob.nBtnConf === 0, 'ya no hay botones Confirmar/Revisar/Reportar en la ruta (pedido usuario 2026-08-31)');

  // Botones Confirmar/Revisar/Reportar eliminados (pedido usuario 2026-08-31):
  // el modulo Despiece deja de disparar ruta_confirmar / ruta_reportar / ruta_pin
  // desde la UI. FIRMA_101 sigue calculada arriba por si en el futuro se reincorpora.
  const noRpc = await page.evaluate(() => ({
    conf:  window.__rpc.some(c => c.n === 'ruta_confirmar'),
    warn:  window.__rpc.some(c => c.n === 'ruta_reportar'),
    pin:   window.__rpc.some(c => c.n === 'ruta_pin'),
  }));
  ok(!noRpc.conf, 'no se dispara ruta_confirmar (boton retirado)');
  ok(!noRpc.warn, 'no se dispara ruta_reportar (boton retirado)');
  ok(!noRpc.pin,  'no se dispara ruta_pin (boton retirado)');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
