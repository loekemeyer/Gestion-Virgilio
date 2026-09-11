const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

/* v3.22.0: NO SE PUEDE SALIR SIN CONTROLAR [usuario 2026-08-31: "No se puede
   salir sin controlar de ningún modulo"]. Este test cubre lo contrario del
   viejo: el paso 2 (pesaje/control) NO tiene "Salir sin pesar" visible; la X
   y Escape ya NO cierran el popup — muestran "Terminá el control para salir".
   Y ademas: mientras hay REMITO en curso o control activo, las salidas
   generales (Atras del header y ← Volver del paso 2) tambien se ocultan. Al
   terminar (o al desmontar) todo vuelve a la normalidad. */
const BUNDLE = {
  tara: { tara_pallet: '20', tol_ctrl_peso_pct: '5', carton_uni_x_paquete: '250' },
  sectores: [{ id: 5, nombre: 'Sector Fleje' }],
  proveedores: [{ nombre: 'Basconia', modo_control: 'rollos_remito', informa_rollos: true, factura_uni: false }],
  recepciones: [], pallets: [], rollos: [],
  insumos: [
    { comp_id: 1, codigo: 'A1', descripcion: 'Fleje N° 13', sector: 'Sector Fleje', sector_id: 5, um: 'kg',
      proveedor: 'Basconia', n_fleje: 13, medida: '84 x 1,75', ultima: null, oc_pend: null },
  ],
};

const STUB = 'window.supabase={createClient:function(){return{'
  + 'rpc:async function(n,a){ if(n==="recepcion_bundle") return {data:' + JSON.stringify(BUNDLE) + ',error:null};'
  + ' if(n==="cargar_recepcion") return {data:{recepcion_id:77,movimiento_id:1,oc_cruzada:[]},error:null};'
  + ' return {data:{ok:true},error:null}; },'
  + 'from:function(){ var q={select:function(){return q;},in:function(){return Promise.resolve({data:[],error:null});}}; return q; }'
  + '};}};';

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  await page.route('**/@supabase/supabase-js@2', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/auth-guard.js*', r => r.fulfill({ contentType: 'application/javascript', body: 'window.GP2_AUTH_ON=false;' }));
  await page.route('**/GP2_favicon.png*', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));
  const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) process.exitCode = 1; };
  // el beforeunload del handler abre un dialogo que el test acepta para no colgar
  page.on('dialog', d => d.accept());

  // Llegar al paso 2 como en la vida real: rubro -> proveedor -> item -> remito -> "Termine"
  async function llegarAlPesaje() {
    await page.goto(ROOT + '/StockFlejes/RecepcionInsumos_GP2.html');
    await page.click('button:has-text("Flejes")');
    await page.click('button:has-text("Basconia")');
    await page.click('#btnContinuar');
    await page.waitForSelector('.item-btn');
    // cargar() es async y al terminar RE-RENDERIZA: puede reemplazar el boton del item
    // justo cuando se lo clickea, o vaciar los campos del popup recien llenados. Se
    // reintenta la secuencia ENTERA hasta que sale.
    for (let intento = 1; ; intento++) {
      try {
        await page.click('.item-btn');
        await page.waitForSelector('#kgPopup.open', { timeout: 3000 });
        // Desde v3.31.1 (revision usuario 2026-09-01) el popup de fleje pide SOLO el
        // Kg total: Basconia perdio su "Kg x Rollo" y el unico proveedor con campo
        // extra es Hermac (Paquetes). Por eso aca ya no se llenan #kgRollos/#kgPallets
        // — no existen en el DOM.
        await page.fill('#kgValue', '360');
        await page.waitForFunction(() => document.getElementById('kgValue').value === '360',
                                   null, { timeout: 3000 });
        await page.click('#kgConfirm');
        // Desde v3.34.0 el remito esta BUFFERIZADO: Confirmar deja el item en PEND
        // (nada baja a la BD todavia) y lo que aparece es "✓ Terminé de cargar remito"
        // al lado del buscador. Ese boton es el que dispara flushPend() -> N
        // cargar_recepcion con el mismo remito -> paso 2. El viejo #btnFinRemito
        // hoy solo sale cuando ya hay recepciones bajadas esperando control.
        await page.waitForSelector('#btnTerminarRemito', { timeout: 3000 });
        break;
      } catch (e) {
        if (intento >= 6) throw e;
        await page.waitForTimeout(300);
        await page.evaluate(() => { const p = document.getElementById('kgPopup');
                                    if (p) p.classList.remove('open'); });
      }
    }
    await page.click('#btnTerminarRemito');
    await page.waitForSelector('#pesajeWrap:not(.hidden)');
  }

  await llegarAlPesaje();

  // 1) el paso 2 NO ofrece "Salir sin pesar" (control obligatorio)
  // La X del popup se saco en v3.24.0 [usuario: "el funcionamiento de no poder salir
  // esta bien pero saca la X no se va a usar"], asi que ya no se chequea: se sale por
  // Cancelar (paso 1) o Guardar (paso 2), y Escape sigue avisando (punto 4).
  const pie = await page.evaluate(() => {
    const vis = id => { const e = document.getElementById(id); return !!e && !e.classList.contains('hidden'); };
    return { salir: vis('kgPesajeSalir'), guardar: vis('kgPesajeOk'), cancelar: vis('kgCancel'),
             hayX: !!document.getElementById('kgX') };
  });
  ok(!pie.salir, 'el paso 2 NO muestra "Salir sin pesar" (control obligatorio)');
  ok(pie.guardar, 'sigue estando "Guardar pesaje"');
  ok(!pie.cancelar, 'el "Cancelar" del paso 1 no se mezcla');
  ok(!pie.hayX, 'la X del popup sigue afuera (se saco en v3.24.0)');

  // 2) Atras del header y Volver del paso 2 estan OCULTOS mientras hay REMITO/PES
  const salidasOcultas = await page.evaluate(() => {
    const a = document.getElementById('btnAtrasHeader');
    const v = document.getElementById('btnVolver1');
    return { atras: a && a.style.display === 'none', volver: v && v.style.display === 'none' };
  });
  ok(salidasOcultas.atras, 'con PES activo, "Atras" del header queda oculto');
  ok(salidasOcultas.volver, 'con PES activo, "← Volver" del paso 2 queda oculto');

  // 3) (el punto de la X quedo sin objeto desde v3.24.0 — ver arriba)

  // 4) Escape tampoco cierra
  await page.keyboard.press('Escape');
  await page.waitForTimeout(200);
  const trasEsc = await page.evaluate(() => ({
    abierto: document.getElementById('kgPopup').classList.contains('open'),
    msg: document.getElementById('kgMsg').textContent,
  }));
  ok(trasEsc.abierto, 'Escape NO cierra el popup durante el pesaje');
  ok(/termin[aá] el control/i.test(trasEsc.msg), 'Escape avisa "Terminá el control..."');

  // 5) el click en el fondo sigue SIN cerrar en el paso 2
  await page.evaluate(() => document.getElementById('kgPopup').click());
  await page.waitForTimeout(150);
  ok(await page.$('#kgPopup.open') !== null, 'el click en el fondo NO cierra el pesaje');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
