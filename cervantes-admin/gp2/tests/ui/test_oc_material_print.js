/* OC de MATERIA PRIMA PLASTICA (2026-09-11): la hoja que va al proveedor tiene el formato de las
 * hojas "O.C." del workbook del usuario — membrete doble Loekemeyer / Chef, RAZON SOCIAL + COD PROV,
 * ENTREGA EN Virgilio 2788, "FACTURAR Loekemeyer 85% Chef 15%", "ESTE PEDIDO ANULA...", y cada
 * material en dos renglones LK (Cod ISIS, 85% de los kg) y CH (Cod ISIS de Chef, 15%). Un material
 * SIN codigo de Chef va en un solo renglon LK con el 100% (usuario: "si no lo usa"). La OC de Master
 * Bach (Arcolor / Julio Garcia) dice ENTREGA EN Cervantes 2868 (proveedor_insumo.entrega_en). Una OC
 * que no es de material sigue con la hoja de siempre (test_oc_print.js).
 */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);
const BUNDLE = {
  paq: 250, insumos: [], facturar_pct_loeke: 85, tc: 1535,
  ocs: [ { id: 21, numero: 40, proveedor: 'Indarnyl', cod_prov: '202', entrega_en: null, rubro: 'Sector Materia Prima Plástica', estado: 'borrador',
    creado_en: '2026-09-11T10:00:00Z', fecha_entrega_estimada: '2026-09-16', total_usd: 1015, total_ars: 0,
    items: [ { codigo: '2455', descripcion: 'ABS GP 22 Natural', cantidad: 350, unidad: 'kg', recibido: 0,
               precio_uni: 2.9, moneda: 'USD', subtotal: 1015, sector_id: 14, codigo_isis_ch: '1085' },
             { codigo: '2475', descripcion: 'Nylon Virgen', cantidad: 25, unidad: 'kg', recibido: 0,
               precio_uni: null, moneda: null, subtotal: null, sector_id: 14, codigo_isis_ch: null } ] },
         { id: 22, numero: 41, proveedor: 'Arcolor', cod_prov: '2297', entrega_en: 'Cervantes 2868', rubro: 'Sector Materia Prima Plástica', estado: 'borrador',
    creado_en: '2026-09-11T10:00:00Z', fecha_entrega_estimada: null, total_usd: 0, total_ars: 0,
    items: [ { codigo: '0255', descripcion: 'Master Bach 2% Negro', cantidad: 50, unidad: 'kg', recibido: 0,
               precio_uni: null, moneda: null, subtotal: null, sector_id: 14, codigo_isis_ch: null } ] } ],
};
const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    if(name==='oc_bundle') return { data: ${JSON.stringify(BUNDLE)}, error: null };
    return { data: { ok: true }, error: null };
  }
};}};
`;
(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  await page.route('**/@supabase/supabase-js@2', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/gp2-modulo.css**', r => r.fulfill({ contentType: 'text/css', body: '.hidden{display:none!important}' }));
  await page.route('**/GP2_favicon.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));
  await page.goto(ROOT + '/Compras/OC_GP2.html');
  await page.waitForFunction(() => document.getElementById('status').textContent === '');
  const ok = (c, m) => { console.log((c?'OK  ':'FAIL')+' '+m); if(!c) process.exitCode = 1; };
  await page.click('#tabOcs');
  await ctx.addInitScript(() => { window.print = () => { window.__printed = true; }; });
  // la lista respeta el orden del bundle: [0] = 40 Indarnyl, [1] = 41 Arcolor (Master Bach)
  const botones = await page.$$('.oc-acts button.imp');
  ok(botones.length === 2, 'dos OC de material en la lista (' + botones.length + ')');
  const [pop] = await Promise.all([ ctx.waitForEvent('page'), botones[0].click() ]);
  await pop.waitForFunction(() => document.body && document.body.textContent.includes('ORDEN DE COMPRA'));
  const txt = await pop.textContent('body');
  ok(/ORDEN DE COMPRA N° 40/.test(txt), 'titulo con el numero');
  ok(txt.includes('Loekemeyer Hnos. S.R.L') && txt.includes('30-51584245-0') && txt.includes('Chef SRL') && txt.includes('30-68575625-7'),
     'membrete doble con los dos CUIT');
  ok(txt.includes('RAZON SOCIAL:INDARNYL') && txt.includes('COD PROV:202'), 'razon social en mayusculas y cod prov');
  ok(txt.includes('ENTREGA EN:Virgilio 2788'), 'entrega en Virgilio (proveedor sin entrega_en propia)');
  ok(txt.includes('FACTURAR Loekemeyer 85% · Chef 15%') && txt.includes('ESTE PEDIDO ANULA CUALQUIER PEDIDO ANTERIOR'), 'avisos de facturacion y anulacion');
  // ABS (con codigo Chef 1085): 350 kg -> 297,5 LK + 52,5 CH. Nylon Virgen (sin codigo Chef): UN renglon LK con los 25 kg.
  const filas = await pop.$$eval('tbody tr', xs => xs.map(x => [...x.querySelectorAll('td')].map(t => t.textContent.trim())));
  ok(filas.length === 3, 'LK+CH para el ABS y solo LK para el Nylon Virgen (' + filas.length + ' renglones)');
  ok(filas[0][0] === 'LK' && filas[0][1] === '2455' && filas[0][2] === '1' && filas[0][4] === '350' && filas[0][6] === '297,5' && filas[0][7] === '16/09/2026',
     'renglon LK: ' + filas[0].join('|'));
  ok(filas[1][0] === 'CH' && filas[1][1] === '1085' && filas[1][6] === '52,5', 'renglon CH con el Cod ISIS de Chef y el 15%: ' + filas[1].join('|'));
  ok(filas[2][0] === 'LK' && filas[2][1] === '2475' && filas[2][2] === '2' && filas[2][6] === '25', 'material sin codigo Chef: un solo renglon LK con el 100%: ' + filas[2].join('|'));
  ok(!txt.includes('—'), 'no queda ningun renglon CH con guion');
  ok(filas[0].length === 14, '14 columnas como la hoja del usuario (Fecha Ent / Kg Ent x3 en blanco)');
  // la hoja de material NO lleva precios: es la hoja del proveedor tal cual la del usuario
  ok(!txt.includes('Precio unit.') && !txt.includes('US$'), 'sin precios en la hoja de material');
  // Master Bach: se stockea en Cervantes por ahora -> ENTREGA EN Cervantes 2868
  const [pop2] = await Promise.all([ ctx.waitForEvent('page'), botones[1].click() ]);
  await pop2.waitForFunction(() => document.body && document.body.textContent.includes('ORDEN DE COMPRA'));
  const txt2 = await pop2.textContent('body');
  ok(/ORDEN DE COMPRA N° 41/.test(txt2) && txt2.includes('RAZON SOCIAL:ARCOLOR') && txt2.includes('COD PROV:2297'), 'OC de Master Bach: Arcolor 2297');
  ok(txt2.includes('ENTREGA EN:Cervantes 2868'), 'Master Bach se entrega en Cervantes 2868');
  const filas2 = await pop2.$$eval('tbody tr', xs => xs.map(x => [...x.querySelectorAll('td')].map(t => t.textContent.trim())));
  ok(filas2.length === 1 && filas2[0][0] === 'LK' && filas2[0][6] === '50', 'Master Bach sin codigo Chef: un renglon LK con los 50 kg: ' + filas2[0].join('|'));
  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
