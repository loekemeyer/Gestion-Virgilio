// En "¿Qué necesito para producir?", un ARTÍCULO COMPRADO TERMINADO no tiene tallerista:
// el proveedor de artículo terminado lo REEMPLAZA [usuario 2026-09-11, textual]. De casa sale
// el cartón y la caja, y el proveedor entrega el artículo hecho en Virgilio.
// Antes la pantalla dibujaba "TALLERISTA (sin asignar) — tabla incompleta" en esos 39 artículos
// (de 189): mentía diciendo que faltaba un dato y encima escondía quién entrega.
// Fixture = el 761 Cucharita Matera real: caja A8 -> Melinox -> Virgilio.
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const B = {
  art: [{ id: 219, cod: '761', fam: 'Mate', d: 'Cucharita Matera', mk: 'CHEF', disc: false }],
  sect: { '11': { t: 'caja' }, '12': { t: 'terminado' } },
  comp: {
    '900': { cod: 'A8', d: 'Caja N° 2', s: 11 },
    '901': { cod: '761', d: '761 Terminado', s: 12 },
  },
  mat: {}, prov: {}, tall: {},
  provat: { '7': 'Melinox' },
  bom: [{ a: 219, c: 900, q: 0.01 }],
  children: {},
  tall_art: {},                       // <- el artículo NO tiene tallerista, y está bien
  rp: {
    '939': [
      { o: 1, tp: 'insumo', ce: 900, cs: 900 },
      { o: 2, tp: 'proveedor_at', pat: 7, ce: 900, cs: 901 },
      { o: 3, tp: 'virgilio', ce: 901, cs: null },
    ],
  },
  rutas_by_art: { '219': [{ id: 939, nom: 'caja -> Melinox', f: null, a: 219 }] },
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

  ok(!/sin asignar/i.test(txt), 'no dice "(sin asignar)": el 761 no lleva tallerista por diseño');
  ok(!/tabla incompleta/i.test(txt), 'no dice "tabla incompleta": no falta ningún dato');
  ok(/MELINOX/i.test(txt), 'muestra al proveedor que entrega: Melinox');
  ok(/entrega terminado/i.test(txt), 'dice que entrega el artículo terminado');
  const kpi = await page.$eval('.hero', e => e.innerText);
  ok(/MELINOX/i.test(kpi), 'el encabezado tambien nombra al proveedor, no a un tallerista vacio');
  ok(!/ensambla/i.test(kpi), 'el encabezado no dice "ensambla" (no lo ensambla nadie acá)');
  ok(/Artículo comprado terminado/i.test(txt), 'el bloque final se titula "Artículo comprado terminado → Virgilio"');
  if (process.exitCode) console.log('\n---- render ----\n' + txt);
  await browser.close();
})();
