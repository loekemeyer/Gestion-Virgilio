// Regresion v1.114.0: al dejar que las ramas de un convergente usen rutas de INSUMO, una rama
// cuyo unico paso es el 'insumo' (el Resorte Biconico BOM10 dentro del C12 del art 515) quedaba
// con el nodo vacio: "Rama 1 — ? produce BOM10 / INSUMO ?". Tiene que decir "Insumo BOM10".
// Fixture = la convergencia C12 real del 515 (BOM10 + IE1 + W1B).
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const B = {
  art: [{ id: 36, cod: '515', fam: 'Batidores' }],
  sect: { '2': { t: 'procesado' }, '5': { t: 'fleje' }, '6': { t: 'plástico' }, '7': { t: 'bombilla' },
          '10': { t: 'cartón' }, '11': { t: 'caja' }, '12': { t: 'terminado' } },
  comp: {
    '180': { cod: 'IF11', d: 'Fleje N° 19', s: 5 }, '194': { cod: 'IE1', d: 'Fleje N° 33', s: 5 },
    '151': { cod: 'W1B', d: 'Grampa Batidor', s: 2 }, '262': { cod: 'C12', d: 'Paleta Batidor Resorte', s: 7 },
    '264': { cod: 'BOM10', d: 'Resorte Biconico', s: 7 }, '318': { cod: 'A1C1', d: 'Cartón 515', s: 10 },
    '457': { cod: 'A8', d: 'Caja N°2', s: 11 }, '242': { cod: 'PA13', d: 'Capuchon Batidor LK', s: 6 },
    '632': { cod: 'PA13B', d: 'Capuchon Batidor LK S/Serig', s: 6 }, '229': { cod: 'PC10', d: 'Mango LK Espatula', s: 6 },
    '399': { cod: '515', d: '515 Terminado', s: 12 },
  },
  mat: { '70': { n: '138', d: '', r: 40 } },
  prov: { '4': { n: 'Guazzaroni Patricio', p: 'Niquelado' }, '6': { n: 'Pedernera Ilario', p: 'Cromado' },
          '8': { n: 'Hernandez Julio', p: 'Serigrafiado' } },
  tall: { '2': 'Alex Escalante' },
  bom: [{ a: 36, c: 318, q: 1 }, { a: 36, c: 457, q: 0.0833 }, { a: 36, c: 262, q: 1 }, { a: 36, c: 242, q: 1 }, { a: 36, c: 229, q: 1 }],
  children: { '262': [{ c: 264, q: 1 }, { c: 194, q: 1 }, { c: 151, q: 1 }] },
  tall_art: { '36': ['Alex Escalante'] },
  rp: {
    '61': [{ o: 1, tp: 'ingreso', ce: 180, cs: 180 }, { o: 2, tp: 'matriz', m: 70, ce: 180, cs: 151 },
           { o: 3, tp: 'proveedor_servicio', pr: 4, ce: 151, cs: 151 }, { o: 4, tp: 'tallerista', ta: 2, ce: 151, cs: 262 },
           { o: 5, tp: 'proveedor_servicio', pr: 6, ce: 262, cs: 262 }, { o: 6, tp: 'tallerista', ta: 2, ce: 262, cs: 399 },
           { o: 7, tp: 'virgilio', ce: 399, cs: null }],
    '319': [{ o: 1, tp: 'insumo', ce: 229, cs: 229 }, { o: 2, tp: 'tallerista', ta: 2, ce: 229, cs: 399 }, { o: 3, tp: 'virgilio', ce: 399, cs: null }],
    '320': [{ o: 1, tp: 'insumo', ce: 318, cs: 318 }, { o: 2, tp: 'tallerista', ta: 2, ce: 318, cs: 399 }, { o: 3, tp: 'virgilio', ce: 399, cs: null }],
    '321': [{ o: 1, tp: 'insumo', ce: 632, cs: 632 }, { o: 2, tp: 'proveedor_servicio', pr: 8, ce: 632, cs: 242 },
            { o: 3, tp: 'tallerista', ta: 2, ce: 242, cs: 399 }, { o: 4, tp: 'virgilio', ce: 399, cs: null }],
    '494': [{ o: 1, tp: 'insumo', ce: 457, cs: 457 }, { o: 2, tp: 'tallerista', ta: 2, ce: 457, cs: 399 }, { o: 3, tp: 'virgilio', ce: 399, cs: null }],
    '551': [{ o: 1, tp: 'ingreso', ce: 194, cs: 194 }, { o: 2, tp: 'tallerista', ta: 2, ce: 194, cs: 262 },
            { o: 3, tp: 'proveedor_servicio', pr: 6, ce: 262, cs: 262 }, { o: 4, tp: 'tallerista', ta: 2, ce: 262, cs: 399 },
            { o: 5, tp: 'virgilio', ce: 399, cs: null }],
    '563': [{ o: 1, tp: 'insumo', ce: 264, cs: 264 }, { o: 2, tp: 'tallerista', ta: 2, ce: 264, cs: 399 }, { o: 3, tp: 'virgilio', ce: 399, cs: null }],
  },
  rutas_by_art: { '36': [
    { id: 61, nom: 'Fleje 19 -> Art 515', f: 180, a: 36 }, { id: 319, nom: 'Insumo PC10', f: null, a: 36 },
    { id: 320, nom: 'Insumo CART515', f: null, a: 36 }, { id: 321, nom: 'Insumo PA13', f: null, a: 36 },
    { id: 494, nom: 'Insumo A8', f: null, a: 36 }, { id: 551, nom: 'Fleje 33 -> Art 515', f: 194, a: 36 },
    { id: 563, nom: 'Insumo BOM10', f: null, a: 36 }] },
};

const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name){ if(name==='programa_bundle') return { data: ${JSON.stringify(B)}, error:null };
    return { data:null, error:{message:'rpc '+name} }; },
  from: function(){ var o={}; ['select','eq','order','single'].forEach(m=>o[m]=()=>o);
    o.then=(r)=>Promise.resolve({data:[],error:null}).then(r); return o; }
};}};`;

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const page = await browser.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  await page.route('**/@supabase/supabase-js@2', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/*.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));
  await page.goto(ROOT + '/Programa/Programa.html');
  await page.waitForSelector('#canvas .lane');

  const txt = await page.$eval('#canvas', e => e.innerText);
  const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) process.exitCode = 1; };

  ok(!/\?\s*PRODUCE/i.test(txt), 'ninguna rama arranca con el nodo vacio "? produce X"');
  ok(/Rama\s*1\s*—\s*Insumo BOM10/i.test(txt), 'Rama 1 = "Insumo BOM10" (Resorte Biconico)');
  ok(/Resorte Biconico/i.test(txt), 'el Resorte Biconico aparece en la convergencia del C12');
  ok(/Rama\s*2\s*—\s*Insumo IE1/i.test(txt), 'Rama 2 = "Insumo IE1" (fleje sin pasos previos)');
  ok(/Rama\s*3\s*—\s*IF11 produce W1B/i.test(txt), 'Rama 3 = "IF11 produce W1B" (la que si tiene matriz)');
  if (process.exitCode) console.log('\n---- render ----\n' + txt);
  await browser.close();
})();
