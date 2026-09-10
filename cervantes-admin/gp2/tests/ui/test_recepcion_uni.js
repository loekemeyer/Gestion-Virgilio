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
  tara: { tara_pallet: '20', tol_ctrl_peso_pct: '5', carton_uni_x_paquete: '250' },
  sectores: [{ id: 6, nombre: 'Sector Plástico' }, { id: 8, nombre: 'Sector Remache' }],
  proveedores: [
    { nombre: 'Eduardo Pintos', modo_control: 'ninguno', informa_rollos: false, factura_uni: false },
    { nombre: 'Trefilados Industriales', modo_control: 'ninguno', informa_rollos: false, factura_uni: false },
    { nombre: 'Tornillos Suipacha', modo_control: 'ninguno', informa_rollos: false, factura_uni: false },
  ],
  recepciones: [], pallets: [], rollos: [],
  insumos: [
    { comp_id: 1, codigo: 'PEP5', descripcion: 'Mango Madera', sector: 'Sector Plástico', sector_id: 6,
      um: 'unidad', proveedor: 'Eduardo Pintos', kg_x_uni: 0.0063, stock: 100, ultima: null, oc_pend: null },
    { comp_id: 2, codigo: 'PCP3', descripcion: 'Clavo 505', sector: 'Sector Plástico', sector_id: 6,
      um: 'unidad', proveedor: 'Trefilados Industriales', kg_x_uni: 0.00653, stock: 0, ultima: null, oc_pend: null },
    { comp_id: 3, codigo: 'CV18D', descripcion: 'Tornillo Sacafuente p/Niquelar', sector: 'Sector Remache',
      sector_id: 8, um: 'unidad', proveedor: 'Tornillos Suipacha', kg_x_uni: null, stock: 0, ultima: null, oc_pend: null },
  ],
};

/* Los kg_x_uni NO vienen en el bundle: la pantalla los pide aparte con
   from('componente').select('id,kg_x_uni').in('sector_id',[...]). Sin esa
   respuesta el stub no probaria nada (la conversion no se intentaria siquiera). */
const KX = [{ id: 1, kg_x_uni: 0.0063, recibe_en_cajas: false },
            { id: 2, kg_x_uni: 0.00653, recibe_en_cajas: true },   // el clavo: viene en cajas y se pesa
            { id: 3, kg_x_uni: null, recibe_en_cajas: false }];

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

  // ── 2) CONTROL ─────────────────────────────────────────────────────────
  const RECS = {
    sector: 'Sector Remache', sector_id: 8,
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

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
