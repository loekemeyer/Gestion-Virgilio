/* PEDIDO MINIMO POR PIEZA (2026-09-11). Del Excel del usuario (hoja "Pedido 31-08", columna
 * `Pedi Min Uni`): el inyector no hace una tirada de menos de N piezas. A DIFERENCIA del piso en kg
 * del proveedor de resina, este NO bloquea la OC: hoy 24 de los 47 sugeridos quedan por debajo del
 * piso (el pirolo blanco sugiere 2.248 contra un minimo de 36.000 = 64 meses), asi que bloquear
 * dejaria la OC imposible de crear. Es un aviso aparte con un boton para subir al piso las lineas
 * que el comprador decida llevar.
 */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const BUNDLE = {
  paq: 250, tc: 1535, facturar_pct_loeke: 85, ocs: [],
  proveedores: [
    { nombre: 'Pat Bet Plast', rubro: 'Sector Plástico', cod_prov: '111', activo: true,
      dias_entrega: 15, entrega_en: null, pedido_minimo_kg: null, insumos: 3 },
  ],
  insumos: [
    // Pirolo Blanco: el caso real. Sugiere 2.248 y el inyector no tira menos de 36.000.
    { comp_id: 251, codigo: 'PA7A', descripcion: 'Pirolo Blanco', sector: 'Sector Plástico',
      sector_id: 6, proveedor: 'Pat Bet Plast', um: 'uni', unidad: 'uni', kg_x_uni: 0.0012,
      consumo: 562, meses: 4, online: 0, minimo: 0, maximo: 2248, pendiente_oc: 0, sugerido: 2248,
      pedido_minimo_uni: 36000, precio: 20, moneda: 'ARS' },
    // Muñeco Antiderrame: sugiere 3.000 contra un minimo de 2.500 -> ya lo cumple, no avisa.
    { comp_id: 702, codigo: 'PA3', descripcion: 'Muñeco Antiderrame', sector: 'Sector Plástico',
      sector_id: 6, proveedor: 'Pat Bet Plast', um: 'uni', unidad: 'uni', kg_x_uni: 0.004,
      consumo: 750, meses: 4, online: 0, minimo: 0, maximo: 3000, pendiente_oc: 0, sugerido: 3000,
      pedido_minimo_uni: 2500, precio: 55, moneda: 'ARS' },
    // Sin pedido_minimo_uni cargado: no se toca nunca.
    { comp_id: 254, codigo: 'PC7', descripcion: 'Inserto Neg. Canelones', sector: 'Sector Plástico',
      sector_id: 6, proveedor: 'Pat Bet Plast', um: 'uni', unidad: 'uni', kg_x_uni: 0.002,
      consumo: 100, meses: 4, online: 0, minimo: 0, maximo: 400, pendiente_oc: 0, sugerido: 400,
      pedido_minimo_uni: null, precio: 30, moneda: 'ARS' },
  ],
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
  const page = await browser.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  await page.route('**/@supabase/supabase-js@2', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/gp2-modulo.css**', r => r.fulfill({ contentType: 'text/css', body: '.hidden{display:none!important}' }));
  await page.route('**/GP2_favicon.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));
  await page.goto(ROOT + '/Compras/OC_GP2.html');
  await page.waitForFunction(() => document.getElementById('status').textContent === '');
  const ok = (c, m) => { console.log((c?'OK  ':'FAIL')+' '+m); if(!c) process.exitCode = 1; };

  await page.click('#rubros .chip:has-text("Plástico")');
  await page.click('#provs .chip:has-text("Pat Bet")');

  const aviso = await page.textContent('#avisoMinUni');
  const plano = aviso.replace(/\s+/g, ' ');
  ok(!(await page.$eval('#avisoMinUni', x => x.classList.contains('hidden'))), 'aparece el aviso de pedido minimo por pieza');
  ok(/PA7A/.test(aviso), 'nombra la pieza que queda corta: ' + plano.slice(0, 110));
  ok(/36\.000/.test(aviso), 'dice cual es el minimo del inyector');
  ok(!/PA3/.test(aviso), 'no avisa por la que YA cumple el minimo');
  ok(!/PC7/.test(aviso), 'no avisa por la que no tiene minimo cargado');
  ok(/1 línea queda/.test(plano), 'cuenta bien las lineas cortas: ' + plano.slice(0, 60));

  // Lo importante: AVISA pero DEJA crear. Bloquear volveria la OC imposible.
  ok(!(await page.$eval('#btnCrear', x => x.disabled)), 'el aviso NO bloquea la creacion de la OC');

  // El boton sube SOLO las lineas cortas, al piso exacto.
  await page.click('#btnSubirMinUni');
  await page.waitForFunction(() => document.getElementById('avisoMinUni').classList.contains('hidden'));
  ok(await page.$eval('.pedir-in[data-in="251"]', x => x.value.replace(/\./g, '') === '36000'), 'el boton sube el Pirolo al minimo (36.000)');
  ok(await page.$eval('.pedir-in[data-in="702"]', x => x.value.replace(/\./g, '') === '3000'), 'no toca la que ya cumplia (sigue en 3.000)');
  ok(await page.$eval('.pedir-in[data-in="254"]', x => x.value.replace(/\./g, '') === '400'), 'no toca la que no tiene minimo (sigue en 400)');
  ok(await page.$eval('#avisoMinUni', x => x.classList.contains('hidden')), 'y el aviso se va');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
