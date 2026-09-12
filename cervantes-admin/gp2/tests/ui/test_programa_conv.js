// Rama de convergencia con ruta de INSUMO: el V3 del 521 tiene que mostrar el niquelado
// (CV3 -> Guazzaroni -> V3) antes de entrar a la Matriz 135, y no repetirse en el bloque 4.
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

// Recorte del programa_bundle real alrededor del 521
const B = {
  art: [{ id: 41, cod: '521', fam: 'Sacacorchos' }],
  sect: { '1': { t: 'crudo' }, '2': { t: 'procesado' }, '5': { t: 'fleje' }, '8': { t: 'remache' }, '12': { t: 'terminado' } },
  comp: {
    '36': { cod: 'K5', d: 'Cpo Sacacorcho LK p/Armar', s: 1 },
    '38': { cod: 'K8', d: 'Sacatapita Estampado p/Cromar', s: 1 },
    '8':  { cod: 'G4', d: 'Cpo Sacacorcho 521 p/cromar', s: 1 },
    '105':{ cod: 'C16', d: 'C Sacacorcho 521 Crom', s: 2 },
    '412':{ cod: '521', d: '521 Terminado', s: 12 },
    '278':{ cod: 'V3', d: 'Rem. Sacatapita Niq', s: 8 },
    '475':{ cod: 'CV3', d: 'Rem. Sacatapita Niq p/Niquelar', s: 8 },
    '30': { cod: 'IC1', d: 'Fleje N° 25', s: 5 },
  },
  mat: { '66': { n: '135', d: 'Remachado Sacatapita', r: null }, '30': { n: '40', d: '', r: 27.95 }, '31': { n: '41', d: '', r: null } },
  prov: { '4': { n: 'Guazzaroni Patricio', p: 'Niquelado' }, '6': { n: 'Pedernera Ilario', p: 'Cromado' } },
  tall: { '6': 'Martin Cornejo' },
  bom: [{ a: 41, c: 105, q: 1 }],
  children: { '8': [{ c: 36, q: 1 }, { c: 38, q: 1 }, { c: 278, q: 1 }] },
  tall_art: { '41': ['Martin Cornejo'] },
  rp: {
    // ruta 83: Fleje 25 -> K7 -> K8 -> G4 -> C16 -> 521
    '83': [
      { o: 1, tp: 'ingreso', ce: 30, cs: 30 },
      { o: 2, tp: 'matriz', m: 30, ce: 30, cs: 38 },
      { o: 3, tp: 'matriz', m: 66, ce: 38, cs: 8 },
      { o: 4, tp: 'proveedor_servicio', pr: 6, ce: 8, cs: 105 },
      { o: 5, tp: 'tallerista', ta: 6, ce: 105, cs: 412 },
      { o: 6, tp: 'virgilio', ce: 412, cs: null },
    ],
    // ruta 777 (la nueva): CV3 -> Guazzaroni -> V3 -> Matriz 135 -> ...
    '777': [
      { o: 1, tp: 'ingreso', ce: 475, cs: 475 },
      { o: 2, tp: 'proveedor_servicio', pr: 4, ce: 475, cs: 278 },
      { o: 3, tp: 'matriz', m: 66, ce: 278, cs: 8 },
      { o: 4, tp: 'proveedor_servicio', pr: 6, ce: 8, cs: 105 },
      { o: 5, tp: 'tallerista', ta: 6, ce: 105, cs: 412 },
      { o: 6, tp: 'virgilio', ce: 412, cs: null },
    ],
  },
  rutas_by_art: { '41': [{ id: 83, nom: 'Fleje 25 -> Art 521', f: 30, a: 41 }, { id: 777, nom: 'Insumo V3 -> Art 521', f: null, a: 41 }] },
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

  ok(/Rama\s*3\s*—\s*CV3 produce V3/i.test(txt), 'Rama 3 = "CV3 produce V3"');
  ok(/PROV GUAZZARONI PATRICIO/i.test(txt), 'aparece el paso de niquelado');
  ok(!/Rama 3 — Insumo V3/.test(txt), 'ya no dibuja el V3 pelado');
  ok(!/Insumos comprados/i.test(txt), 'la ruta del CV3 no se repite en el bloque 4');
  ok(/MATRIZ N°135/.test(txt), 'converge en la Matriz 135');
  if (process.exitCode) console.log('\n---- render ----\n' + txt);
  await browser.close();
})();
