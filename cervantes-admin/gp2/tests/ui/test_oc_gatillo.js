/* EL GATILLO DE REPOSICION de la OC (idea 7273, v1.21.0): el MINIMO dispara y el MAXIMO
   dimensiona, y la fila que ya tiene algo en camino avisa en vez de volver a pedirlo.
   Fixture propio (no toca el de test_oc.js, que prueba las reglas de carton con el
   contrato VIEJO -- sin minimo -- y por eso alli todo cae en 'sin-gatillo'). */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const base = { sector: 'Sector Fleje', sector_id: 5, proveedor: 'Basconia', um: 'kg', unidad: 'kg',
  kg_x_uni: null, precio: 1, moneda: 'USD', maximo_origen: 'fisico',
  carton_formato: null, pliegos_multiplo: null, codigo_multiplo: null, min_codigo_x_multiplo: null };

const BUNDLE = {
  paq: 250,
  insumos: [
    // 1) BAJO MINIMO -> hay que pedir, y se pide hasta el maximo. Se carga solo.
    Object.assign({ comp_id: 1, codigo: 'G1', descripcion: 'Bajo minimo',
      stock: 50, minimo: 100, maximo: 1000, pendiente_oc: 0, sugerido: 950 }, base),
    // 2) ARRIBA DEL MINIMO -> todavia no hace falta. NO se carga solo.
    Object.assign({ comp_id: 2, codigo: 'G2', descripcion: 'Arriba del minimo',
      stock: 500, minimo: 100, maximo: 1000, pendiente_oc: 0, sugerido: 500 }, base),
    // 3) BAJO MINIMO PERO YA PEDIDO -> avisa lo que viene en camino y no se carga solo.
    Object.assign({ comp_id: 3, codigo: 'G3', descripcion: 'Ya pedido',
      stock: 50, minimo: 100, maximo: 1000, pendiente_oc: 400, sugerido: 950 }, base),
    // 4) SIN MINIMO -> no hay con que decidir: se comporta como antes (se carga solo).
    Object.assign({ comp_id: 4, codigo: 'G4', descripcion: 'Sin minimo',
      stock: 0, minimo: null, maximo: 1000, pendiente_oc: 0, sugerido: 1000 }, base),
    // 5) CONFIG ROTA (minimo >= maximo, hoy son 52 lineas reales) -> tambien como antes.
    Object.assign({ comp_id: 5, codigo: 'G5', descripcion: 'Config rota',
      stock: 500, minimo: 900, maximo: 800, pendiente_oc: 0, sugerido: 300 }, base),
  ],
  ocs: [], pliego_uni_x_paquete: 100, tc: 1500, generado_en: '2026-09-08T10:00:00Z',
};

const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    if(name==='oc_bundle') return { data: ${JSON.stringify(BUNDLE)}, error: null };
    return { data: { ok:true }, error: null };
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
  const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) process.exitCode = 1; };
  const val = id => page.$eval('.pedir-in[data-in="' + id + '"]', x => x.value);
  const fila = id => page.textContent('tr[data-id="' + id + '"]');

  await page.click('#rubros .chip:has-text("Fleje")');
  ok(await page.$$eval('#tbody tr', x => x.length) === 5, 'las 5 filas del fixture');

  // EL GATILLO: solo se carga solo lo que hace falta.
  ok(await val(1) === '950', 'bajo minimo: se carga solo, hasta el maximo (950)');
  ok(await val(2) === '', 'arriba del minimo: NO se carga solo');
  ok(await val(3) === '', 'lo que ya viene en camino: NO se carga solo');
  ok(await val(4) === '1000', 'sin minimo: se comporta como antes (fail-safe)');
  ok(await val(5) === '300', 'config rota (min >= max): se comporta como antes (fail-safe)');

  // Y la fila DICE por que.
  ok((await fila(1)).includes('hay que pedir'), 'la fila bajo minimo dice "hay que pedir"');
  ok((await fila(2)).includes('no hace falta'), 'la fila arriba del minimo dice "no hace falta"');
  ok((await fila(3)).includes('ya pediste 400 kg'), 'la fila avisa lo que ya viene en camino');
  ok(!(await fila(4)).includes('hay que pedir') && !(await fila(4)).includes('no hace falta'),
     'sin minimo no inventa un estado de gatillo');
  ok(!(await fila(5)).includes('no hace falta'), 'config rota no inventa un estado de gatillo');

  // "Aprovechar el viaje": la valvula de escape. Solo cuenta el que no hace falta y esta vacio.
  ok(!(await page.$eval('#btnViaje', x => x.classList.contains('hidden'))), 'aparece "Aprovechar el viaje"');
  ok((await page.textContent('#btnViaje')).trim() === 'Aprovechar el viaje (1)', 'y cuenta 1');
  await page.click('#btnViaje');
  ok(await val(2) === '500', 'al aprovechar el viaje se carga el que no hacia falta');
  ok(await page.$eval('#btnViaje', x => x.classList.contains('hidden')), 'y el boton se esconde: no queda ninguno');
  ok(await val(3) === '', 'aprovechar el viaje NO toca lo que ya viene en camino');

  // "Usar sugeridos" es la orden explicita: pisa el gatillo y el aviso.
  await page.click('#btnLimpiar');
  ok(await val(1) === '' && await val(2) === '', 'limpiar deja todo en cero');
  await page.click('#btnSug');
  ok(await val(1) === '950' && await val(2) === '500' && await val(3) === '950' && await val(5) === '300',
     '"Usar sugeridos" carga TODO lo visible, tambien lo que el gatillo dejo afuera');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
