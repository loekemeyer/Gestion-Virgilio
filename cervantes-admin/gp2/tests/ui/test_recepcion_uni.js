const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

/* EL REMITO EN UNIDADES SE GUARDA EN UNIDADES (usuario 2026-09-03):
   "en el caso de eduardo pintos, pat bet plast, pettofrezza rafael. cuando voy
   a cargar un remito que me tire por default unidades (kg borralo) y en el
   control que pueda poner los kg y con el kg por uni de cada componente me lo
   pase a uni" + "y en el caso de tornillos suipacha lo mismo (como en todos lo
   de sector remaches)".

   Fija las dos mitades del circuito:
     1. RECEPCION: sin toggle Kg/Uni y cargar_recepcion recibe p_unidad='uni' con
        la cantidad TAL COMO se tipeo (antes se multiplicaba por kg_x_uni y
        bajaba en kg). Un plastico de OTRO proveedor (Trefilados, que si compra
        por kg) tiene que seguir con el toggle a la vista.
     2. CONTROL: se tipean los kg de la balanza y la pantalla los divide por
        kg_x_uni; lo que se guarda son las UNIDADES. Sin kg_x_uni se piden las
        unidades contadas, y las recepciones viejas en kg siguen en kg. */

const BUNDLE = {
  tara: { tara_pallet: '20', tol_ctrl_pct: '5', carton_uni_x_paquete: '250' },
  sectores: [{ id: 6, nombre: 'Sector Plástico' }, { id: 8, nombre: 'Sector Remache' }],
  proveedores: [
    { nombre: 'CC Galvanoquimica', modo_control: 'ninguno', informa_rollos: false, factura_uni: false },
    { nombre: 'Eduardo Pintos', modo_control: 'ninguno', informa_rollos: false, factura_uni: false },
    { nombre: 'Trefilados Industriales', modo_control: 'ninguno', informa_rollos: false, factura_uni: false },
    { nombre: 'Tornillos Suipacha', modo_control: 'ninguno', informa_rollos: false, factura_uni: false },
    { nombre: 'Kollplast', modo_control: 'ninguno', informa_rollos: false, factura_uni: false },
    { nombre: 'Importado', modo_control: 'ninguno', informa_rollos: false, factura_uni: false },
  ],
  recepciones: [], pallets: [], rollos: [],
  insumos: [
    { comp_id: 1, codigo: 'PEP5', descripcion: 'Mango Madera', sector: 'Sector Plástico', sector_id: 6,
      um: 'unidad', proveedor: 'Eduardo Pintos', kg_x_uni: 0.0063, recibe_en_cajas: false,
      stock: 100, ultima: null, oc_pend: null },
    { comp_id: 2, codigo: 'PCP3', descripcion: 'Clavo 505', sector: 'Sector Plástico', sector_id: 6,
      um: 'unidad', proveedor: 'Trefilados Industriales', kg_x_uni: 0.00653, recibe_en_cajas: true,
      stock: 0, ultima: null, oc_pend: null },   // el clavo: viene en cajas y se pesa
    { comp_id: 3, codigo: 'CV18D', descripcion: 'Tornillo Sacafuente p/Niquelar', sector: 'Sector Remache',
      sector_id: 8, um: 'unidad', proveedor: 'Tornillos Suipacha', kg_x_uni: null, recibe_en_cajas: false,
      stock: 0, ultima: null, oc_pend: null },
    // LA PIEZA MANDA SOBRE EL RUBRO (2026-09-23): la plancha de níquel vive en el MISMO sector
    // que los mangos de Eduardo Pintos, que se cuentan, pero ella viene pesada y lo dice con
    // componente.remito_unidad. Sin kg_x_uni a propósito: es el caso real, y por eso su unidad
    // canónica tuvo que pasar a kg (en unidades no había con qué convertir).
    { comp_id: 4, codigo: 'PCP2', descripcion: 'Plancha de Niquel', sector: 'Sector Plástico',
      sector_id: 6, um: 'kg', proveedor: 'CC Galvanoquimica', kg_x_uni: null, recibe_en_cajas: false,
      remito_unidad: 'kg', stock: 0, ultima: null, oc_pend: null },
    // El buje mariposa: era de Pat Bet y desde el 2026-09-23 lo entrega Kollplast, que NO está
    // en PLAST_UNI. Lo que lo hace cargar contado es su propia bandera remito_unidad='uni', no
    // el proveedor: es el mismo mecanismo que la plancha de acá abajo, del otro lado.
    { comp_id: 5, codigo: 'PA8A', descripcion: 'Buje Blanco', sector: 'Sector Plástico', sector_id: 6,
      um: 'unidad', proveedor: 'Kollplast', kg_x_uni: 0.00063, recibe_en_cajas: false,
      remito_unidad: 'uni', stock: 0, ultima: null, oc_pend: null },
    // EL REMITO EN EL ENVASE DE LA PIEZA (2026-09-25): el bastidor del corta queso llega en cajas
    // de 144 y así viene contado el remito. remito_unidad='envase' + entrega_unidad/entrega_uni_x,
    // el MISMO envase con el que la Tablet se lo manda a Lucho.
    { comp_id: 6, codigo: 'C13', descripcion: 'Corta Queso Bastidor c/Cilindro', sector: 'Sector Procesado',
      sector_id: 2, um: 'unidad', proveedor: 'Importado', estado_compra: 'importado',
      kg_x_uni: 4.4 / 144, recibe_en_cajas: false, remito_unidad: 'envase',
      entrega_unidad: 'cajas', entrega_uni_x: 144, stock: 0, ultima: null, oc_pend: null },
  ],
};

/* kg_x_uni y recibe_en_cajas vienen en el BUNDLE, con los insumos (2026-09-11).
   Hasta ese dia la pantalla los pedia aparte con from('componente') y este stub
   tenia que contestar esa segunda consulta; ahora `from` devuelve vacio a
   proposito: si alguien vuelve a meter la consulta suelta, la conversion se
   queda sin factor y los checks de abajo lo cantan. */
const KX = [];

/* El stub reporta cada RPC a Node por un binding (window.__log) en vez de a una
   variable del window: al terminar el remito la pantalla NAVEGA sola al control,
   y con la navegacion se perderia lo anotado. */
const STUB = 'window.supabase={createClient:function(){return{'
  + 'rpc:async function(n,a){ if(window.__log) window.__log(n,a);'
  + ' if(n==="recepcion_bundle") return {data:' + JSON.stringify(BUNDLE) + ',error:null};'
  + ' if(n==="cargar_recepcion") return {data:{ok:true,recepcion_id:99},error:null};'
  + ' if(n==="control_recepcion_bundle") return {data:' + '{}' + ',error:null};'
  + ' return {data:{ok:true},error:null}; },'
  + 'from:function(){ var q={select:function(){return q;},update:function(){return q;},'
  + 'eq:function(){return Promise.resolve({data:[],error:null});},'
  + 'in:function(){return Promise.resolve({data:' + JSON.stringify(KX) + ',error:null});}}; return q; }'
  + '};}};';

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) process.exitCode = 1; };

  const rpcs = [];                        // [nombre, args] de cada RPC, sobrevive a las navegaciones
  await ctx.exposeFunction('__log', (n, a) => { rpcs.push([n, a]); });
  const ultimo = (n) => (rpcs.filter(r => r[0] === n).pop() || [])[1];

  // Regex y no glob: control-remaches.html pide el CDN con la URL larga
  // (@supabase/supabase-js@2/dist/umd/supabase.js) y el * del glob no cruza barras.
  await page.route(/supabase-js@2/, r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/supabase-config.js*', r => r.fulfill({ contentType: 'application/javascript', body: 'self.SB_URL="x";self.SB_ANON="y";self.GP2_SB=function(o){return self.supabase.createClient("x","y",o||{db:{schema:"GP2"}});};' }));   // el stub de supabase-config.js trae la fabrica GP2_SB (2026-09-05)
  await page.route('**/auth-guard.js*', r => r.fulfill({ contentType: 'application/javascript', body: 'window.GP2_AUTH_ON=false;' }));
  await page.route('**/GP2_favicon.png*', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));

  // ── 1) RECEPCION ───────────────────────────────────────────────────────
  await page.goto(ROOT + '/StockFlejes/RecepcionInsumos_GP2.html');
  await page.click('#rubroGrid button:has-text("Plásticos")');
  await page.click('#provGrid button:has-text("Eduardo Pintos")');
  await page.click('#btnContinuar');
  await page.waitForSelector('.item-btn');
  await page.click('.item-btn:has-text("PEP5")');
  await page.waitForSelector('#kgPopup.open');

  ok(await page.locator('#unitRow').isHidden(), 'plásticos de Eduardo Pintos: sin el toggle Kg/Uni');
  ok((await page.locator('#kgValueLabel').innerText()).includes('uni'), 'el campo pide unidades');
  ok(await page.locator('#kgValue').getAttribute('inputmode') === 'numeric', 'teclado numérico entero');

  await page.fill('#kgValue', '100');
  ok(/0,63 kg/.test(await page.locator('#kgConvDisplay').innerText()),
     'muestra al costado los kg que va a marcar la balanza (100 × 0,0063)');
  await page.click('#kgConfirm');
  await page.click('#remitoBtnSlot button, #remitoBtnSlotCart button');
  await page.waitForTimeout(400);

  let carga = ultimo('cargar_recepcion');
  ok(carga && carga.p_unidad === 'uni' && carga.p_cantidad === 100,
     'baja 100 uni, no 0,63 kg (bajó: ' + JSON.stringify(carga && { c: carga.p_cantidad, u: carga.p_unidad }) + ')');

  // Trefilados compra en el MISMO sector pero por kg (su clavo viene en cajas y se
  // pesa): la regla de unidades es por proveedor, no por rubro.
  await page.goto(ROOT + '/StockFlejes/RecepcionInsumos_GP2.html');
  await page.click('#rubroGrid button:has-text("Plásticos")');
  await page.click('#provGrid button:has-text("Trefilados")');
  await page.click('#btnContinuar');
  await page.click('.item-btn:has-text("PCP3")');
  await page.waitForSelector('#kgPopup.open');
  ok(await page.locator('#unitRow').isHidden() &&
     (await page.locator('#kgValueLabel').innerText()).includes('kg'),
     'el clavo de Trefilados sigue en kg: la regla de unidades no se lo lleva puesto');

  // Kollplast: los bujes mariposa pasaron de Pat Bet a Kollplast (2026-09-23,
  // "Remito en uni control en kg"). El proveedor nuevo NO está en PLAST_UNI: lo que lo
  // hace cargar contado es la bandera remito_unidad='uni' de la pieza. Sin ella, la
  // pantalla multiplicaría por kg_x_uni y guardaría kg con el cartel diciendo unidades.
  await page.goto(ROOT + '/StockFlejes/RecepcionInsumos_GP2.html');
  await page.click('#rubroGrid button:has-text("Plásticos")');
  await page.click('#provGrid button:has-text("Kollplast")');
  await page.click('#btnContinuar');
  await page.click('.item-btn:has-text("PA8A")');
  await page.waitForSelector('#kgPopup.open');
  ok(await page.locator('#unitRow').isHidden() &&
     (await page.locator('#kgValueLabel').innerText()).includes('uni'),
     'el buje de Kollplast: remito en unidades, sin toggle Kg/Uni');
  await page.fill('#kgValue', '5000');
  ok(/3,15 kg/.test(await page.locator('#kgConvDisplay').innerText()),
     'y muestra los kg del control (5.000 × 0,00063 = 3,15)');
  await page.click('#kgConfirm');
  await page.click('#remitoBtnSlot button, #remitoBtnSlotCart button');
  await page.waitForTimeout(400);
  carga = ultimo('cargar_recepcion');
  ok(carga && carga.p_unidad === 'uni' && carga.p_cantidad === 5000, 'PA8A baja 5.000 uni');

  // Tornillos Suipacha: sin kg_x_uni y aun así en unidades
  await page.goto(ROOT + '/StockFlejes/RecepcionInsumos_GP2.html');
  await page.click('#rubroGrid button:has-text("Remaches")');
  await page.click('#provGrid button:has-text("Tornillos Suipacha")');
  await page.click('#btnContinuar');
  await page.click('.item-btn:has-text("CV18D")');
  await page.waitForSelector('#kgPopup.open');
  ok(await page.locator('#unitRow').isHidden() &&
     (await page.locator('#kgValueLabel').innerText()).includes('uni'),
     'Tornillos Suipacha sin kg_x_uni: igual en unidades (antes caía a kg y el RPC lo rechazaba)');
  await page.fill('#kgValue', '500');
  await page.click('#kgConfirm');
  await page.click('#remitoBtnSlot button, #remitoBtnSlotCart button');
  await page.waitForTimeout(400);
  carga = ultimo('cargar_recepcion');
  ok(carga && carga.p_unidad === 'uni' && carga.p_cantidad === 500, 'CV18D baja 500 uni');

  // ── 1bis) LA PIEZA MANDA: PCP2 viene pesada aunque su sector se cuente ──
  // [usuario 2026-09-23: "CC galvanoquimica. plancha niquel en el remito viene en kg y se
  // controla en kg"]. Es el mismo Sector Plástico que los mangos de Eduardo Pintos; lo que
  // cambia es componente.remito_unidad.
  await page.goto(ROOT + '/StockFlejes/RecepcionInsumos_GP2.html');
  await page.click('#rubroGrid button:has-text("Plásticos")');
  await page.click('#provGrid button:has-text("CC Galvanoquimica")');
  await page.click('#btnContinuar');
  await page.click('.item-btn:has-text("PCP2")');
  await page.waitForSelector('#kgPopup.open');
  ok(await page.locator('#unitRow').isHidden(), 'PCP2: sin toggle Kg/Uni (la unidad no se elige)');
  ok((await page.locator('#kgValueLabel').innerText()).includes('kg'),
     'PCP2 pide kg: ' + (await page.locator('#kgValueLabel').innerText()));
  ok(await page.locator('#kgValue').getAttribute('inputmode') === 'decimal',
     'y con teclado decimal, que es lo que marca una balanza');
  await page.fill('#kgValue', '12,5');
  await page.click('#kgConfirm');
  await page.click('#remitoBtnSlot button, #remitoBtnSlotCart button');
  await page.waitForTimeout(400);
  carga = ultimo('cargar_recepcion');
  ok(carga && carga.p_unidad === 'kg' && carga.p_cantidad === 12.5,
     'PCP2 baja 12,5 kg (bajó: ' + JSON.stringify(carga && { c: carga.p_cantidad, u: carga.p_unidad }) + ')');

  // ── 1ter) EL REMITO EN CAJAS: C13 llega en cajas de 144 [usuario 2026-09-25] ──
  await page.goto(ROOT + '/StockFlejes/RecepcionInsumos_GP2.html');
  await page.click('#rubroGrid button:has-text("Importados")');
  await page.click('#btnContinuar');
  await page.waitForSelector('.item-btn:has-text("C13")');
  await page.click('.item-btn:has-text("C13")');
  await page.waitForSelector('#kgPopup.open');
  ok(await page.locator('#unitRow').isHidden(), 'C13: sin toggle Kg/Uni');
  ok(/cajas/.test(await page.locator('#kgValueLabel').innerText()),
     'C13 pide cajas: ' + (await page.locator('#kgValueLabel').innerText()));
  ok(await page.locator('#kgValue').getAttribute('inputmode') === 'numeric', 'cajas con teclado entero');
  await page.fill('#kgValue', '3');
  ok(/432 unidades/.test(await page.locator('#kgConvDisplay').innerText()),
     'muestra las unidades: 3 cajas = 432 (' + (await page.locator('#kgConvDisplay').innerText()) + ')');
  await page.click('#kgConfirm');
  await page.click('#remitoBtnSlot button, #remitoBtnSlotCart button');
  await page.waitForTimeout(400);
  carga = ultimo('cargar_recepcion');
  ok(carga && carga.p_unidad === 'uni' && carga.p_cantidad === 432,
     'C13 baja 432 uni, no 3 (bajó: ' + JSON.stringify(carga && { c: carga.p_cantidad, u: carga.p_unidad }) + ')');

  // ── 2) CONTROL ─────────────────────────────────────────────────────────
  const RECS = {
    sector: 'Sector Remache', sector_id: 8,
    // LA TOLERANCIA DEL CONTROL VIENE DE LA BASE (parametro.tol_ctrl_pct, 5 %) y ya no es un
    // número escrito en el JS [usuario 2026-09-23: "todo control no puede exceder el 5% de
    // diferencia"]. Antes esta pantalla toleraba un 10 % propio.
    tol_pct: 5,
    recepciones: [
      { id: 1, fecha: '2026-09-03T12:00:00Z', proveedor: 'Bella Vista', remito: 'R1', codigo: 'CV1',
        descripcion: 'Remache Espiral p/Niquelar', cantidad: 10000, cantidad_declarada: 10000,
        unidad: 'uni', kg_x_uni: 0.00035, controlado: false, movimiento_id: 11 },
      { id: 2, fecha: '2026-09-03T12:00:00Z', proveedor: 'Tornillos Suipacha', remito: 'R2', codigo: 'CV18D',
        descripcion: 'Tornillo Sacafuente p/Niquelar', cantidad: 500, cantidad_declarada: 500,
        unidad: 'uni', kg_x_uni: null, controlado: false, movimiento_id: 12 },
      { id: 3, fecha: '2026-09-02T12:00:00Z', proveedor: 'Bella Vista', remito: 'R0', codigo: 'V5',
        descripcion: 'Rem. afila niq.', cantidad: 3.5, cantidad_declarada: 3.5,
        unidad: 'kg', kg_x_uni: 0.00388, controlado: false, movimiento_id: 13 },
      // Dos piezas iguales para medir la tolerancia: se cuentan (sin kg_x_uni no hay balanza que
      // convertir), así el número que se tipea es directamente el que se compara.
      { id: 4, fecha: '2026-09-03T12:00:00Z', proveedor: 'Tornillos Suipacha', remito: 'R4', codigo: 'TOL4',
        descripcion: 'Tolerancia 4 por ciento', cantidad: 1000, cantidad_declarada: 1000,
        unidad: 'uni', kg_x_uni: null, controlado: false, movimiento_id: 14 },
      { id: 5, fecha: '2026-09-03T12:00:00Z', proveedor: 'Tornillos Suipacha', remito: 'R5', codigo: 'TOL6',
        descripcion: 'Tolerancia 6 por ciento', cantidad: 1000, cantidad_declarada: 1000,
        unidad: 'uni', kg_x_uni: null, controlado: false, movimiento_id: 15 },
    ],
  };
  const STUB2 = 'window.supabase={createClient:function(){return{'
    + 'rpc:async function(n,a){ if(window.__log) window.__log(n,a);'
    + ' if(n==="control_recepcion_bundle") return {data:' + JSON.stringify(RECS) + ',error:null};'
    + ' return {data:{kg:(a&&a.p_kg)},error:null}; },'
    + 'from:function(){ var q={update:function(){return q;},eq:function(){return Promise.resolve({error:null});}}; return q; }'
    + '};}};';
  await page.route(/supabase-js@2/, r => r.fulfill({ contentType: 'application/javascript', body: STUB2 }));
  await page.goto(ROOT + '/StockFlejes/control-remaches.html?sector=8');
  await page.waitForSelector('.item-btn');

  const cards = await page.$$eval('.item-btn', bs => bs.map(b => b.innerText.replace(/\n/g, ' | ')));
  ok(cards.some(c => /CV1.*Declarado: 10\.000 uni/.test(c)), 'la tarjeta declara en uni: ' + cards[0]);
  ok(cards.some(c => /V5.*Declarado: 3,5 kg/.test(c)), 'la recepción vieja en kg sigue en kg');

  // CV1: se pesan 3,5 kg -> 3,5 / 0,00035 = 10.000 uni
  await page.click('.item-btn:has-text("CV1")');
  await page.waitForSelector('#ovCtrl.open');
  ok(/[Kk]g/.test(await page.locator('#lblKg').innerText()), 'pide los kg de la balanza');
  await page.fill('#inKg', '3,5');
  await page.waitForTimeout(120);
  const conv = await page.locator('#lblUni').innerText();
  ok(/10\.000/.test(conv), 'convierte en vivo: 3,5 kg = 10.000 uni (' + conv + ')');
  ok(/se guardan estas unidades/.test(conv), 'y avisa que ESAS unidades son las que se guardan');
  // El kg por unidad tiene 6 decimales: con un formateador de 3 decia "1 uni = 0 kg"
  // y parecia que el dato faltaba (la trampa de CONOCIMIENTO_GP2.md 4a).
  ok(/0,00035/.test(conv), 'el kg por unidad se muestra con sus decimales, no redondeado a 0');
  ok(/Coincide/.test(await page.locator('#lblDiff').innerText()), 'compara contra lo declarado EN UNIDADES');
  await page.click('#btnConfirm');
  await page.waitForTimeout(200);
  let ctl = ultimo('controlar_recepcion_kg');
  ok(ctl && ctl.p_kg === 10000, 'guarda 10.000 uni, no 3,5 (guardó: ' + (ctl && ctl.p_kg) + ')');

  // CV18D sin kg_x_uni: no hay conversión posible, se cuentan unidades
  await page.click('.item-btn:has-text("CV18D")');
  await page.waitForSelector('#ovCtrl.open');
  ok(/[Uu]nidades/.test(await page.locator('#lblKg').innerText()),
     'sin kg por unidad pide contar unidades: ' + (await page.locator('#lblKg').innerText()));
  ok(await page.locator('#inKg').getAttribute('inputmode') === 'numeric', 'y con teclado entero');
  await page.click('#btnCancel');

  // V5 (recepción vieja en kg): sigue siendo kg puro, sin línea de conversión
  await page.click('.item-btn:has-text("V5")');
  await page.waitForSelector('#ovCtrl.open');
  await page.fill('#inKg', '3,5');
  await page.waitForTimeout(120);
  // La recepcion en kg SI muestra el equivalente en unidades (es informativo,
  // de la otra mitad del cambio), pero lo que se guarda son los kg.
  // 3,5 kg / 0,00388 = 902 unidades. Se muestran, pero lo que se guarda son los kg.
  ok(/902/.test(await page.locator('#lblUni').innerText()),
     'la recepción en kg muestra el equivalente en unidades (' + (await page.locator('#lblUni').innerText()) + ')');
  await page.click('#btnConfirm');
  await page.waitForTimeout(200);
  ctl = ultimo('controlar_recepcion_kg');
  ok(ctl && ctl.p_kg === 3.5, 'la recepción en kg se sigue guardando en kg');

  // ── 3) LA TOLERANCIA DEL CONTROL: 5 %, Y SALE DE LA BASE ───────────────
  // [usuario 2026-09-23: "acordate de la regla de que todo control no puede exceder el 5% de
  // diferencia"]. Hasta hoy acá había un 10 % escrito a mano: 1.060 contra 1.000 declaradas
  // pasaba sin decir nada.
  const carteles = [];
  page.on('dialog', d => { carteles.push(d.message()); d.accept(); });

  await page.click('.item-btn:has-text("TOL4")');
  await page.waitForSelector('#ovCtrl.open');
  await page.fill('#inKg', '1040');                 // 4 % : adentro de la tolerancia
  await page.click('#btnConfirm');
  await page.waitForTimeout(250);
  ok(carteles.length === 0, 'una diferencia del 4 % no molesta a nadie (carteles: ' + carteles.length + ')');
  ok((ultimo('controlar_recepcion_kg') || {}).p_kg === 1040, 'y guarda las 1.040 contadas');

  await page.click('.item-btn:has-text("TOL6")');
  await page.waitForSelector('#ovCtrl.open');
  await page.fill('#inKg', '1060');                 // 6 % : afuera
  await page.click('#btnConfirm');
  await page.waitForTimeout(250);
  ok(carteles.length === 1 && /6,0%|6\.0%/.test(carteles[0]),
     'el 6 % avisa antes de guardar: ' + (carteles[0] || '(sin cartel)'));
  ok(/tolerancia 5/i.test(carteles[0] || ''), 'y el cartel dice cuál es la tolerancia');

  // Que el 5 salga de la BASE y no de un número escrito en el JS: con la misma diferencia del
  // 6 % pero tol_pct = 10, no tiene que aparecer ningún cartel.
  const RECS10 = JSON.parse(JSON.stringify(RECS)); RECS10.tol_pct = 10;
  await page.route(/supabase-js@2/, r => r.fulfill({ contentType: 'application/javascript',
    body: STUB2.replace(JSON.stringify(RECS), JSON.stringify(RECS10)) }));
  await page.goto(ROOT + '/StockFlejes/control-remaches.html?sector=8');
  await page.waitForSelector('.item-btn');
  await page.click('.item-btn:has-text("TOL6")');
  await page.waitForSelector('#ovCtrl.open');
  await page.fill('#inKg', '1060');
  await page.click('#btnConfirm');
  await page.waitForTimeout(250);
  ok(carteles.length === 1, 'la tolerancia sale del bundle: con 10 % el mismo 6 % pasa callado');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
