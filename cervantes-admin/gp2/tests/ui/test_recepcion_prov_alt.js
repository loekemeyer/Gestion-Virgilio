const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

/* UN INSUMO PUEDE TENER MAS DE UN PROVEEDOR (2026-09-17, usuario: "dentro de cajas,
   ademas de corrugadora del plata, tenes que agregar al proveedor Recicor. Entrega las
   mismas cajas que corrugadora. El control de remito es igual al de corrugadora").

   componente.proveedor es UN texto: el principal, el que manda en la OC y en el costo.
   Los que TAMBIEN entregan la misma pieza vienen en insumo.proveedores_alt (tabla
   GP2.componente_proveedor_alt). Lo que este test fija:

     1. Los chips de proveedor salen de principal + alternativos, con el conteo de cada uno.
     2. La misma caja aparece bajo los DOS chips (no se duplica el componente, asi que el
        stock sigue siendo uno solo) y una caja sin alternativo NO aparece bajo el alternativo.
     3. Al recibir eligiendo el alternativo, cargar_recepcion baja con p_proveedor='Recicor'
        (por eso Recicor tiene que existir en proveedor_insumo: recepcion_insumo.proveedor
        tiene FK contra esa tabla).

   Si alguien vuelve a escribir i.proveedor===provSel en vez de esDelProv(), el chip del
   proveedor alternativo queda en 0 items y este test lo canta. */

function caja(id, cod, desc, alt) {
  return { comp_id: id, codigo: cod, descripcion: desc, sector: 'Sector Caja', sector_id: 11,
           um: 'unidad', proveedor: 'Corrugadora del Plata', proveedores_alt: alt || [],
           kg_x_uni: null, recibe_en_cajas: false, stock: 0, ultima: null, oc_pend: null };
}

const BUNDLE = {
  tara: { tara_pallet: '20', tol_ctrl_pct: '5', carton_uni_x_paquete: '250' },
  sectores: [{ id: 11, nombre: 'Sector Caja' }],
  proveedores: [
    { nombre: 'Corrugadora del Plata', modo_control: 'ninguno', informa_rollos: false, factura_uni: false },
    { nombre: 'Recicor', modo_control: 'ninguno', informa_rollos: false, factura_uni: false },
  ],
  recepciones: [], pallets: [], rollos: [],
  insumos: [
    caja(1, 'A1', 'Caja N°1', ['Recicor']),
    caja(2, 'A8', 'Caja N°2', ['Recicor']),
    caja(3, 'A9', 'Caja N°22', []),   // esta solo la entrega Corrugadora
  ],
};

const STUB = 'window.supabase={createClient:function(){return{'
  + 'rpc:async function(n,a){ if(window.__log) window.__log(n,a);'
  + ' if(n==="recepcion_bundle") return {data:' + JSON.stringify(BUNDLE) + ',error:null};'
  + ' if(n==="cargar_recepcion") return {data:{ok:true,recepcion_id:99},error:null};'
  + ' if(n==="control_recepcion_bundle") return {data:{},error:null};'
  + ' return {data:{ok:true},error:null}; },'
  + 'from:function(){ var q={select:function(){return q;},update:function(){return q;},'
  + 'eq:function(){return Promise.resolve({data:[],error:null});},'
  + 'in:function(){return Promise.resolve({data:[],error:null});}}; return q; }'
  + '};}};';

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) process.exitCode = 1; };

  const rpcs = [];
  await ctx.exposeFunction('__log', (n, a) => { rpcs.push([n, a]); });
  const ultimo = (n) => (rpcs.filter(r => r[0] === n).pop() || [])[1];

  await page.route(/supabase-js@2/, r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/supabase-config.js*', r => r.fulfill({ contentType: 'application/javascript', body: 'self.SB_URL="x";self.SB_ANON="y";self.GP2_SB=function(o){return self.supabase.createClient("x","y",o||{db:{schema:"GP2"}});};' }));
  await page.route('**/auth-guard.js*', r => r.fulfill({ contentType: 'application/javascript', body: 'window.GP2_AUTH_ON=false;' }));
  await page.route('**/GP2_favicon.png*', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));

  // ── 1) los dos chips, con su conteo ───────────────────────────────────
  await page.goto(ROOT + '/StockFlejes/RecepcionInsumos_GP2.html');
  await page.click('#rubroGrid button:has-text("Cajas")');
  await page.waitForSelector('#provGrid .prov-btn');
  const chips = (await page.locator('#provGrid .prov-btn').allInnerTexts()).map(t => t.replace(/\s+/g, ' ').trim());
  ok(chips.length === 2, 'Cajas tiene 2 proveedores (salió: ' + JSON.stringify(chips) + ')');
  ok(chips.some(t => /^Corrugadora del Plata \(3\)$/.test(t)), 'Corrugadora del Plata con sus 3 cajas');
  ok(chips.some(t => /^Recicor \(2\)$/.test(t)), 'Recicor aparece con las 2 cajas que también entrega');

  // ── 2) la misma caja aparece bajo Recicor, y la que no es suya no ─────
  await page.click('#provGrid button:has-text("Recicor")');
  await page.click('#btnContinuar');
  await page.waitForSelector('.item-btn');
  let items = await page.locator('.item-btn').allInnerTexts();
  ok(items.length === 2, 'Recicor muestra 2 items (salió ' + items.length + ')');
  ok(items.join(' ').includes('A1') && items.join(' ').includes('A8'), 'son las mismas cajas A1 y A8');
  ok(!items.join(' ').includes('A9'), 'la caja que solo entrega Corrugadora (A9) no se cuela en Recicor');

  // ── 3) el remito baja con el proveedor elegido ────────────────────────
  await page.click('.item-btn:has-text("A1")');
  await page.waitForSelector('#kgPopup.open');
  await page.fill('#kgValue', '50');
  await page.click('#kgConfirm');
  await page.click('#remitoBtnSlot button, #remitoBtnSlotCart button');
  await page.waitForTimeout(400);
  const carga = ultimo('cargar_recepcion');
  ok(carga && carga.p_proveedor === 'Recicor' && carga.p_comp_id === 1,
     'cargar_recepcion baja con p_proveedor="Recicor" (bajó: ' + JSON.stringify(carga && { p: carga.p_proveedor, c: carga.p_comp_id }) + ')');

  // ── 4) Corrugadora sigue viendo las 3 ─────────────────────────────────
  await page.goto(ROOT + '/StockFlejes/RecepcionInsumos_GP2.html');
  await page.click('#rubroGrid button:has-text("Cajas")');
  await page.click('#provGrid button:has-text("Corrugadora")');
  await page.click('#btnContinuar');
  await page.waitForSelector('.item-btn');
  items = await page.locator('.item-btn').allInnerTexts();
  ok(items.length === 3, 'Corrugadora sigue con sus 3 cajas (salió ' + items.length + ')');

  await browser.close();
})();
