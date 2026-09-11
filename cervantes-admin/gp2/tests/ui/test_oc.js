const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
// Raiz del repo (los tests viven en tests/ui/) y Chromium portable si existe.
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const BUNDLE = {
  paq: 250,
  // Kg por paquete de Charcas: viene del bundle (GP2.parametro.charcas_kg_x_paquete). Aca vale
  // 20 a proposito: si la pantalla siguiera con el 10 escrito, la cuenta de paquetes cambia.
  charcas_kg_x_paquete: 20,
  insumos: [
    { comp_id: 1, codigo: 'A1', descripcion: 'Fleje N 13', sector: 'Sector Fleje', sector_id: 5,
      proveedor: 'Basconia', um: 'kg', unidad: 'kg', kg_x_uni: null,
      consumo: 424.9, meses: 6, online: 100, pendiente_oc: 0, sugerido: 2449,
      precio: 1, moneda: 'USD',
      carton_formato: null, pliegos_multiplo: null, codigo_multiplo: null, min_codigo_x_multiplo: null },
    { comp_id: 2, codigo: 'B1', descripcion: 'Fleje N 2', sector: 'Sector Fleje', sector_id: 5,
      proveedor: 'Hermac', um: 'kg', unidad: 'kg', kg_x_uni: null,
      consumo: 50, meses: 6, online: 0, pendiente_oc: 0, sugerido: 300,
      precio: 1, moneda: 'USD',
      carton_formato: null, pliegos_multiplo: null, codigo_multiplo: null, min_codigo_x_multiplo: null },
    { comp_id: 3, codigo: 'CART506', descripcion: 'Carton 506', sector: 'Sector Carton', sector_id: 10,
      proveedor: 'Cartonero', um: 'uni', unidad: 'uni', kg_x_uni: null,
      consumo: 3000, meses: 6, online: 2000, pendiente_oc: 0, sugerido: 16000,
      precio: 1, moneda: 'USD',
      carton_formato: 'C', carton_categoria: 'Resto', marca: 'LOEKE', mezcla_libre: false,
      pliegos_multiplo: 12000, codigo_multiplo: 1000, min_codigo_x_multiplo: 1000 },
    { comp_id: 4, codigo: 'CARTPP', descripcion: 'Carton Pelapapas', sector: 'Sector Carton', sector_id: 10,
      proveedor: 'Cartonero', um: 'uni', unidad: 'uni', kg_x_uni: null,
      consumo: 1000, meses: 6, online: 0, pendiente_oc: 0, sugerido: 6000,
      precio: 1000, moneda: 'ARS',
      carton_formato: 'C', carton_categoria: 'Resto', marca: 'LOEKE', mezcla_libre: false,
      pliegos_multiplo: 12000, codigo_multiplo: 1000, min_codigo_x_multiplo: 1000 },
    // Insumo cotizado POR KG pero comprado por unidad (el clavo PCP3). El bundle tiene que
    // mandar el precio YA CONVERTIDO a la unidad de pedido: 3,30 USD/kg x 6,53 g = 0,0215.
    // Si algun dia vuelve a llegar 3,30 crudo, la OC infla el precio 153x y sale asi en la
    // hoja al proveedor (bug real del 2026-08-31, ver AUDITORIA_GP2_2026-08-31.md).
    { comp_id: 5, codigo: 'PCP3', descripcion: 'Clavo 505', sector: 'Sector Plastico', sector_id: 6,
      proveedor: 'Altrak', um: 'unidad', unidad: 'uni', kg_x_uni: 0.00653,
      consumo: 5000, meses: 2, online: 0, pendiente_oc: 0, sugerido: 10000,
      precio: 0.021549, moneda: 'USD',
      carton_formato: null, pliegos_multiplo: null, codigo_multiplo: null, min_codigo_x_multiplo: null },
    // El COMODIN: un sacacorchos se puede sumar a cualquier otra familia del tipo C
    // para completar el multiplo [usuario 2026-09-03].
    { comp_id: 6, codigo: 'CARTSC', descripcion: 'Carton 520', sector: 'Sector Carton', sector_id: 10,
      proveedor: 'Cartonero', um: 'unidad', unidad: 'uni', kg_x_uni: null,
      consumo: 500, meses: 6, online: 0, pendiente_oc: 0, sugerido: 3000,
      precio: 1, moneda: 'USD',
      carton_formato: 'C', carton_categoria: 'Sacacorchos', marca: 'LOEKE', mezcla_libre: true,
      pliegos_multiplo: 12000, codigo_multiplo: 1000, min_codigo_x_multiplo: 1000 },
    // Mismo formato LOKE, distinta MARCA: son dos pedidos distintos, no se suman.
    { comp_id: 7, codigo: 'LOKELK', descripcion: 'Carton LOKE Loekemeyer', sector: 'Sector Carton', sector_id: 10,
      proveedor: 'Cartonero', um: 'unidad', unidad: 'uni', kg_x_uni: null,
      consumo: 1000, meses: 6, online: 0, pendiente_oc: 0, sugerido: 8000,
      precio: 1, moneda: 'USD',
      carton_formato: 'LOKE', carton_categoria: null, marca: 'LOEKE', mezcla_libre: false,
      pliegos_multiplo: 16000, codigo_multiplo: 1000, min_codigo_x_multiplo: 1000 },
    { comp_id: 8, codigo: 'LOKECH', descripcion: 'Carton LOKE Chef', sector: 'Sector Carton', sector_id: 10,
      proveedor: 'Cartonero', um: 'unidad', unidad: 'uni', kg_x_uni: null,
      consumo: 1000, meses: 6, online: 0, pendiente_oc: 0, sugerido: 8000,
      precio: 1, moneda: 'USD',
      carton_formato: 'LOKE', carton_categoria: null, marca: 'CHEF', mezcla_libre: false,
      pliegos_multiplo: 16000, codigo_multiplo: 1000, min_codigo_x_multiplo: 1000 },
    // HUEVO: el pliego es de 25.000 y el minimo por codigo 2.000 [usuario 2026-09-03].
    { comp_id: 9, codigo: 'HUEVO1', descripcion: 'Carton Huevo 1', sector: 'Sector Carton', sector_id: 10,
      proveedor: 'Cartonero', um: 'unidad', unidad: 'uni', kg_x_uni: null,
      consumo: 3000, meses: 6, online: 0, pendiente_oc: 0, sugerido: 18000,
      precio: 1, moneda: 'USD',
      carton_formato: 'Huevo', carton_categoria: null, marca: 'LOEKE', mezcla_libre: false,
      pliegos_multiplo: 25000, codigo_multiplo: 1000, min_codigo_x_multiplo: 2000 },
    { comp_id: 10, codigo: 'HUEVO2', descripcion: 'Carton Huevo 2', sector: 'Sector Carton', sector_id: 10,
      proveedor: 'Cartonero', um: 'unidad', unidad: 'uni', kg_x_uni: null,
      consumo: 100, meses: 6, online: 0, pendiente_oc: 0, sugerido: 600,
      precio: 1, moneda: 'USD',
      carton_formato: 'Huevo', carton_categoria: null, marca: 'LOEKE', mezcla_libre: false,
      pliegos_multiplo: 25000, codigo_multiplo: 1000, min_codigo_x_multiplo: 2000 },
    // EL PLIEGO DEL 500: lleva carton_formato 'C' porque son 12 POSICIONES (eso es para el
    // costo), pero NO se pide por la familia del carton C — va de a 100 pliegos
    // [usuario 2026-09-03]. El bundle manda igual los multiplos del formato: el que tiene
    // que ignorarlos es la pantalla, mirando es_pliego.
    { comp_id: 11, codigo: 'Pliego 500', descripcion: 'Sin adhesivar', sector: 'Sector Carton', sector_id: 10,
      proveedor: 'Cartonero', um: 'unidad', unidad: 'uni', kg_x_uni: null,
      consumo: 40, meses: 6, online: 0, pendiente_oc: 0, sugerido: 250,
      precio: 917, moneda: 'ARS', es_pliego: true,
      carton_formato: 'C', carton_categoria: null, marca: 'LOEKE', mezcla_libre: false,
      pliegos_multiplo: 12000, codigo_multiplo: 1000, min_codigo_x_multiplo: 1000 },
    // BOLSA: no tiene multiplo (va de a 1) pero si PEDIDO MINIMO — 20.000 a Envases Vihal
    // [usuario 2026-09-03]. Son dos cosas distintas: el multiplo dice de a cuanto sube el
    // total, el minimo dice el piso para que el proveedor lo tome.
    { comp_id: 12, codigo: 'A1B', descripcion: 'Cartón 031', sector: 'Sector Carton', sector_id: 10,
      proveedor: 'Envases Vihal', um: 'unidad', unidad: 'uni', kg_x_uni: null,
      consumo: 500, meses: 6, online: 0, pendiente_oc: 0, sugerido: 3000,
      precio: 63, moneda: 'ARS',
      carton_formato: 'Bolsa', carton_categoria: null, marca: 'LOEKE', mezcla_libre: false,
      pliegos_multiplo: 1, codigo_multiplo: 1, min_codigo_x_multiplo: 1, pedido_minimo: 20000 },
    // CHARCAS: se pide en PAQUETES de charcas_kg_x_paquete kg (20 en este fixture / 0,01 kg
    // por unidad = 2.000 uni por paquete). El sugerido de 2.500 uni se redondea para arriba a
    // 2 paquetes, la pantalla manda unidad 'paq' y crear_oc lo guarda en kg.
    { comp_id: 13, codigo: 'EP10', descripcion: 'Bombilla EP10', sector: 'Sector Plastico', sector_id: 6,
      proveedor: 'Resortes Charcas', um: 'unidad', unidad: 'uni', kg_x_uni: 0.01,
      consumo: 400, meses: 6, online: 0, pendiente_oc: 0, sugerido: 2500,
      precio: 1, moneda: 'USD',
      carton_formato: null, pliegos_multiplo: null, codigo_multiplo: null, min_codigo_x_multiplo: null },
  ],
  ocs: [
    { id: 9, numero: 1, proveedor: 'Basconia', rubro: 'Fleje', estado: 'borrador', nota: 'prueba',
      creado_en: '2026-08-29T10:00:00Z',
      total_usd: 500, total_ars: 0,
      items: [ { codigo: 'A1', descripcion: 'Fleje N 13', cantidad: 500, unidad: 'kg', recibido: 0,
                 precio_uni: 1, moneda: 'USD', subtotal: 500 } ] },
    // La ANULADA no se muestra [usuario 2026-09-04]: sigue en la base, pero fuera de la lista.
    { id: 8, numero: 7, proveedor: 'Basconia', rubro: 'Fleje', estado: 'anulada', nota: null,
      creado_en: '2026-08-28T10:00:00Z', total_usd: 0, total_ars: 0, items: [] },
  ],
  pliego_uni_x_paquete: 100,
  tc: 1535,
  generado_en: '2026-08-29T10:00:00Z',
};

const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    window.__calls = window.__calls || [];
    window.__calls.push({name:name, args:args});
    if(name==='oc_bundle') return { data: ${JSON.stringify(BUNDLE)}, error: null };
    if(name==='crear_oc') return { data: { ok:true, oc_id: 10, numero: 2, items: (args.p.items||[]).length,
      // la OC a un PS hibrido devuelve la gemela al proveedor de su materia prima (generica desde 2026-09-05)
      oc_gemela: args.p.proveedor === 'Resortes Charcas'
        ? { oc_id: 11, numero: 3, proveedor: 'Altrak', componente: 'FLEJE90_BRUTO', kg: 40.8 } : null }, error: null };
    if(name==='oc_marcar') return { data: { ok:true }, error: null };
    return { data: null, error: { message: 'rpc desconocida '+name } };
  }
};}};
`;

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const page = await browser.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  page.on('console', m => { if (m.type() === 'error') console.log('CONSOLE:', m.text()); });

  await page.route('**/@supabase/supabase-js@2', r =>
    r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/gp2-modulo.css**', r => r.fulfill({ contentType: 'text/css', body: '.hidden{display:none!important}' }));
  await page.route('**/GP2_favicon.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));

  await page.goto(ROOT + '/Compras/OC_GP2.html');
  await page.waitForFunction(() => document.getElementById('status').textContent === '');

  const ok = (c, msg) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + msg); if (!c) process.exitCode = 1; };

  // chips de SECTOR (asi se llama en pantalla desde v1.19.0; el campo de la base
  // sigue siendo 'rubro')
  ok((await page.textContent('#panGen')).includes('Sector'), 'la botonera se llama Sector, no Rubro');
  const chips = await page.$$eval('#rubros .chip', xs => xs.map(x => x.textContent));
  ok(chips.join(',') === 'Fleje,Carton,Plastico', 'chips de sector: ' + chips.join(','));

  // SIN SECTOR NI PROVEEDOR NO HAY LISTA [usuario 2026-09-04: "si no pongo el sector y
  // no pongo el proveedor, que no me aparezca la lista"].
  ok(await page.$eval('#zonaLista', x => x.classList.contains('hidden')), 'sin elegir nada, no se muestra la lista');
  ok(!(await page.$eval('#elegiSector', x => x.classList.contains('hidden'))), 'se ve el cartel que pide elegir sector');
  ok(await page.$$eval('#tbody tr', x => x.length) === 0, 'y no hay ninguna fila cargada');

  // Al elegir el sector aparece todo
  await page.click('#rubros .chip:has-text("Carton")');
  ok(!(await page.$eval('#zonaLista', x => x.classList.contains('hidden'))), 'al elegir sector aparece la lista');
  await page.click('#rubros .chip:has-text("Carton")');   // se suelta: vuelve a esconderse
  ok(await page.$eval('#zonaLista', x => x.classList.contains('hidden')), 'al soltar el sector se esconde de nuevo');
  await page.click('#rubros .chip:has-text("Plastico")');

  // La tabla quedo en lo que se mira para pedir (v1.17.0): salieron Consumo/mes,
  // Sugerido y Precio.
  const heads = await page.evaluate(() => [].map.call(
    document.getElementById('tbody').closest('table').querySelectorAll('thead th'),
    x => x.textContent.replace(/\s+/g, '').trim()));
  ok(heads.join('|') === 'Insumo|Proveedor|Stockactual|Máximo|Pedir',
     'columnas: ' + heads.join(' · '));
  // La plata no se muestra por fila: se mira en la barra y en la OC ya creada.
  ok(!(await page.textContent('#tbody')).includes('US$'), 'no hay precios ni subtotales en la tabla');
  // El "mín N" debajo del stock tambien se saco [usuario: "eso no lo quiero ver"].
  ok(!(await page.textContent('#tbody')).includes('mín'), 'no aparece el minimo debajo del stock');

  // filtro Fleje -> 2 filas + chips proveedor
  await page.click('#rubros .chip:has-text("Fleje")');
  ok(await page.$$eval('#tbody tr', x => x.length) === 2, 'filtro rubro Fleje: 2 filas');
  const provChips = await page.$$eval('#provs .chip', xs => xs.map(x => x.textContent));
  ok(provChips.join(',') === 'Basconia,Hermac', 'chips proveedor: ' + provChips.join(','));

  // EL SUGERIDO YA VIENE EN "PEDIR" [usuario 2026-09-04]. A1 = 424,9 x 6 - 100 = 2449
  // (lo redondea el servidor): la fila llega con el numero puesto, sin tocar nada.
  ok(await page.$eval('.pedir-in[data-in="1"]', x => x.value) === '2449', 'el sugerido llega cargado en Pedir (2449)');
  ok(await page.$eval('.pedir-in[data-in="2"]', x => x.value) === '300', 'y el del otro fleje tambien (300)');
  const filaA1 = await page.textContent('tr[data-id="1"]');
  // El cartel de abajo DICE que ese numero es el sugerido y de donde sale [usuario:
  // "que me aclare que es el sugerido"]. (En el bundle de prueba no hay maximo cargado,
  // asi que la cuenta cae al consumo.)
  ok(await page.$eval('tr[data-id="1"] .sug-lb', x => x.textContent.trim()) === 'sugerido 2.449',
     'el cartel aclara que es el sugerido y cuanto es');
  ok(/(?:máx|cons)/.test(filaA1) && filaA1.includes('stock'), 'y de donde sale: ' +
     filaA1.replace(/\s+/g, ' ').slice(0, 120));
  const tot1 = (await page.textContent('#tot')).trim();
  ok(tot1.startsWith('2 ítems'), 'barra: los 2 flejes del rubro ya cuentan (' + tot1 + ')');
  // (2449 + 300) kg x US$ 1 = US$ 2.749; con el dolar del cron (1535) ~ $ 4.219.715
  ok(tot1.includes('US$ 2.749') && tot1.includes('4.219.715'), 'barra valorizada: ' + tot1);
  ok(!(await page.$eval('#btnCrear', b => b.disabled)), 'btnCrear habilitado');

  // VACIAR EL CAMPO = "este no lo pido": el sugerido NO se vuelve a cargar solo.
  await page.fill('.pedir-in[data-in="2"]', '');
  await page.dispatchEvent('.pedir-in[data-in="2"]', 'change');
  ok(await page.$eval('.pedir-in[data-in="2"]', x => x.value) === '', 'vaciado se queda vacio (no se recarga solo)');
  ok((await page.textContent('#tot')).trim().startsWith('1 ítems'), 'y sale de la cuenta de la barra');
  // El cartel del sugerido sigue estando aunque el campo este vacio o pisado: es la
  // referencia contra la que se cambia.
  ok(await page.$eval('tr[data-id="2"] .sug-lb', x => x.textContent.trim()) === 'sugerido 300',
     'el cartel del sugerido queda aunque el campo este vacio');
  // "Usar sugeridos" lo repone
  await page.click('#btnSug');
  ok(await page.$eval('.pedir-in[data-in="2"]', x => x.value) === '300', '"Usar sugeridos" repone lo vaciado');

  // EL PRECIO SE FUE DE LA TABLA [usuario 2026-09-04: "precio se va y subtotal tambien"],
  // pero NO del circuito: sigue valorizando la barra (y mas abajo, el payload de crear_oc).
  ok((await page.$$('.precio-in')).length === 0 && (await page.$$('.mon-btn')).length === 0,
     'no queda campo de precio ni boton de moneda en la tabla');

  // filtro proveedor Basconia y crear OC
  await page.click('#provs .chip:has-text("Basconia")');
  ok(await page.$$eval('#tbody tr', x => x.length) === 1, 'filtro proveedor: 1 fila');
  await page.fill('#nota', 'nota test');
  await page.click('#btnCrear');
  await page.waitForFunction(() => (window.__calls || []).some(c => c.name === 'crear_oc'));
  const call = await page.evaluate(() => window.__calls.filter(c => c.name === 'crear_oc')[0].args.p);
  ok(call.proveedor === 'Basconia' && call.rubro === 'Fleje' && call.nota === 'nota test', 'payload cabecera OK');
  ok(call.items.length === 1 && call.items[0].comp_id === 1 && call.items[0].cantidad === 2449 && call.items[0].unidad === 'kg',
     'payload items OK: ' + JSON.stringify(call.items));
  // El precio ya no se pisa en pantalla, pero SIGUE viajando (el de la lista): sin esto
  // la OC se guardaria sin plata y la hoja al proveedor saldria en blanco.
  ok(call.items[0].precio === 1 && call.items[0].moneda === 'USD', 'el precio de lista viaja igual: ' + JSON.stringify(call.items[0]));

  // tras crear pasa a tab Ordenes
  ok(!(await page.$eval('#panOcs', x => x.classList.contains('hidden'))), 'muestra tab Ordenes tras crear');
  ok((await page.textContent('.oc-card .num-oc')).includes('OC N° 1'), 'OC listada');
  const cardTxt = await page.textContent('.oc-card');
  ok(cardTxt.includes('US$ 500'), 'OC listada con total y subtotal US$ 500');
  // La ANULADA no se muestra [usuario 2026-09-04: "si anula una orden de compra, no
  // quiero que me siga apareciendo en ordenes"]. Sigue en la base, no en la pantalla.
  ok((await page.$$('.oc-card')).length === 1, 'la OC anulada no se lista');
  ok(!(await page.textContent('#ocsList')).includes('OC N° 7'), 'y no queda rastro de la anulada');
  ok((await page.textContent('#ocsN')).trim() === '(1)', 'el contador del tab no cuenta la anulada');

  // ── CHARCAS: paquetes de charcas_kg_x_paquete kg (del bundle), unidad 'paq' a crear_oc y la
  // OC gemela generica en el mensaje (2026-09-05, ciclos 9-10 de la auditoria) ──
  await page.click('#tabGen');
  await page.click('#rubros .chip:has-text("Plastico")');
  await page.click('#provs .chip:has-text("Resortes Charcas")');
  ok(await page.$$eval('#tbody tr', x => x.length) === 1, 'Charcas: 1 fila (EP10)');
  // 2.500 uni sugeridas; 1 paquete = 20 kg / 0,01 kg = 2.000 uni -> 2 paquetes (para arriba).
  // Con el 10 que antes estaba escrito en la pantalla darian 3.
  ok(await page.$eval('.pedir-in[data-in="13"]', x => x.value) === '2', 'el sugerido de Charcas llega en paquetes y usa el kg por paquete del bundle (2)');
  const eqCh = (await page.textContent('tr[data-id="13"] .paq-eq')).replace(/\s+/g, ' ').trim();
  ok(eqCh.includes('4.000') && eqCh.includes('uni'), 'la equivalencia dice 2 paq = 4.000 uni: ' + eqCh);
  await page.click('#btnCrear');
  await page.waitForFunction(() => (window.__calls || []).filter(c => c.name === 'crear_oc').length === 2);
  const callCh = await page.evaluate(() => window.__calls.filter(c => c.name === 'crear_oc')[1].args.p);
  ok(callCh.proveedor === 'Resortes Charcas' && callCh.items.length === 1 && callCh.items[0].comp_id === 13
     && callCh.items[0].cantidad === 2 && callCh.items[0].unidad === 'paq',
     'a crear_oc viajan los PAQUETES con unidad paq (la base los guarda en kg): ' + JSON.stringify(callCh.items));
  await page.waitForFunction(() => document.getElementById('status').textContent.includes('gemela'));
  const stCh = (await page.textContent('#status')).replace(/\s+/g, ' ').trim();
  ok(stCh.includes('OC gemela N° 3 a Altrak') && stCh.includes('40,8 kg de FLEJE90_BRUTO'),
     'el mensaje de la OC gemela sale de la respuesta generica (proveedor + componente + kg): ' + stCh.slice(0, 140));
  // se suelta el proveedor para que el bloque de cartones vea todas sus filas
  await page.click('#tabGen');
  if (await page.evaluate(() => provSel !== null)) await page.click('#provs .chip:has-text("Resortes Charcas")');
  ok(await page.evaluate(() => provSel === null), 'proveedor Charcas soltado');

  // volver a Generar y validar reglas de carton
  await page.click('#tabGen');
  await page.click('#rubros .chip:has-text("Carton")');
  // Los cartones tambien llegan con el sugerido puesto y YA redondeado a su familia:
  // asi era antes con "Usar sugeridos" y asi tiene que estar sin tocar nada.
  ok(await page.$eval('#reglaCarton', x => x.classList.contains('hidden')),
     'el carton llega valido de fabrica (el sugerido entra redondeado a la familia)');
  // Para probar las reglas a mano se parte de la tabla vacia.
  await page.click('#btnLimpiar');
  ok(await page.$eval('.pedir-in[data-in="3"]', x => x.value) === '', '"Limpiar" deja los campos vacios y no los recarga');
  // 1500 no es multiplo de 1000
  await page.fill('.pedir-in[data-in="3"]', '1500');
  await page.$eval('.pedir-in[data-in="3"]', x => x.dispatchEvent(new Event('change')));
  let regla = await page.textContent('#reglaCarton');
  ok(!(await page.$eval('#reglaCarton', x => x.classList.contains('hidden'))) && regla.includes('múltiplo de 12.000'),
     'total no multiplo de 12000 bloquea: ' + regla.trim().slice(0, 60));
  ok(await page.$eval('#btnCrear', b => b.disabled), 'btnCrear bloqueado con regla rota');

  // 11000 + 1000 = 12000 total, ambos multiplos de 1000, minimo 1000 -> valido
  await page.fill('.pedir-in[data-in="3"]', '11000');
  await page.$eval('.pedir-in[data-in="3"]', x => x.dispatchEvent(new Event('change')));
  await page.fill('.pedir-in[data-in="4"]', '1000');
  await page.$eval('.pedir-in[data-in="4"]', x => x.dispatchEvent(new Event('change')));
  ok(await page.$eval('#reglaCarton', x => x.classList.contains('hidden')), '12000 valido (11000+1000)');
  ok(!(await page.$eval('#btnCrear', b => b.disabled)), 'btnCrear habilitado con carton valido');
  // equivalencia en paquetes visible
  const paq = await page.textContent('tr[data-id="3"] .paq-eq');
  ok(paq.includes('44') && paq.includes('paq'), 'equivalencia paquetes: ' + paq.trim());

  // El minimo por codigo es FIJO (el paquete), NO escala con el multiplo [usuario
  // 2026-09-03: "el paquete viene a mil, se puede recibir a mil"]. 23.000 + 1.000 = 24.000,
  // dos multiplos, y el de 1.000 sigue estando bien: con el minimo escalado habria dado
  // error pidiendole 2.000, y una familia con muchos codigos no cerraba nunca.
  await page.fill('.pedir-in[data-in="3"]', '23000');
  await page.$eval('.pedir-in[data-in="3"]', x => x.dispatchEvent(new Event('change')));
  ok(await page.$eval('#reglaCarton', x => x.classList.contains('hidden')),
     'el minimo por codigo NO escala: 23.000 + 1.000 es valido');
  // Y abajo del minimo si avisa. Se usa el HUEVO, que es el unico donde el minimo
  // (2.000) es mayor que el paso (1.000) y por lo tanto se puede quedar corto siendo
  // multiplo: 24.000 + 1.000 = 25.000 cierra el pliego, pero ese 1.000 no llega al minimo.
  await page.fill('.pedir-in[data-in="9"]', '24000');
  await page.$eval('.pedir-in[data-in="9"]', x => x.dispatchEvent(new Event('change')));
  await page.fill('.pedir-in[data-in="10"]', '1000');
  await page.$eval('.pedir-in[data-in="10"]', x => x.dispatchEvent(new Event('change')));
  regla = await page.textContent('#reglaCarton');
  ok(/mínimo 2\.000 por código/.test(regla) && !/para un pedido de/.test(regla),
     'abajo del paquete avisa, y sin hablar de multiplos: ' + regla.trim().slice(0, 90));

  // "Usar sugeridos" deja el carton YA VALIDO (usuario 2026-09-03: "sí, redondeá
  // para arriba"). Sugeridos 16.000 + 6.000 = 22.000 -> el total sube al multiplo
  // siguiente (24.000) y lo que falta se reparte de a 1.000 empezando por el que
  // mas pidio: 17.000 + 7.000. Ademas 24.000 son dos multiplos, asi que el minimo
  // por codigo pasa a 2.000 y los dos lo cumplen.
  await page.click('#btnLimpiar');
  await page.click('#btnSug');
  const val = async id => Number(await page.$eval('.pedir-in[data-in="' + id + '"]', x => x.value));
  // Familia C · LOEKE: Resto (16.000 + 6.000) + el sacacorchos comodin (3.000) = 25.000,
  // que sube al multiplo siguiente, 36.000, y lo que falta se reparte de a 1.000.
  const totC = (await val(3)) + (await val(4)) + (await val(6));
  ok(totC === 36000, 'la familia C junta al sacacorchos y redondea a 36.000 (dio ' + totC + ')');
  ok((await val(6)) >= 3000, 'el comodin tambien respeta el minimo por codigo (3.000 con multiplo 3)');
  // LOKE: las dos marcas NO se suman. 8.000 de cada una serian 16.000 juntas, pero como
  // van por separado cada una sube a su propio 16.000 [usuario: "una marca va con un
  // pliego y la otra con el otro"].
  ok((await val(7)) === 16000 && (await val(8)) === 16000,
     'LOKE LOEKE y LOKE CHEF se piden por separado, 16.000 cada una');
  // HUEVO: 18.000 + 600 = 18.600 sube al pliego de 25.000, y el chico (600) tiene que
  // llegar al minimo de 2.000 por codigo aunque haya pedido mucho menos.
  const h1 = await val(9), h2 = await val(10);
  ok(h1 + h2 === 25000, 'el huevo cierra en el pliego de 25.000 (' + h1 + ' + ' + h2 + ')');
  ok(h2 >= 2000, 'y el codigo chico sube al minimo de 2.000 (pidio 600, va ' + h2 + ')');
  // EL PLIEGO no se contagia del formato C: 250 sube a 300 (paquetes de 100), no a 12.000.
  const pl = await val(11);
  ok(pl === 300, 'el pliego va de a 100, no arrastra el multiplo del carton C (dio ' + pl + ')');
  // LA BOLSA: pide 3.000 por consumo pero el proveedor no toma menos de 20.000.
  const bolsa = await val(12);
  ok(bolsa === 20000, 'la bolsa sube al pedido mínimo de 20.000 (pidió 3.000, va ' + bolsa + ')');
  ok(await page.$eval('#reglaCarton', x => x.classList.contains('hidden')), 'y no queda ningun error de regla');
  ok(!(await page.$eval('#btnCrear', b => b.disabled)), 'la OC de cartones queda lista para crear');

  // Y si se escribe a mano algo que rompe la regla, el cartel ofrece arreglarlo
  await page.fill('.pedir-in[data-in="3"]', '1500');
  await page.$eval('.pedir-in[data-in="3"]', x => x.dispatchEvent(new Event('change')));
  ok(!(await page.$eval('#reglaCarton', x => x.classList.contains('hidden'))), 'a mano se puede romper la regla');
  await page.click('#btnAjustarCart');
  ok(await page.$eval('#reglaCarton', x => x.classList.contains('hidden')),
     '"Ajustar al múltiplo" lo deja valido de nuevo');
  // 1.500 sube a 2.000 (multiplo de codigo); con los otros dos de la familia quedan
  // 18.000, que sube al multiplo siguiente (24.000) repartiendo de a 1.000.
  const a3 = await val(3), a4 = await val(4), a6 = await val(6);
  ok(a3 + a4 + a6 === 24000 && a3 >= 2000 && a4 >= 2000 && a6 >= 2000,
     'ajusta para arriba a 24.000 respetando el minimo por codigo (' + [a3, a4, a6].join(' + ') + ')');

  // Bajarla a mano por debajo del mínimo tiene que avisar, y con las palabras del piso
  // (no del múltiplo, que en la bolsa es 1 y siempre da bien).
  await page.fill('.pedir-in[data-in="12"]', '10000');
  await page.$eval('.pedir-in[data-in="12"]', x => x.dispatchEvent(new Event('change')));
  regla = await page.textContent('#reglaCarton');
  ok(/pedido mínimo es 20\.000/.test(regla), 'avisa si no llega al mínimo: ' + regla.trim().slice(0, 90));

  // "Pedir" es AHORA el unico campo de la fila: tiene que ser tocable (44px) y con
  // letra grande, que es la regla de la casa para todo lo que se carga a mano.
  const cajaPedir = await page.$eval('.pedir-in',
    x => { const r = x.getBoundingClientRect(); const s = getComputedStyle(x);
           return [Math.round(r.width), Math.round(r.height), parseFloat(s.fontSize)]; });
  ok(cajaPedir[0] >= 44 && cajaPedir[1] >= 44, 'el campo Pedir se toca bien (' + cajaPedir[0] + 'x' + cajaPedir[1] + ')');
  ok(cajaPedir[2] >= 18, 'y la letra del campo Pedir es grande (' + cajaPedir[2] + 'px)');
  // Y no quedan restos de las dos columnas que se fueron (Sugerido y Consumo/mes).
  ok((await page.$$('.sug')).length === 0 && (await page.$$('.cd-tocable')).length === 0,
     'no quedan celdas de Sugerido ni de Consumo/mes en la tabla');

  // acciones de OC: marcar enviada
  await page.click('#tabOcs');
  await page.click('.oc-acts button.env');
  await page.waitForFunction(() => (window.__calls || []).some(c => c.name === 'oc_marcar'));
  const mc = await page.evaluate(() => window.__calls.filter(c => c.name === 'oc_marcar')[0].args);
  ok(mc.p_oc_id === 9 && mc.p_estado === 'enviada', 'oc_marcar enviada OK');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
