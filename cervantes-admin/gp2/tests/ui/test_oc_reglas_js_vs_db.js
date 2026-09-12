const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

/* LAS REGLAS DE OC TIENEN QUE DECIR LO MISMO EN LOS DOS LADOS.
   Hasta el 2026-09-11 vivian SOLO en Compras/OC_GP2.html: `crear_oc` tiene EXECUTE para
   anon y aceptaba cualquier cantidad, asi que el unico control estaba en el navegador.
   Ahora la base tiene "GP2"._oc_validar_carton(p_items) y
   "GP2"._oc_validar_minimo_proveedor(p_items), ports LITERALES de famKey / famBase / reglaDe /
   gruposCarton / validarCarton y de validarMinimoProveedor, y crear_oc las llama a las dos.

   Este test corre los MISMOS 17 casos contra el JS de la pantalla y compara, mensaje por
   mensaje, con lo que devolvieron las funciones de la base. Los ESPERADOS de abajo NO son lo
   que yo creo que deberia pasar: son la salida REAL de
     select "GP2"._oc_validar_carton('[{"comp_id":...,"cantidad":...}]');
     select "GP2"._oc_validar_minimo_proveedor('[...]');
   corrida el 2026-09-11 contra el proyecto hrxfctzncixxqmpfhskv. Si alguien toca una de las
   dos implementaciones y no la otra, este test se prende.

   Los comp_id y los atributos de los items son los REALES de la base (por eso los mismos
   casos sirven de los dos lados):
     719 O2D / 712 S2A / 767 CART715 -> formato C, CHEF, sin categoria
     894 T3A                          -> formato C, CHEF, categoria Sacacorchos (mezcla_libre = COMODIN)
     288 A1B                          -> formato Bolsa, LOEKE, pedido_minimo 20.000
     306 Pliego Ad 500 / 564 Pliego 506 -> es_pliego, LOEKE (se piden de a 100, parametro
                                           pliego_uni_x_paquete; NO heredan el 12.000 del formato C)
     743 ABS GP 22 / 745 Nylon Virgen -> sector 14, Indarnyl (pedido minimo 400 kg)
     748 PE Baja 7147                 -> sector 14, Beta Plasticos (pedido minimo 25 kg) */

function carton(comp_id, codigo, descripcion, formato, marca, categoria, mezcla_libre, es_pliego,
                pm, cm, mc, pmin) {
  return {
    comp_id, codigo, descripcion, sector: 'Sector Carton', sector_id: 10,
    proveedor: 'Cartonero', um: 'uni', unidad: 'uni', kg_x_uni: null,
    consumo: 1000, meses: 6, online: 0, pendiente_oc: 0, sugerido: 0,
    precio: 1, moneda: 'ARS',
    carton_formato: formato, carton_categoria: categoria, marca,
    mezcla_libre, es_pliego,
    pliegos_multiplo: pm, codigo_multiplo: cm, min_codigo_x_multiplo: mc, pedido_minimo: pmin,
  };
}

const BUNDLE = {
  paq: 250,
  pliego_uni_x_paquete: 100,
  charcas_kg_x_paquete: 10,
  insumos: [
    carton(719, 'O2D',     'Cartón 818', 'C', 'CHEF',  null,          false, false, 12000, 1000, 1000, null),
    carton(712, 'S2A',     'Cartón 909', 'C', 'CHEF',  null,          false, false, 12000, 1000, 1000, null),
    carton(767, 'CART715', 'Cartón 715', 'C', 'CHEF',  null,          false, false, 12000, 1000, 1000, null),
    carton(894, 'T3A',     'Cartón 735', 'C', 'CHEF',  'Sacacorchos', true,  false, 12000, 1000, 1000, null),
    carton(288, 'A1B',     'Cartón 031', 'Bolsa', 'LOEKE', null,      false, false, 1, 1, 1, 20000),
    carton(306, 'Pliego Ad 500', 'Adhesivado',    'C', 'LOEKE', null, false, true,  12000, 1000, 1000, null),
    carton(564, 'Pliego 506',    'Sin adhesivar', 'C', 'LOEKE', null, false, true,  12000, 1000, 1000, null),
  ],
  ocs: [], parametros: {},
  /* Materia prima plastica (sector 14, todo en kg) para la OTRA regla que bloquea:
     el pedido minimo EN KG del proveedor (proveedor_insumo.pedido_minimo_kg). */
  proveedores: [
    { nombre: 'Indarnyl',       pedido_minimo_kg: 400 },
    { nombre: 'Beta Plásticos', pedido_minimo_kg: 25 },
  ],
};

function mp(comp_id, codigo, descripcion, proveedor) {
  return {
    comp_id, codigo, descripcion, sector: 'Sector Materia Prima Plástica', sector_id: 14,
    proveedor, um: 'kg', unidad: 'kg', kg_x_uni: null,
    consumo: 100, meses: 6, online: 0, pendiente_oc: 0, sugerido: 0, precio: 1, moneda: 'ARS',
    carton_formato: null, carton_categoria: null, marca: null, mezcla_libre: false,
    es_pliego: false, pliegos_multiplo: null, codigo_multiplo: null,
    min_codigo_x_multiplo: null, pedido_minimo: null,
  };
}
BUNDLE.insumos.push(mp(743, '2455', 'ABS GP 22 Natural', 'Indarnyl'));
BUNDLE.insumos.push(mp(745, '2475', 'Nylon Virgen', 'Indarnyl'));
BUNDLE.insumos.push(mp(748, '2435', 'PE Polietileno Baja 7147', 'Beta Plásticos'));

/* Cada caso: [nombre, {comp_id: cantidad}, errores que devolvio la BASE]. */
const CASOS = [
  ['múltiplo justo: 6.000 + 6.000 = 12.000', { 719: 6000, 712: 6000 }, []],
  ['el total no llega al múltiplo de familia', { 719: 6000, 712: 5000 },
    ['Formato C CHEF: el total (11.000) debe ser múltiplo de 12.000.']],
  ['dos códigos fuera del múltiplo de 1.000', { 719: 6500, 712: 5500 },
    ['Formato C CHEF · O2D: 6.500 no es múltiplo de 1.000.',
     'Formato C CHEF · S2A: 5.500 no es múltiplo de 1.000.']],
  ['el múltiplo por código se chequea ANTES que el mínimo', { 719: 11500, 712: 500 },
    ['Formato C CHEF · O2D: 11.500 no es múltiplo de 1.000.',
     'Formato C CHEF · S2A: 500 no es múltiplo de 1.000.']],
  ['el comodín completa la familia: 10.000 + 2.000', { 719: 10000, 894: 2000 }, []],
  ['el comodín solo, con su propio múltiplo', { 894: 12000 }, []],
  ['el comodín solo y corto: no tiene a quién sumarse', { 894: 2000 },
    ['Formato C CHEF · Sacacorchos: el total (2.000) debe ser múltiplo de 12.000.']],
  ['la bolsa justo en su pedido mínimo', { 288: 20000 }, []],
  ['la bolsa por debajo del pedido mínimo', { 288: 19000 },
    ['Formato Bolsa LOEKE: el pedido mínimo es 20.000 y hay 19.000.']],
  ['el pliego se pide de a 100', { 306: 100 }, []],
  ['el pliego suelto no vale', { 306: 150 },
    ['Pliegos LOEKE: el total (150) debe ser múltiplo de 100.']],
  ['dos pliegos de la misma marca son UNA familia', { 306: 100, 564: 100 }, []],
  ['una familia bien y otra corta: sólo se queja de la corta', { 719: 12000, 288: 19000 },
    ['Formato Bolsa LOEKE: el pedido mínimo es 20.000 y hay 19.000.']],
];

/* La otra regla que BLOQUEA: el pedido mínimo en kg del proveedor de materia prima. Mismo
   criterio de esperados: es la salida real de "GP2"._oc_validar_minimo_proveedor(...). */
const CASOS_MP = [
  ['Indarnyl 200 + 150 = 350, con mínimo 400', { 743: 200, 745: 150 },
    ['Indarnyl: el pedido mínimo es 400 kg y hay 350 kg (faltan 50).']],
  ['Indarnyl justo en 400', { 743: 200, 745: 200 }, []],
  ['dos proveedores, los dos cortos', { 743: 10, 748: 5 },
    ['Beta Plásticos: el pedido mínimo es 25 kg y hay 5 kg (faltan 20).',
     'Indarnyl: el pedido mínimo es 400 kg y hay 10 kg (faltan 390).']],
  ['un pedido sin materia prima no mira esta regla', { 719: 12000 }, []],
];

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) process.exitCode = 1; };

  const STUB = 'window.supabase={createClient:function(){return{'
    + 'rpc:async function(n){ if(n==="oc_bundle") return {data:' + JSON.stringify(BUNDLE) + ',error:null};'
    + ' return {data:{ok:true},error:null}; },'
    + 'from:function(){ var q={select:function(){return q;},eq:function(){return Promise.resolve({data:[],error:null});},'
    + 'in:function(){return Promise.resolve({data:[],error:null});}}; return q; }'
    + '};}};';
  await page.route(/supabase-js@2/, r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/auth-guard.js*', r => r.fulfill({ contentType: 'application/javascript', body: 'window.GP2_AUTH_ON=false;' }));
  await page.route('**/GP2_favicon.png*', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));

  await page.goto(ROOT + '/Compras/OC_GP2.html');
  await page.waitForFunction(() => typeof window.validarCarton === 'function' && window.D && (window.D.insumos || []).length > 0);

  ok(await page.evaluate(() => typeof window.validarCarton === 'function'),
     'la pantalla sigue exponiendo validarCarton (si se renombra, este test deja de servir)');

  for (const [nombre, pedido, esperado] of CASOS) {
    const got = await page.evaluate(p => {
      const items = Object.keys(p).map(k => {
        const it = window.D.insumos.filter(i => String(i.comp_id) === String(k))[0];
        return { comp_id: it.comp_id, cantidad: p[k], it };
      });
      return window.validarCarton(items);
    }, pedido);
    const a = JSON.stringify(got.slice().sort());
    const b = JSON.stringify(esperado.slice().sort());
    ok(a === b, nombre + (a === b ? '' : '\n     JS : ' + a + '\n     BASE: ' + b));
  }

  for (const [nombre, pedido, esperado] of CASOS_MP) {
    const got = await page.evaluate(p => {
      const items = Object.keys(p).map(k => {
        const it = window.D.insumos.filter(i => String(i.comp_id) === String(k))[0];
        return { comp_id: it.comp_id, cantidad: p[k], it };
      });
      return window.validarMinimoProveedor(items);
    }, pedido);
    const a = JSON.stringify(got.slice().sort());
    const b = JSON.stringify(esperado.slice().sort());
    ok(a === b, nombre + (a === b ? '' : '\n     JS : ' + a + '\n     BASE: ' + b));
  }

  console.log('TODO OK');
  await browser.close();
})();
