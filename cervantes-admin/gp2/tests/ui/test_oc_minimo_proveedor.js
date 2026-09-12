/* PEDIDO MINIMO DEL PROVEEDOR DE RESINA (2026-09-11). Del Excel del usuario: Indarnyl no vende menos de
 * 400 kg. La pantalla suma los kg de la OC POR PROVEEDOR (solo los items del sector 14) y, si no llega al
 * piso, no deja crear la orden y dice cuanto falta. A proposito no se infla sola: sumar kg es una decision
 * de compra. Un proveedor sin pedido_minimo_kg (o un insumo de otro sector) no se toca.
 */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const BUNDLE = {
  paq: 250, tc: 1535, facturar_pct_loeke: 85, ocs: [],
  proveedores: [
    { nombre: 'Indarnyl', rubro: 'Sector Materia Prima Plástica', cod_prov: '202', activo: true,
      dias_entrega: 5, entrega_en: null, pedido_minimo_kg: 400, insumos: 2 },
    { nombre: 'Beta Plásticos', rubro: 'Sector Materia Prima Plástica', cod_prov: '3527', activo: true,
      dias_entrega: 5, entrega_en: null, pedido_minimo_kg: 25, insumos: 1 },
  ],
  insumos: [
    // ABS y Nylon c/Carga: los dos de Indarnyl. Juntos no llegan a los 400 kg.
    { comp_id: 101, codigo: '2455', descripcion: 'ABS GP 22 Natural', sector: 'Sector Materia Prima Plástica',
      sector_id: 14, proveedor: 'Indarnyl', um: 'kg', unidad: 'kg', kg_x_uni: null,
      consumo: 83, meses: 2.5, online: 0, minimo: 0, maximo: 225, pendiente_oc: 0, sugerido: 225,
      precio: 2.9, moneda: 'USD' },
    { comp_id: 102, codigo: '2485', descripcion: 'Nylon c/Carga 25%', sector: 'Sector Materia Prima Plástica',
      sector_id: 14, proveedor: 'Indarnyl', um: 'kg', unidad: 'kg', kg_x_uni: null,
      consumo: 51, meses: 2.5, online: 0, minimo: 0, maximo: 150, pendiente_oc: 0, sugerido: 150,
      precio: 3.1, moneda: 'USD' },
    // PE de Beta: su piso es 25 kg y el sugerido lo pasa, asi que nunca molesta.
    { comp_id: 103, codigo: '2435', descripcion: 'PE Polietileno Baja', sector: 'Sector Materia Prima Plástica',
      sector_id: 14, proveedor: 'Beta Plásticos', um: 'kg', unidad: 'kg', kg_x_uni: null,
      consumo: 16, meses: 2.5, online: 0, minimo: 0, maximo: 50, pendiente_oc: 0, sugerido: 50,
      precio: 2.7, moneda: 'USD' },
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

  // Sector Materia Prima Plastica -> proveedor Indarnyl: 225 + 150 = 375 kg, faltan 25 para los 400.
  await page.click('#rubros .chip:has-text("Materia Prima")');
  await page.click('#provs .chip:has-text("Indarnyl")');
  const aviso = await page.textContent('#reglaCarton');
  ok(/Indarnyl/.test(aviso) && /400/.test(aviso), 'avisa el minimo de Indarnyl: ' + aviso.replace(/\s+/g,' ').slice(0,90));
  ok(/faltan\s*25/.test(aviso.replace(/\./g,'')), 'dice cuantos kg faltan: ' + aviso.replace(/\s+/g,' ').slice(0,90));
  ok(await page.$eval('#btnCrear', x => x.disabled), 'con la OC por debajo del minimo no se puede crear');
  ok(!/Ajustar al múltiplo/.test(aviso), 'no ofrece "Ajustar al múltiplo" (eso es del carton, aca no hay nada que redondear)');

  // Subiendo el ABS a 250 kg el total llega a 400 y la OC queda valida.
  await page.fill('.pedir-in[data-in="101"]', '250');
  await page.dispatchEvent('.pedir-in[data-in="101"]', 'change');
  await page.waitForFunction(() => !document.getElementById('btnCrear').disabled);
  ok(!(await page.$eval('#btnCrear', x => x.disabled)), 'llegando a los 400 kg se habilita crear');
  ok(await page.$eval('#reglaCarton', x => x.classList.contains('hidden')), 'y el aviso desaparece');

  // Beta pide 25 y el sugerido es 50: nunca molesta.
  await page.click('#provs .chip:has-text("Beta")');
  ok(await page.$eval('#reglaCarton', x => x.classList.contains('hidden')), 'un proveedor cuyo piso ya se cumple no avisa nada');
  ok(!(await page.$eval('#btnCrear', x => x.disabled)), 'y deja crear la OC');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
