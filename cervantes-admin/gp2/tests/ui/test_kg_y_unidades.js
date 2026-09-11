const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

/* EL INSUMO QUE VIENE EN CAJAS Y SE PESA (componente.recibe_en_cajas).
   Un dato del componente, dos consecuencias en pantalla:
     1. RECEPCION: se carga siempre en kg y no aparece el toggle Kg/Unidades
        [usuario 2026-09-03: "que tire por default kg y borra unidades en el
        caso de Trefilados Industriales Clavo 505"].
     2. CONTROL POR PESO: cajas x kg por caja
   y, aparte, LA OTRA MITAD DE LA MISMA MONEDA: los insumos que se reciben
   CONTANDO unidades (bombillas, remaches) se cargan sin toggle en uni, y su
   control —que es por peso— muestra el pasaje a unidades con el kg_x_uni
   [usuario 2026-09-03: "en recepcion de bombillas que tire por default unidades
   (que no aparezca kg) y que en el control ponga kg y me haga el pasaje a
   unidades con el kg por uni"]. [usuario 2026-09-03: "en el caso del
   control de este componente que me deje poner cant de cajas y kg por caja"].
   El Clavo 505 viene en cajas y se pesa: en su control aparecen los dos campos
   y la multiplicacion completa los kg controlados. El resto de los insumos del
   mismo sector siguen con un solo campo de kg — el flag es del componente
   (recibe_en_cajas), no de la pantalla. */
const BUNDLE = {
  sector: 'Sector Plástico', sector_id: 6,
  recepciones: [
    { id: 1, fecha: '2026-09-03', componente_id: 256, codigo: 'PCP3', descripcion: 'Clavo 505',
      proveedor: 'Trefilados Industriales', remito: 'R-1', cantidad: 1000, unidad: 'kg',
      cantidad_declarada: 1000, controlado: false, recibe_en_cajas: true },
    { id: 2, fecha: '2026-09-03', componente_id: 240, codigo: 'PA1', descripcion: 'Plaquita 3 en 1 LK',
      proveedor: 'Trefilados Industriales', remito: 'R-1', cantidad: 20, unidad: 'kg',
      cantidad_declarada: 20, controlado: false, recibe_en_cajas: false, kg_x_uni: 0.002 },
  ],
};

/* La recepcion pide su propio bundle y, aparte, los factores kg/uni + el flag
   recibe_en_cajas con un select directo a componente. */
const RECEP = {
  tara: { tara_pallet: '20', tol_ctrl_peso_pct: '5', carton_uni_x_paquete: '250' },
  sectores: [{ id: 6, nombre: 'Sector Plástico' }, { id: 7, nombre: 'Sector Bombilla' }],
  proveedores: [{ nombre: 'Trefilados Industriales', modo_control: null }],
  recepciones: [], pallets: [], rollos: [],
  insumos: [
    { comp_id: 256, codigo: 'PCP3', descripcion: 'Clavo 505', sector: 'Sector Plástico', sector_id: 6,
      um: 'unidad', proveedor: 'Trefilados Industriales', ultima: null, oc_pend: null },
    { comp_id: 539, codigo: 'BOM8', descripcion: 'Resorte para Bombilla', sector: 'Sector Bombilla',
      sector_id: 7, um: 'unidad', proveedor: 'Trefilados Industriales', ultima: null, oc_pend: null },
  ],
};
const COMPS = [{ id: 256, kg_x_uni: 0.00653, recibe_en_cajas: true },
               { id: 539, kg_x_uni: 0.0046, recibe_en_cajas: false }];

const STUB = 'window.supabase={createClient:function(){return{'
  + 'rpc:async function(n,a){ if(n==="control_recepcion_bundle") return {data:' + JSON.stringify(BUNDLE) + ',error:null};'
  + ' if(n==="recepcion_bundle") return {data:' + JSON.stringify(RECEP) + ',error:null};'
  + ' return {data:{ok:true},error:null}; },'
  + 'from:function(){ var q={select:function(){return q;},update:function(){return q;},'
  + 'in:function(){return Promise.resolve({data:' + JSON.stringify(COMPS) + ',error:null});},'
  + 'eq:function(){return Promise.resolve({data:[],error:null});}}; return q; }'
  + '};}};';

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  await page.route(/supabase-js@2/, r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/auth-guard.js*', r => r.fulfill({ contentType: 'application/javascript', body: 'window.GP2_AUTH_ON=false;' }));
  await page.route('**/GP2_favicon.png*', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));
  const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) process.exitCode = 1; };

  await page.goto(ROOT + '/StockFlejes/control-remaches.html?sector=6');
  await page.waitForSelector('.item-btn');
  ok((await page.textContent('#pageTitle')).includes('Plástico'), 'el titulo sale del sector del bundle');

  // El clavo: aparecen los dos campos y multiplican
  await page.click('.item-btn:has-text("PCP3")');
  await page.waitForSelector('#ovCtrl.open');
  ok(await page.isVisible('#cajasBox'), 'el clavo muestra cajas y kg por caja');
  await page.fill('#inCajas', '3');
  await page.fill('#inKgCaja', '8,4');
  const calc = (await page.textContent('#lblCajas')).replace(/\s+/g, ' ').trim();
  ok(/3 cajas x 8,4 kg = 25,2 kg/.test(calc), 'multiplica cajas x kg por caja — ' + calc);
  ok((await page.inputValue('#inKg')) === '25,2', 'los kg controlados se completan solos');
  ok(!(await page.isDisabled('#btnConfirm')), 'con la cuenta hecha se puede confirmar');
  const dif = (await page.textContent('#lblDiff')).replace(/\s+/g, ' ').trim();
  ok(/faltan/.test(dif), 'sigue comparando contra lo declarado — ' + dif);

  // La plaquita: un solo campo, como siempre
  await page.click('#btnCancel');
  await page.click('.item-btn:has-text("PA1")');
  await page.waitForSelector('#ovCtrl.open');
  ok(!(await page.isVisible('#cajasBox')), 'el insumo que no viene en cajas sigue con un solo campo');
  // ...pero si tiene kg por unidad, el control muestra el pasaje a unidades
  await page.fill('#inKg', '20');
  const uni = (await page.textContent('#lblUni')).replace(/\s+/g, ' ').trim();
  ok(/10\.000 unidades/.test(uni) && /0,002 kg/.test(uni), 'el control pasa los kg a unidades — ' + uni);

  // La pantalla entra en 390px sin scroll horizontal
  const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  ok(over <= 0, 'sin scroll horizontal en 390px (overflow=' + over + ')');

  // ── 2) la recepcion del mismo insumo: kg y punto ──────────────────────
  await page.goto(ROOT + '/StockFlejes/RecepcionInsumos_GP2.html');
  await page.click('button[data-rubro="Plasticos"]');
  await page.click('button:has-text("Trefilados Industriales")');
  await page.click('#btnContinuar');
  await page.waitForSelector('.item-btn');
  await page.click('.item-btn:has-text("PCP3")');
  await page.waitForSelector('#kgPopup.open');
  ok(!(await page.isVisible('#unitRow')), 'el clavo se recibe sin el toggle Kg/Unidades');
  const lbl = await page.textContent('#kgValueLabel');
  ok(lbl.includes('kg'), 'y el campo pide kg — ' + lbl);

  // Bombillas: se reciben contando unidades y el kg no aparece
  await page.click('button:has-text("Atrás"), button:has-text("Volver")').catch(() => {});
  await page.goto(ROOT + '/StockFlejes/RecepcionInsumos_GP2.html');
  await page.click('button[data-rubro="Bombillas"]');
  await page.click('button:has-text("Trefilados Industriales")');
  await page.click('#btnContinuar');
  await page.waitForSelector('.item-btn');
  await page.click('.item-btn:has-text("BOM8")');
  await page.waitForSelector('#kgPopup.open');
  ok(!(await page.isVisible('#unitRow')), 'bombillas se reciben sin el toggle (no aparece Kg)');
  const lblB = await page.textContent('#kgValueLabel');
  ok(/uni/i.test(lblB), 'y el campo pide unidades — ' + lblB);

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
