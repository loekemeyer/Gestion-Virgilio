/* EL GATILLO DE REPOSICION de la OC (v1.26.0): lo dispara el MAXIMO y nada mas
   [usuario 2026-09-14, textual: "lo de minimo borralo. la orden de compra tiene que
   disparar segun el maximo. es algo que habiamos hecho mal"]. La columna
   inventario.minimo se borro de la base ese dia, junto con el estado intermedio
   'viaje' y el boton "Aprovechar el viaje".
     'pedir'       stock < maximo  -> se carga solo, hasta el maximo.
     'lleno'       stock >= maximo -> no se carga solo (y el sugerido da 0).
     'sin-gatillo' sin maximo o sin stock -> se carga solo igual (fail-safe).
   Lo que NO cambio: la fila que ya tiene algo en camino avisa y no se carga sola, y
   "Usar sugeridos" es la orden explicita que pisa las dos cosas.
   Fixture propio (no toca el de test_oc.js, que prueba las reglas de carton). */
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
    // 1) ABAJO DEL MAXIMO -> hay que pedir, hasta el maximo. Se carga solo.
    Object.assign({ comp_id: 1, codigo: 'G1', descripcion: 'Abajo del maximo',
      stock: 50, maximo: 1000, pendiente_oc: 0, sugerido: 950 }, base),
    // 2) TAMBIEN ABAJO, PERO MENOS -> con la regla vieja era 'viaje' y quedaba afuera;
    //    ahora entra igual, porque el unico gatillo es el maximo.
    Object.assign({ comp_id: 2, codigo: 'G2', descripcion: 'Abajo por poco',
      stock: 500, maximo: 1000, pendiente_oc: 0, sugerido: 500 }, base),
    // 3) ABAJO DEL MAXIMO PERO YA PEDIDO -> avisa lo que viene en camino y no se carga solo.
    Object.assign({ comp_id: 3, codigo: 'G3', descripcion: 'Ya pedido',
      stock: 50, maximo: 1000, pendiente_oc: 400, sugerido: 950 }, base),
    // 4) SIN MAXIMO -> no hay con que decidir: fail-safe, se carga solo.
    Object.assign({ comp_id: 4, codigo: 'G4', descripcion: 'Sin maximo',
      stock: 0, maximo: null, pendiente_oc: 0, sugerido: 1000 }, base),
    // 5) LLENO (stock >= maximo) -> no se carga solo. El sugerido real es 0.
    Object.assign({ comp_id: 5, codigo: 'G5', descripcion: 'Lleno',
      stock: 900, maximo: 800, pendiente_oc: 0, sugerido: 0 }, base),
  ],
  ocs: [], pliego_uni_x_paquete: 100, tc: 1500, generado_en: '2026-09-14T10:00:00Z',
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

  // EL GATILLO: se carga solo todo lo que esta abajo del maximo.
  ok(await val(1) === '950', 'abajo del maximo: se carga solo, hasta el maximo (950)');
  ok(await val(2) === '500', 'abajo por poco: TAMBIEN se carga solo (ya no hay estado intermedio)');
  ok(await val(3) === '', 'lo que ya viene en camino: NO se carga solo');
  ok(await val(4) === '1000', 'sin maximo: fail-safe, se carga solo');
  ok(await val(5) === '', 'lleno (stock >= maximo): NO se carga solo');

  // Y la fila DICE por que.
  // Los cartelitos "hay que pedir" / "no hace falta" se sacaron en v1.35.0 [Thomas
  // 2026-09-28: "elimina todos esos textos"]: lo dice el stock en rojo.
  const rojo = id => page.$('tr[data-id="' + id + '"] td.bajo-min').then(x => !!x);
  ok(await rojo(1) && await rojo(2), 'abajo del maximo: stock en rojo');
  ok((await fila(3)).includes('ya pediste 400 kg'), 'la fila avisa lo que ya viene en camino');
  ok(!(await rojo(4)), 'sin maximo no inventa un estado de gatillo');
  ok(!(await rojo(5)) && !(await fila(5)).includes('hay que pedir'), 'la fila llena no se pinta ni dice nada');

  // "Aprovechar el viaje" se fue con el minimo: no queda nada afuera que aprovechar.
  ok(await page.$('#btnViaje') === null, 'ya no existe el boton "Aprovechar el viaje"');

  // "Usar sugeridos" sigue siendo la orden explicita: pisa el aviso de "en camino".
  await page.$eval('#btnLimpiar', b => b.click())  /* oculto desde v1.37.0 */;
  ok(await val(1) === '' && await val(2) === '', 'limpiar deja todo en cero');
  await page.$eval('#btnSug', b => b.click())  /* oculto desde v1.37.0 */;
  ok(await val(1) === '950' && await val(2) === '500' && await val(3) === '950',
     '"Usar sugeridos" carga TODO lo visible, tambien lo que viene en camino');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
