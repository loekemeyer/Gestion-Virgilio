// Stock Tránsito PS en "¿Qué necesito para producir?": una pieza que sale de un proveedor de
// servicio y se va DERECHO a otro no vuelve a ningún sector — queda en TRÁNSITO esperando al
// siguiente. Fixture = la ruta 90 real (Fleje 26 -> Art 053): M68 -> M69 -> I2 -> FAAT ->
// Guazzaroni -> Pedernera -> C9 -> Pettofrezza.
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const B = {
  art: [{ id: 3, cod: '053', fam: 'Sacacorchos' }],
  sect: { '3': { t: 'movimiento' }, '5': { t: 'fleje' }, '7': { t: 'bombilla' }, '12': { t: 'terminado' } },
  comp: {
    '187': { cod: 'IA6', d: 'Fleje N° 26', s: 5 },
    '496': { cod: 'IA6-M68', d: 'Fleje N° 26 tras M68', s: 3 },
    '259': { cod: 'I2', d: 'Resorte U p/Templar', s: 7 },
    '261': { cod: 'C9', d: 'Resorte U Crom', s: 7 },
    '375': { cod: '053', d: '53 Terminado', s: 12 },
  },
  mat: { '44': { n: '68', d: '', r: 50.29 }, '45': { n: '69', d: 'Resorte U p/Templar', r: null } },
  prov: { '2': { n: 'Laboratorio FAAT', p: 'Templado, Cementado' }, '4': { n: 'Guazzaroni Patricio', p: 'Niquelado' },
          '6': { n: 'Pedernera Ilario', p: 'Cromado' } },
  tall: { '11': 'Pettofrezza Rafael' },
  bom: [{ a: 3, c: 261, q: 1 }],
  children: {},
  tall_art: { '3': ['Pettofrezza Rafael'] },
  rp: {
    '90': [
      { o: 1, tp: 'ingreso', ce: 187, cs: 187 },
      { o: 2, tp: 'matriz', m: 44, ce: 187, cs: 496 },
      { o: 3, tp: 'matriz', m: 45, ce: 496, cs: 259 },
      { o: 4, tp: 'proveedor_servicio', pr: 2, ce: 259, cs: 259 },
      { o: 5, tp: 'proveedor_servicio', pr: 4, ce: 259, cs: 259 },
      { o: 6, tp: 'proveedor_servicio', pr: 6, ce: 259, cs: 261 },
      { o: 7, tp: 'tallerista', ta: 11, ce: 261, cs: 375 },
      { o: 8, tp: 'virgilio', ce: 375, cs: null },
    ],
  },
  rutas_by_art: { '3': [{ id: 90, nom: 'Fleje 26 -> Art 53', f: 187, a: 3 }] },
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

  // Los dos tramos PS -> PS son transito
  ok((txt.match(/TRÁNSITO/g) || []).length === 2, 'dos nodos TRÁNSITO (FAAT->Guazzaroni y Guazzaroni->Pedernera)');
  ok(/I2 · Resorte U p\/Niquelar/i.test(txt), 'tras FAAT dice "Resorte U p/Niquelar" (el proceso que espera)');
  ok(/I2 · Resorte U p\/Cromar/i.test(txt), 'tras Guazzaroni dice "Resorte U p/Cromar"');
  // "stock I2" queda UNA sola vez: el que deja la matriz 69. Los dos de despues de un PS eran
  // los inventados (el resorte no vuelve al sector, se va derecho al proveedor siguiente).
  ok((txt.match(/stock I2/g) || []).length === 1, 'un solo "stock I2" (el de la matriz), no tres');
  // Lo que NO es transito sigue igual
  ok(/stock C9/.test(txt), 'tras Pedernera (ultimo PS) si hay stock de sector: C9');
  const trasM69 = txt.split('MATRIZ N°69')[1] || '';
  ok(/BOMBILLA/.test(trasM69.split('PROV')[0] || ''), 'de matriz a PS NO es transito: I2 pasa por Sector Bombilla');
  if (process.exitCode) console.log('\n---- render ----\n' + txt);
  await browser.close();
})();
