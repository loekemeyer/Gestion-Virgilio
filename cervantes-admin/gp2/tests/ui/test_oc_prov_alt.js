const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

/* UNA PIEZA SE LE PUEDE COMPRAR A MAS DE UN PROVEEDOR (2026-09-17, usuario: "en las ordenes de
   compra tendrias que agregar a recicor tambien").

   componente.proveedor es el PRINCIPAL (el que manda en el costo). Los otros que entregan lo
   mismo llegan en i.proveedores_alt (GP2.componente_proveedor_alt) y el precio de cada uno en
   i.precios_prov. Lo que fija este test:

     1. La botonera de proveedores del sector sale de principal + alternativos.
     2. Eligiendo el alternativo se ven SUS piezas (y no la que solo entrega el principal), y la
        columna Proveedor dice a quien se le esta comprando.
     3. EL PRECIO SIGUE AL PROVEEDOR ELEGIDO: la OC a Recicor sale con el precio de Recicor, no
        con el de Corrugadora (que es ~19% mas caro). Ese numero es el que se imprime y se le
        manda al proveedor, asi que equivocarlo es plata mal informada.
     4. Si el proveedor elegido NO cotizo esa pieza, la fila va SIN precio (no se rellena con el
        del otro) y la barra avisa cuantos items quedaron sin precio: si no, el total miente por
        lo bajo en silencio.
     5. Con el principal elegido, todo sigue exactamente como antes. */

function caja(id, cod, desc, alt, precios, sugerido) {
  return { comp_id: id, codigo: cod, descripcion: desc, sector: 'Sector Caja', sector_id: 11,
           proveedor: 'Corrugadora del Plata', proveedores_alt: alt, precios_prov: precios,
           um: 'unidad', unidad: 'uni', kg_x_uni: null,
           maximo: sugerido, maximo_inventario: sugerido, maximo_origen: 'fisico', stock: 0,
           consumo: 10, consumo_uni_mes: 10, meses: 6, online: 0, pendiente_oc: 0,
           sugerido: sugerido, sugerido_consumo: sugerido, es_pliego: false,
           precio: precios['Corrugadora del Plata'].precio, moneda: 'ARS',
           carton_formato: null, pliegos_multiplo: null, codigo_multiplo: null, min_codigo_x_multiplo: null };
}

const BUNDLE = {
  paq: 250, charcas_kg_x_paquete: 20, pliego_uni_x_paquete: 100, tc: 1535,
  insumos: [
    // La cotizan los dos: Recicor mas barata.
    caja(1, 'A1', 'Caja N°1', ['Recicor'],
         { 'Corrugadora del Plata': { precio: 245.53, moneda: 'ARS' }, 'Recicor': { precio: 199, moneda: 'ARS' } }, 100),
    // Recicor la ENTREGA pero no la cotizo: tiene que quedar sin precio.
    caja(2, 'A9B', 'Caja N°15', ['Recicor'],
         { 'Corrugadora del Plata': { precio: 344.26, moneda: 'ARS' } }, 10),
    // Solo la entrega Corrugadora.
    caja(3, 'A9', 'Caja N°22', [],
         { 'Corrugadora del Plata': { precio: 208, moneda: 'ARS' } }, 5),
  ],
  proveedores: [
    { nombre: 'Corrugadora del Plata', rubro: 'Sector Caja', cod_prov: '69587', activo: true, insumos: 3 },
    { nombre: 'Recicor', rubro: 'Sector Caja', cod_prov: '4370', activo: true, insumos: 2 },
  ],
  ocs: [],
  generado_en: '2026-09-17T10:00:00Z',
};

const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    window.__calls = window.__calls || [];
    window.__calls.push({name:name, args:args});
    if(name==='oc_bundle') return { data: ${JSON.stringify(BUNDLE)}, error: null };
    if(name==='crear_oc') return { data: { ok:true, oc_id: 10, numero: 2, items: (args.p.items||[]).length, oc_gemela: null }, error: null };
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

  // ── 1) los dos proveedores del sector ────────────────────────────────
  await page.click('#rubros .chip:has-text("Caja")');
  const provs = await page.$$eval('#provs .chip', xs => xs.map(x => x.textContent.trim()));
  ok(provs.join(' | ') === 'Corrugadora del Plata | Recicor',
     'la botonera trae principal + alternativo (salió: ' + provs.join(' | ') + ')');

  // ── 2) eligiendo el alternativo se ven SUS cajas ─────────────────────
  await page.click('#provs .chip:has-text("Recicor")');
  let filas = await page.$$eval('#tbody tr', xs => xs.map(x => x.getAttribute('data-id')));
  ok(filas.length === 2 && filas.indexOf('3') < 0,
     'Recicor muestra sus 2 cajas y no la que solo entrega Corrugadora (salió: ' + filas.join(',') + ')');
  const provCol = await page.$$eval('#tbody tr td:nth-child(2)', xs => xs.map(x => x.textContent.trim()));
  ok(provCol.every(t => t === 'Recicor'),
     'la columna Proveedor dice a quién se le está comprando (salió: ' + provCol.join(',') + ')');

  // ── 3 y 4) el precio sigue al proveedor, y lo que no cotizó queda sin precio ──
  await page.$eval('#btnSug', b => b.click())  /* oculto desde v1.37.0 */;
  const tot = (await page.textContent('#tot')).replace(/\s+/g, ' ');
  ok(/19\.900/.test(tot), 'el total usa el precio de Recicor: 100 × 199 = $ 19.900 (salió: ' + tot + ')');
  ok(!/23\.442|24\.995/.test(tot), 'no se coló el precio de Corrugadora en el total');
  ok(/1 ítem sin precio de Recicor/.test(tot), 'avisa el ítem que Recicor no cotizó (salió: ' + tot + ')');

  // ── 5) la OC baja al proveedor elegido y con su precio ───────────────
  await page.click('#btnCrear');
  await page.waitForTimeout(300);
  const call = await page.evaluate(() => (window.__calls || []).filter(c => c.name === 'crear_oc').pop());
  const it1 = call.args.p.items.filter(x => x.comp_id === 1)[0];
  const it2 = call.args.p.items.filter(x => x.comp_id === 2)[0];
  ok(call.args.p.proveedor === 'Recicor', 'crear_oc va a Recicor');
  ok(it1 && it1.precio === 199, 'el ítem viaja con el precio de Recicor (' + (it1 && it1.precio) + ')');
  ok(it2 && it2.precio === null, 'el que Recicor no cotizó viaja SIN precio, no con el de Corrugadora (' + (it2 && it2.precio) + ')');

  // ── 6) con el principal, todo como antes ─────────────────────────────
  await page.goto(ROOT + '/Compras/OC_GP2.html');
  await page.waitForFunction(() => document.getElementById('status').textContent === '');
  await page.click('#rubros .chip:has-text("Caja")');
  await page.click('#provs .chip:has-text("Corrugadora")');
  filas = await page.$$eval('#tbody tr', xs => xs.map(x => x.getAttribute('data-id')));
  ok(filas.length === 3, 'Corrugadora sigue con sus 3 cajas');
  await page.$eval('#btnSug', b => b.click())  /* oculto desde v1.37.0 */;
  const tot2 = (await page.textContent('#tot')).replace(/\s+/g, ' ');
  // 100×245,53 + 10×344,26 + 5×208 = 24.553 + 3.442,60 + 1.040 = 29.035,60
  ok(/29\.035/.test(tot2), 'el total del principal no cambió (salió: ' + tot2 + ')');
  ok(!/sin precio/.test(tot2), 'con Corrugadora no hay ítems sin precio');

  await browser.close();
})();
