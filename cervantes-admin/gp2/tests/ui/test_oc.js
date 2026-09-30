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
    /* EL CONTRATO DE HOY (idea 7242). Desde el 2026-09-03 oc_bundle manda maximo / stock /
       maximo_origen y el sugerido es MAXIMO − STOCK; el consumo viaja igual pero sólo se usa
       cuando no hay máximo. Hasta el 2026-09-13 este fixture no tenía ni un `maximo`: la suite
       pasaba en verde probando la fórmula vieja (consumo × meses), que en la base ya no existe.
       Las claves y los valores de acá salen de una corrida real de `oc_bundle`. */
    { comp_id: 1, codigo: 'A1', descripcion: 'Fleje N 13', sector: 'Sector Fleje', sector_id: 5,
      proveedor: 'Basconia', um: 'kg', unidad: 'kg', kg_x_uni: null,
      maximo: 2549, maximo_inventario: 2549, maximo_origen: 'fisico', stock: 100,
      consumo: 424.9, consumo_uni_mes: 424.9, meses: 6, online: 100, pendiente_oc: 0,
      sugerido: 2449, sugerido_consumo: 2449, es_pliego: false,
      precio: 1, moneda: 'USD',
      carton_formato: null, pliegos_multiplo: null, codigo_multiplo: null, min_codigo_x_multiplo: null },
    { comp_id: 2, codigo: 'B1', descripcion: 'Fleje N 2', sector: 'Sector Fleje', sector_id: 5,
      proveedor: 'Hermac', um: 'kg', unidad: 'kg', kg_x_uni: null,
      maximo: 300, maximo_inventario: 300, maximo_origen: 'est_madre', stock: 0,
      consumo: 50, consumo_uni_mes: 50, meses: 6, online: 0, pendiente_oc: 0,
      sugerido: 300, sugerido_consumo: 300, es_pliego: false,
      precio: 1, moneda: 'USD',
      carton_formato: null, pliegos_multiplo: null, codigo_multiplo: null, min_codigo_x_multiplo: null },
    { comp_id: 3, codigo: 'CART506', descripcion: 'Carton 506', sector: 'Sector Carton', sector_id: 10,
      proveedor: 'Cartonero', um: 'uni', unidad: 'uni', kg_x_uni: null,
      consumo: 3000, meses: 6, online: 2000, pendiente_oc: 0, sugerido: 16000,
      precio: 1, moneda: 'USD',
      carton_formato: 'C', pedido_minimo_uni: 12000, carton_categoria: 'Resto', marca: 'LOEKE', mezcla_libre: false,
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
      carton_formato: 'Huevo', pedido_minimo_uni: 2000, carton_categoria: null, marca: 'LOEKE', mezcla_libre: false,
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
    { comp_id: 13, codigo: 'EP10', descripcion: 'Bombilla EP10', sector: 'Sector Plastico', sector_id: 6, familia_pedido: 'Pirolos', familia_minimo: 36000,
      proveedor: 'Resortes Charcas', um: 'unidad', unidad: 'uni', kg_x_uni: 0.01,
      maximo: 2500, maximo_inventario: 2500, maximo_origen: 'est_madre', stock: 0,
      consumo: 400, consumo_uni_mes: 400, meses: 6, online: 0, pendiente_oc: 0,
      sugerido: 2500, sugerido_consumo: 2500, es_pliego: false,
      precio: 1, moneda: 'USD',
      carton_formato: null, pliegos_multiplo: null, codigo_multiplo: null, min_codigo_x_multiplo: null },

    /* ── LOS TRES CASOS QUE LA FORMULA VIEJA NO PODIA PROBAR (idea 7242) ──────────────
       Copiados de filas REALES de oc_bundle (A5, W8 y A1 de Corrugadora del Plata), con el
       codigo cambiado. Los tres estan en Sector Plastico a proposito: agregar un sector
       nuevo movia los chips y no es lo que se quiere probar aca. */
    // 1. TECHO FISICO MUY POR ENCIMA DEL CONSUMO (el A5 real: entran 9.400 en el lugar y se
    //    consumen 9 por mes). Con la formula vieja pediria 54; con la de hoy, 9.400.
    { comp_id: 14, codigo: 'MAXFIS', descripcion: 'Techo fisico arriba del consumo', sector: 'Sector Plastico', sector_id: 6,
      proveedor: 'Inyectores SA', um: 'unidad', unidad: 'uni', kg_x_uni: null,
      maximo: 9400, maximo_inventario: 9400, maximo_origen: 'fisico', stock: 0,
      consumo: 9, consumo_uni_mes: 9, meses: 6, online: 0, pendiente_oc: 0,
      sugerido: 9400, sugerido_consumo: 54, minimo: 28, es_pliego: false,
      precio: 499.74, moneda: 'ARS',
      carton_formato: null, pliegos_multiplo: null, codigo_multiplo: null, min_codigo_x_multiplo: null },
    // 2. TECHO MUY POR DEBAJO DEL CONSUMO (el W8 real: entran 726 y el consumo de 6 meses son
    //    5.228). El maximo MANDA: se pide lo que entra, no lo que se consume.
    { comp_id: 15, codigo: 'MAXBAJO', descripcion: 'Techo fisico abajo del consumo', sector: 'Sector Plastico', sector_id: 6, familia_pedido: 'Pirolos', familia_minimo: 36000,
      proveedor: 'Inyectores SA', um: 'unidad', unidad: 'uni', kg_x_uni: null,
      maximo: 726, maximo_inventario: 726, maximo_origen: 'fisico', stock: 0,
      consumo: 871.3, consumo_uni_mes: 871.3, meses: 6, online: 0, pendiente_oc: 0,
      sugerido: 726, sugerido_consumo: 5228, minimo: 100, es_pliego: false,
      precio: 10, moneda: 'ARS',
      carton_formato: null, pliegos_multiplo: null, codigo_multiplo: null, min_codigo_x_multiplo: null },
    // 3. EL GATILLO (v1.26.0): lo unico que decide es el MAXIMO. Esta fila tiene stock 9.000
    //    contra un techo de 11.625, asi que SE CARGA SOLA con los 2.625 que faltan. Con la regla
    //    vieja (minimo 8.684) quedaba afuera: ese estado intermedio ya no existe.
    //    Su maximo viene del Master Bach, que arma la etiqueta con el porcentaje adentro.
    { comp_id: 16, codigo: 'ENVIAJE', descripcion: 'Falta para llegar al techo', sector: 'Sector Plastico', sector_id: 6,
      proveedor: 'Inyectores SA', um: 'unidad', unidad: 'uni', kg_x_uni: null,
      maximo: 11625, maximo_inventario: 11625, maximo_origen: 'mb_4pct_por_color', stock: 9000,
      consumo: 1543, consumo_uni_mes: 1543, meses: 6, online: 9000, pendiente_oc: 0,
      sugerido: 2625, sugerido_consumo: 8270, es_pliego: false,
      precio: 10, moneda: 'ARS',
      carton_formato: null, pliegos_multiplo: null, codigo_multiplo: null, min_codigo_x_multiplo: null },
  ],
  ocs: [
    { id: 9, numero: 1, proveedor: 'Basconia', rubro: 'Fleje', estado: 'borrador', nota: 'prueba',
      creado_en: '2026-08-29T10:00:00Z',
      total_usd: 500, total_ars: 0,
      items: [ { codigo: 'A1', descripcion: 'Fleje N 13', cantidad: 500, unidad: 'kg', recibido: 0,
                 precio_uni: 1, moneda: 'USD', subtotal: 500 } ] },
    // v1.47.0: dos OC a Maspoli -> la 3 es vigente, la 2 pasa a historicas. v1.46.0: semaforo.
    { id: 12, numero: 3, proveedor: 'Maspoli SRL', rubro: 'Plastico', estado: 'enviada', nota: null,
      creado_en: '2026-08-29T09:00:00Z', total_usd: 0, total_ars: 0,
      items: [ { codigo: 'PC12', descripcion: 'x', cantidad: 100, unidad: 'uni', recibido: 100, subtotal: null, precio_uni: null },
               { codigo: 'PEP7', descripcion: 'x', cantidad: 100, unidad: 'uni', recibido: 40, subtotal: null, precio_uni: null },
               { codigo: 'PEP8', descripcion: 'x', cantidad: 100, unidad: 'uni', recibido: 0, subtotal: null, precio_uni: null } ] },
    { id: 11, numero: 2, proveedor: 'Maspoli SRL', rubro: 'Plastico', estado: 'enviada', nota: null,
      creado_en: '2026-08-28T09:00:00Z', total_usd: 0, total_ars: 0,
      items: [ { codigo: 'PC12', descripcion: 'x', cantidad: 100, unidad: 'uni', recibido: 0, subtotal: null, precio_uni: null } ] },
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
        ? { oc_id: 11, numero: 3, proveedor: 'Altrak', componente: 'ALAMBRE', kg: 40.8 } : null }, error: null };
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

  // CON UN SECTOR ELEGIDO SE VE SOLO ESE, MAS "Todos" [usuario 2026-09-21: "cuando toco un
  // sector me desaparezca el resto de los sectores y ademas haya un boton que diga Todos"].
  const chipsSel = await page.$$eval('#rubros .chip', xs => xs.map(x => x.textContent.trim()));
  ok(chipsSel.join(',') === 'Carton,Todos',
     'con el sector elegido queda ese chip y el boton Todos: ' + chipsSel.join(','));
  // "Todos" suelta el sector: vuelve la botonera entera y, sin sector, la lista se esconde.
  await page.click('#rubroTodos');
  ok(await page.evaluate(() => rubroSel === null), '"Todos" suelta el sector elegido');
  const chipsVuelta = await page.$$eval('#rubros .chip', xs => xs.map(x => x.textContent.trim()));
  ok(chipsVuelta.join(',') === 'Fleje,Carton,Plastico',
     'y vuelven todos los sectores, sin el boton Todos: ' + chipsVuelta.join(','));
  ok(await page.$eval('#zonaLista', x => x.classList.contains('hidden')), 'sin sector no hay lista (regla del 2026-09-04)');

  // El chip elegido se sigue soltando tocandolo, como antes del colapso.
  await page.click('#rubros .chip:has-text("Carton")');
  await page.click('#rubros .chip:has-text("Carton")');   // se suelta: vuelve a esconderse
  ok(await page.$eval('#zonaLista', x => x.classList.contains('hidden')), 'al soltar el sector se esconde de nuevo');
  await page.click('#rubros .chip:has-text("Plastico")');

  // La tabla quedo en lo que se mira para pedir (v1.17.0): salieron Consumo/mes,
  // Sugerido y Precio.
  // v1.44.0: encabezados fijos al bajar (escritorio).
  const stick = await page.$eval('#tbody', tb => getComputedStyle(tb.closest('table').querySelector('thead th')).position);
  ok(stick === 'sticky', 'los encabezados de la tabla quedan fijos (position: ' + stick + ')');
  const heads = await page.evaluate(() => [].map.call(
    document.getElementById('tbody').closest('table').querySelectorAll('thead th'),
    x => x.textContent.replace(/\s+/g, '').trim()));
  ok(heads.join('|') === 'Insumo|Proveedor|Stockactual|Máximo|Pedir|UniMedida',
     'columnas: ' + heads.join(' · '));
  // La plata no se muestra por fila: se mira en la barra y en la OC ya creada.
  ok(!(await page.textContent('#tbody')).includes('US$'), 'no hay precios ni subtotales en la tabla');
  // El "mín N" debajo del stock tambien se saco [usuario: "eso no lo quiero ver"]. Se mira
  // LA CELDA DE STOCK, no toda la tabla: el cartelito del gatillo (v1.21.0) vive en la celda
  // de Pedir y ahi el minimo SI se nombra, que es otra cosa y el usuario no la pidio sacar.
  const stockCells = await page.$$eval('#tbody tr td:nth-child(3)', xs => xs.map(x => x.textContent).join(' | '));
  ok(!stockCells.includes('mín'), 'no aparece el minimo debajo del stock: ' + stockCells.slice(0, 60));

  // filtro Fleje -> 2 filas + chips proveedor (con Plastico elegido hay que soltar primero:
  // la botonera muestra solo el sector activo desde v1.34.0)
  await page.click('#rubroTodos');
  await page.click('#rubros .chip:has-text("Fleje")');
  ok(await page.$$eval('#tbody tr', x => x.length) === 2, 'filtro rubro Fleje: 2 filas');
  const provChips = await page.$$eval('#provs .chip', xs => xs.map(x => x.textContent));
  ok(provChips.join(',') === 'Basconia,Hermac', 'chips proveedor: ' + provChips.join(','));

  // EL SUGERIDO YA VIENE EN "PEDIR" [usuario 2026-09-04]. A1 = 424,9 x 6 - 100 = 2449
  // (lo redondea el servidor): la fila llega con el numero puesto, sin tocar nada.
  ok(await page.$eval('.pedir-in[data-in="1"]', x => x.value) === '2449', 'el sugerido llega cargado en Pedir (2449)');
  ok(await page.$eval('.pedir-in[data-in="2"]', x => x.value) === '300', 'y el del otro fleje tambien (300)');
  const filaA1 = await page.textContent('tr[data-id="1"]');
  // Los carteles debajo de Pedir ("sugerido N · máx − stock") se sacaron en v1.35.0
  // [Thomas 2026-09-28: "elimina todos esos textos"]: el numero ya esta en el campo.
  ok((await page.$$('.sug-calc, .sug-lb, #fechaAyuda, .leyenda')).length === 0,
     'sin carteles de ayuda: ni sugerido debajo de Pedir, ni ayuda de fecha, ni leyenda');
  // [usuario 2026-09-16: "no quiero que me especifique de donde sale el maximo"].
  // La fila ya no muestra el origen (ni "físico" ni "EM"): sigue en el desglose al tocar el Máximo.
  ok(!filaA1.includes('físico'), 'la fila ya no muestra el origen del maximo (físico)');
  ok((await page.$$('tr[data-id="1"] .sub-nota')).length === 0, 'no queda la palabrita gris del origen en la fila');
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
  // "Usar sugeridos" lo repone
  await page.$eval('#btnSug', b => b.click())  /* oculto desde v1.37.0 */;
  ok(await page.$eval('.pedir-in[data-in="2"]', x => x.value) === '300', '"Usar sugeridos" repone lo vaciado');

  // EL PRECIO SE FUE DE LA TABLA [usuario 2026-09-04: "precio se va y subtotal tambien"],
  // pero NO del circuito: sigue valorizando la barra (y mas abajo, el payload de crear_oc).
  ok((await page.$$('.precio-in')).length === 0 && (await page.$$('.mon-btn')).length === 0,
     'no queda campo de precio ni boton de moneda en la tabla');

  // filtro proveedor Basconia y crear OC
  await page.click('#provs .chip:has-text("Basconia")');
  ok(await page.$$eval('#tbody tr', x => x.length) === 1, 'filtro proveedor: 1 fila');
  await page.$eval('#nota', x => { x.value = 'nota test'; });  /* oculto desde v1.37.0 */
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
  ok((await page.$$('.oc-card')).length === 3, 'la OC anulada no se lista');
  // v1.47.0: vigentes = ultima OC por proveedor; la anterior de Maspoli va a historicas.
  const boxes = await page.$$eval('#ocsList details.oc-box', ds => ds.map(d => [...d.querySelectorAll('.num-oc')].map(x => x.textContent.trim())));
  ok(JSON.stringify(boxes) === JSON.stringify([['OC N° 1','OC N° 3'],['OC N° 2']]), 'vigentes/historicas por proveedor: ' + JSON.stringify(boxes));
  ok(!(await page.$eval('#ocsHis', d => d.open)), 'historicas arranca cerrada');
  // v1.46.0: semaforo de recepcion (solo enviada/recibida)
  const sem = await page.$$eval('#ocsList details.oc-box:first-child tr[class^="rc-"]', trs => trs.map(t => t.className));
  ok(JSON.stringify(sem) === JSON.stringify(['rc-ok','rc-par','rc-no']), 'semaforo verde/amarillo/rojo: ' + JSON.stringify(sem));
  ok(!(await page.textContent('#ocsList')).includes('OC N° 7'), 'y no queda rastro de la anulada');
  ok((await page.textContent('#ocsN')).trim() === '(3)', 'el contador del tab no cuenta la anulada');

  // ── CHARCAS: paquetes de charcas_kg_x_paquete kg (del bundle), unidad 'paq' a crear_oc y la
  // OC gemela generica en el mensaje (2026-09-05, ciclos 9-10 de la auditoria) ──
  await page.click('#tabGen');
  await page.click('#rubroTodos');
  await page.click('#rubros .chip:has-text("Plastico")');
  await page.click('#provs .chip:has-text("Resortes Charcas")');
  ok(await page.$$eval('#tbody tr[data-id]', x => x.length) === 1, 'Charcas: 1 fila (EP10)');
  // v1.43.0: la pieza con familia de pedido va bajo el titulo de su familia, con el minimo de la
  // FAMILIA y lo pedido entre todas sus piezas; la fila no repite el minimo.
  const famP = await page.$$eval('#tbody tr.fam-hdr td', xs => xs.map(x => x.textContent.trim()));
  ok(famP.length === 1 && /^Pirolos · 1 pieza · mín\. familia 36\.000 uni · pedido 2\.500 uni$/.test(famP[0]),
     'titulo de familia del plastico: ' + famP.join(' | '));
  ok(await page.$eval('#tbody tr.fam-hdr', x => x.classList.contains('corto')), 'la familia corta (2.500 < 36.000) va en rojo');
  ok(!(await page.$('tr[data-id="13"] .min-uni')), 'la fila con familia no repite el minimo por pieza');
  // v1.38.0: los resortes que Charcas nos VENDE se reciben en unidades y se piden en unidades
  // [Thomas 2026-09-28: "los resortes batidor los pido en unidades"]. El paquete de 10 kg es solo
  // para sus flejes (sector 5).
  ok(await page.$eval('.pedir-in[data-in="13"]', x => x.value) === '2500', 'EP10 de Charcas se pide en unidades (2500)');
  ok((await page.textContent('tr[data-id="13"] td.um-cell')).trim() === 'uni', 'Uni Medida de EP10: uni');
  await page.click('#btnCrear');
  await page.waitForFunction(() => (window.__calls || []).filter(c => c.name === 'crear_oc').length === 2);
  const callCh = await page.evaluate(() => window.__calls.filter(c => c.name === 'crear_oc')[1].args.p);
  ok(callCh.proveedor === 'Resortes Charcas' && callCh.items.length === 1 && callCh.items[0].comp_id === 13
     && callCh.items[0].cantidad === 2500 && callCh.items[0].unidad === 'uni',
     'a crear_oc viajan las UNIDADES: ' + JSON.stringify(callCh.items));
  await page.waitForFunction(() => document.getElementById('status').textContent.includes('gemela'));
  const stCh = (await page.textContent('#status')).replace(/\s+/g, ' ').trim();
  ok(stCh.includes('OC gemela N° 3 a Altrak') && stCh.includes('40,8 kg de ALAMBRE'),
     'el mensaje de la OC gemela sale de la respuesta generica (proveedor + componente + kg): ' + stCh.slice(0, 140));
  // se suelta el proveedor para que el bloque de cartones vea todas sus filas
  await page.click('#tabGen');
  if (await page.evaluate(() => provSel !== null)) await page.click('#provs .chip:has-text("Resortes Charcas")');
  ok(await page.evaluate(() => provSel === null), 'proveedor Charcas soltado');
  // v1.45.0: sin filtro de proveedor, los sectores sin familia van ordenados por proveedor y codigo.
  await page.click('#rubroTodos');
  await page.click('#rubros .chip:has-text("Fleje")');
  const ordF = await page.$$eval('#tbody tr[data-id] td:nth-child(2)', xs => xs.map(x => x.textContent.trim()));
  ok(ordF.length >= 2 && ordF.slice().sort((a, b) => a.localeCompare(b, 'es')).join('|') === ordF.join('|') && !(await page.$('#tbody tr.fam-hdr')),
     'Fleje ordenado por proveedor y sin titulos: ' + ordF.join(' | '));
  await page.click('#rubroTodos');
  await page.click('#rubros .chip:has-text("Plastico")');

  // ── LA FORMULA DE HOY, EN LOS DOS EXTREMOS + EL GATILLO (idea 7242) ───────────────────
  // Tres filas reales de oc_bundle. Si alguien volviera a la formula vieja (consumo x meses),
  // las tres cambian de numero y esto se prende.
  await page.click('#provs .chip:has-text("Inyectores SA")');
  ok(await page.$$eval('#tbody tr[data-id]', x => x.length) === 3, 'Inyectores SA: 3 filas');
  // 1. El techo fisico manda aunque el consumo sea ridiculo al lado: 9.400, no 54.
  ok(await page.$eval('.pedir-in[data-in="14"]', x => x.value) === '9400',
     'el maximo fisico manda sobre el consumo (9.400 y no los 54 de consumo x meses)');
  // 2. Y tambien cuando el techo queda CORTO contra el consumo: se pide lo que entra.
  ok(await page.$eval('.pedir-in[data-in="15"]', x => x.value) === '726',
     'con el techo por debajo del consumo se pide el techo (726 y no 5.228)');
  // 3. El gatillo (v1.26.0): lo que esta abajo del maximo se carga solo, sin punto de pedido.
  ok(await page.$eval('.pedir-in[data-in="16"]', x => x.value) === '2625',
     'abajo del maximo se carga solo lo que falta para el techo (2.625)');
  ok(await page.$eval('tr[data-id="16"] td.bajo-min', x => !!x),
     'y el stock en rojo dice por que (el cartel "hay que pedir" se saco en v1.35.0)');
  // El origen del maximo (incluido Master Bach "MB 4%") ya NO se muestra en la fila
  // [usuario 2026-09-16]; sigue disponible en el desglose al tocar el Máximo.
  ok(!(await page.textContent('tr[data-id="16"]')).includes('MB 4%'),
     'la fila ya no muestra el origen del maximo (MB 4%)');
  await page.click('#provs .chip:has-text("Inyectores SA")');   // se suelta
  ok(await page.evaluate(() => provSel === null), 'proveedor Inyectores soltado');

  // volver a Generar y validar reglas de carton
  await page.click('#tabGen');
  await page.click('#rubroTodos');
  await page.click('#rubros .chip:has-text("Carton")');
  // Los cartones tambien llegan con el sugerido puesto y YA redondeado a su familia:
  // asi era antes con "Usar sugeridos" y asi tiene que estar sin tocar nada.
  ok(await page.$eval('#reglaCarton', x => x.classList.contains('hidden')),
     'el carton llega valido de fabrica (el sugerido entra redondeado a la familia)');
  // Para probar las reglas a mano se parte de la tabla vacia.
  await page.$eval('#btnLimpiar', b => b.click())  /* oculto desde v1.37.0 */;
  ok(await page.$eval('.pedir-in[data-in="3"]', x => x.value) === '', '"Limpiar" deja los campos vacios y no los recarga');
  // 1500 no es multiplo de 1000
  await page.fill('.pedir-in[data-in="3"]', '6');
  await page.$eval('.pedir-in[data-in="3"]', x => x.dispatchEvent(new Event('change')));
  // v1.41.0: el multiplo de familia YA NO avisa ni frena [Thomas 2026-09-28: "Que esto no aparezca"].
  let regla;
  ok(await page.$eval('#reglaCarton', x => x.classList.contains('hidden')),
     'total no multiplo de 12000 NO muestra cartel (v1.41.0)');
  ok(!(await page.$eval('#btnCrear', b => b.disabled)), 'btnCrear sigue habilitado con el multiplo roto');
  // ...pero la tirada de la familia se lee en la fila, debajo de Pedir.
  // v1.42.0: el minimo es POR CARTON (pedido_minimo_uni), no la tirada de la familia.
  const tir = await page.textContent('tr[data-id="3"] .min-uni');
  ok(/mín\. pedido 48 paq 250 \(= 12\.000 uni\)/.test(tir), 'el minimo del carton en la unidad de la O.C. (paq) y en uni: ' + tir.trim());
  // ...y la tabla de cartones va separada por familia, con un renglon de titulo por familia.
  const hdrs = await page.$$eval('tr.fam-hdr td', xs => xs.map(x => x.textContent.trim()));
  ok(hdrs.length >= 3 && hdrs.some(h => /^Formato C · /.test(h)) && hdrs.some(h => /^Formato Huevo · /.test(h)) && !hdrs.some(h => /LOEKE|CHEF/.test(h)),
     'renglones por FORMATO (sin marca) en la tabla: ' + hdrs.join(' | '));
  const primero = await page.$eval('#tbody tr', x => x.className);
  ok(primero === 'fam-hdr', 'la tabla de cartones arranca con el titulo de la primera familia');

  // 11000 + 1000 = 12000 total, ambos multiplos de 1000, minimo 1000 -> valido
  await page.fill('.pedir-in[data-in="3"]', '44');
  await page.$eval('.pedir-in[data-in="3"]', x => x.dispatchEvent(new Event('change')));
  await page.fill('.pedir-in[data-in="4"]', '4');
  await page.$eval('.pedir-in[data-in="4"]', x => x.dispatchEvent(new Event('change')));
  ok(await page.$eval('#reglaCarton', x => x.classList.contains('hidden')), '12000 valido (11000+1000)');
  ok(!(await page.$eval('#btnCrear', b => b.disabled)), 'btnCrear habilitado con carton valido');
  // equivalencia en paquetes visible
  // v1.38.0: el campo va en paquetes (como el remito) y abajo la equivalencia en unidades.
  ok(await page.$eval('.pedir-in[data-in="3"]', x => x.value) === '44', 'el carton se pide en paquetes (44)');
  ok((await page.textContent('tr[data-id="3"] td.um-cell')).trim() === 'paq 250', 'Uni Medida del carton: paq 250');
  // v1.44.2: sin equivalencia debajo del campo [Thomas: "Estas aclaraciones no las quiero"].
  ok(!(await page.$('tr[data-id="3"] .paq-eq')), 'ya no hay "= N uni" debajo de Pedir');

  // El minimo por codigo es FIJO (el paquete), NO escala con el multiplo [usuario
  // 2026-09-03: "el paquete viene a mil, se puede recibir a mil"]. 23.000 + 1.000 = 24.000,
  // dos multiplos, y el de 1.000 sigue estando bien: con el minimo escalado habria dado
  // error pidiendole 2.000, y una familia con muchos codigos no cerraba nunca.
  await page.fill('.pedir-in[data-in="3"]', '92');
  await page.$eval('.pedir-in[data-in="3"]', x => x.dispatchEvent(new Event('change')));
  ok(await page.$eval('#reglaCarton', x => x.classList.contains('hidden')),
     'el minimo por codigo NO escala: 23.000 + 1.000 es valido');
  // Y abajo del minimo si avisa. Se usa el HUEVO, que es el unico donde el minimo
  // (2.000) es mayor que el paso (1.000) y por lo tanto se puede quedar corto siendo
  // multiplo: 24.000 + 1.000 = 25.000 cierra el pliego, pero ese 1.000 no llega al minimo.
  await page.fill('.pedir-in[data-in="9"]', '96');
  await page.$eval('.pedir-in[data-in="9"]', x => x.dispatchEvent(new Event('change')));
  await page.fill('.pedir-in[data-in="10"]', '4');
  await page.$eval('.pedir-in[data-in="10"]', x => x.dispatchEvent(new Event('change')));
  ok(await page.$eval('#reglaCarton', x => x.classList.contains('hidden')),
     'abajo del minimo tampoco hay cartel (v1.41.0); se ve en la fila');
  ok((await page.$eval('tr[data-id="10"] .min-uni', x => x.classList.contains('corto'))),
     'la fila del carton corto se marca en rojo (min. por carton 2.000)');

  // "Usar sugeridos" deja el carton YA VALIDO (usuario 2026-09-03: "sí, redondeá
  // para arriba"). Sugeridos 16.000 + 6.000 = 22.000 -> el total sube al multiplo
  // siguiente (24.000) y lo que falta se reparte de a 1.000 empezando por el que
  // mas pidio: 17.000 + 7.000. Ademas 24.000 son dos multiplos, asi que el minimo
  // por codigo pasa a 2.000 y los dos lo cumplen.
  await page.$eval('#btnLimpiar', b => b.click())  /* oculto desde v1.37.0 */;
  await page.$eval('#btnSug', b => b.click())  /* oculto desde v1.37.0 */;
  // v1.38.0: el campo del carton va en PAQUETES (unidad del remito); las reglas se miran en unidades.
  const val = async id => page.evaluate(i => PEDIDO[i] || 0, id);
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

  // Y si se escribe a mano algo que rompe la regla, NO hay cartel ni boton (v1.41.0):
  // lo que el comprador escribe es su decision, y la tirada se lee en la fila.
  await page.fill('.pedir-in[data-in="3"]', '6');
  await page.$eval('.pedir-in[data-in="3"]', x => x.dispatchEvent(new Event('change')));
  ok(await page.$eval('#reglaCarton', x => x.classList.contains('hidden')), 'a mano se puede romper la regla sin cartel');
  ok(!(await page.$('#btnAjustarCart')), 'ya no existe el boton "Ajustar al múltiplo"');
  ok(!(await page.$eval('#btnCrear', b => b.disabled)), 'y Crear OC sigue habilitado');

  // Bajarla a mano por debajo del mínimo tiene que avisar, y con las palabras del piso
  // (no del múltiplo, que en la bolsa es 1 y siempre da bien).
  await page.fill('.pedir-in[data-in="12"]', '40');
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

  // acciones de OC: el boton WhatsApp abre wa.me con el texto de la OC y la marca enviada
  await page.click('#tabOcs');
  await page.evaluate(() => { window.__wa = null; window.open = (u) => { window.__wa = u; return null; }; });
  ok(await page.$('.oc-acts button.wpp') !== null, 'boton WhatsApp presente');
  ok((await page.$$('.oc-acts button.rec')).length === 0, 'ya no existe "Marcar recibida"');
  await page.click('.oc-acts button.wpp');
  await page.waitForFunction(() => (window.__calls || []).some(c => c.name === 'oc_marcar'));
  const mc = await page.evaluate(() => window.__calls.filter(c => c.name === 'oc_marcar')[0].args);
  ok(mc.p_oc_id === 9 && mc.p_estado === 'enviada', 'WhatsApp marca la OC enviada');
  const wa = await page.evaluate(() => window.__wa || '');
  ok(/wa\.me\/\?text=/.test(wa), 'abre wa.me con texto');
  ok(/Orden%20de%20Compra/.test(wa), 'el texto de WhatsApp lleva la OC');

  // ── UNIDAD DEL REMITO (v1.38.0): misma decision que Recepcion de Insumos ─────────────
  const um = await page.evaluate(() => [
    umRemito({ sector_id: 6, unidad: 'uni', um: 'unidad', kg_x_uni: 0.005, recibe_en_cajas: true, proveedor: 'Trefilados' }),
    umRemito({ sector_id: 9, unidad: 'uni', um: 'unidad', remito_unidad: 'envase', entrega_unidad: 'cajas', entrega_uni_x: 144 }),
    umRemito({ sector_id: 8, unidad: 'uni', um: 'unidad', kg_x_uni: 0.001 }),
    umRemito({ sector_id: 5, unidad: 'kg', um: 'kg', proveedor: 'Basconia' }),
    umRemito({ sector_id: 6, unidad: 'uni', um: 'unidad', recibe_en_cajas: true })   // sin kg_x_uni
  ]);
  ok(um[0].lbl === 'kg' && Math.abs(um[0].k - 0.005) < 1e-9, 'recibe en cajas -> se pide en kg: ' + JSON.stringify(um[0]));
  ok(um[1].lbl === 'cajas 144' && Math.abs(um[1].k - 1 / 144) < 1e-9, 'remito en envase -> cajas de 144: ' + JSON.stringify(um[1]));
  ok(um[2].lbl === 'uni' && um[2].k === 1, 'remaches en unidades');
  ok(um[3].lbl === 'kg' && um[3].k === 1, 'fleje Basconia en kg');
  ok(um[4].lbl === 'uni' && um[4].k === 1, 'sin kg_x_uni no se convierte (no se inventa el peso)');

  // ── v1.39.0: el minimo del proveedor en ROJO y negrita si lo pedido no llega ─────────
  await page.click('#tabGen');
  const corto = await page.evaluate(() => {
    const i = D.insumos.find(x => x.comp_id === 14); i.pedido_minimo_uni = 20000;
    rubroSel = null; provSel = null; render();
    return [notaMinUni(i, 9400, false, 0), notaMinUni(i, 25000, false, 0), notaMinUni(i, 0, false, 0)];
  });
  ok(corto[0].includes('min-uni corto'), 'pide 9.400 con minimo 20.000: rojo y negrita');
  ok(!corto[1].includes('corto'), 'pide 25.000: normal');
  ok(!corto[2].includes('corto'), 'sin pedido no se marca');
  ok(/table\.t\.t-insumos\{width:auto\}/.test(await page.content()), 'la tabla no hereda el 100% de table.t (sin huecos)');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
