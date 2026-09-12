/* "Guardar pesaje" tiene que TERMINAR: guardar los pallets, cerrar el popup y mostrar la
   caja verde. Existe por un bug real del 2026-09-11 (usuario: "cuando pongo guardar pesaje
   no me deja, se buguea"): el commit 556b111 renombro la variable `fuera` a `itsFuera` en su
   declaracion y en dos usos, y dejo el tercero sin renombrar en el armado del mensaje de
   exito. Esa linea corre SIEMPRE, despues de que las RPC pesar_pallet ya se ejecutaron, asi
   que tiraba "ReferenceError: fuera is not defined" y abortaba el handler ANTES de
   cerrarPopup() / cargar(): los pallets quedaban guardados en la base pero la pantalla se
   quedaba clavada en "Guardando pesaje…" y la recepcion seguia figurando como pendiente.

   Los tests que ya habia (test_recepcion_etapas, test_recepcion_salir_pesaje) llegan hasta el
   boton pero NUNCA lo aprietan, asi que el camino del exito no lo miraba nadie. */
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) process.exitCode = 1; };
  const page = await browser.newPage({ viewport: { width: 390, height: 800 } });

  const errores = [];
  page.on('pageerror', e => { if (!/SB\.from/.test(e.message)) errores.push(e.message); });

  await page.route('**/auth-guard.js*', r => r.fulfill({ contentType: 'application/javascript', body: 'window.GP2_AUTH_ON=false;' }));
  await page.route('**/pwa.js*', r => r.fulfill({ contentType: 'application/javascript', body: '' }));
  // pesar_pallet responde OK; el resto devuelve el bundle minimo que la pantalla necesita.
  await page.route('**/@supabase/supabase-js@2', r => r.fulfill({ contentType: 'application/javascript', body:
    'window.__rpc=[];' +
    'window.supabase={createClient:()=>({rpc:async(n,a)=>{window.__rpc.push(n);' +
    '  if(n==="pesar_pallet") return {data:{ok:true,lineas:1},error:null};' +
    '  return {data:{insumos:[],proveedores:[],tara:{tara_pallet_min:4,tara_pallet_max:8,tara_estimada:5.0,tara_n:12,tara_por_proveedor:{}}},error:null};}})};' }));
  await page.goto('file://' + path.resolve(__dirname, '..', '..', 'StockFlejes', 'RecepcionInsumos_GP2.html'));
  await page.waitForTimeout(600);

  // Un item limpio: balanza 246 = 4 rollos x 60 (240) + 6 kg de pallet (sobrante dentro de
  // 4-8), y 246 > 236 del remito. Sin sobrante fuera de rango, sin excedente del 20%:
  // ningun confirm de por medio, el guardado tiene que salir derecho.
  await page.evaluate(() => montarPesaje([{
    recId: 7, codigo: 'A1', desc: 'Fleje N° 13', modo: 'rollos', remitoKg: 236,
    blocks: { 1: { peso: '246', rollos: [{ c: '4', k: '60' }] } },
  }]));
  await page.waitForTimeout(200);

  // Si aparece un dialogo es que el fixture dejo de ser limpio: se acepta y se avisa.
  const dialogos = [];
  page.on('dialog', async d => { dialogos.push(d.message()); await d.accept(); });

  ok(await page.locator('#kgPesajeOk').isVisible(), 'el boton Guardar pesaje esta a la vista');
  await page.click('#kgPesajeOk');
  await page.waitForTimeout(700);

  ok(dialogos.length === 0, 'guardado limpio, sin confirmaciones de por medio' +
     (dialogos.length ? ' — salio: ' + dialogos[0].split('\n')[0] : ''));
  ok(errores.length === 0, 'ningun error de JS al guardar' + (errores.length ? ' — ' + errores[0] : ''));
  const rpcs = await page.evaluate(() => window.__rpc || []);
  ok(rpcs.includes('pesar_pallet'), 'llamo a pesar_pallet');
  ok(await page.locator('#successBox').isVisible(), 'muestra la caja verde de recepcion completa');
  ok((await page.locator('#successDetail').innerText()).includes('1 pallet'), 'el detalle dice cuantos pallets peso');
  ok(!(await page.locator('#kgPopup').evaluate(e => e.classList.contains('open'))), 'el popup se cierra solo');
  const msg = await page.locator('#kgMsg').innerText();
  ok(!/Guardando pesaje/i.test(msg), 'no queda clavado en "Guardando pesaje…"');

  await browser.close();
})();
