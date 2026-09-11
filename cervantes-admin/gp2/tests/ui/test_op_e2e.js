const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
// Raiz del repo (los tests viven en tests/ui/) y Chromium portable si existe.
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const BUNDLE = {
  empleados: { '19': { nombre: 'Eduardo B', activo: true, hora_entrada: '08:00' } },
  registro_en_golpes: true,
  // 28 saca 1 pieza por golpe (el caso normal), 348 saca 2 (Corte Cuch Untar Mgo Madera)
  matrices: [ { n: '28', d: 'Pinza Grande', ppk: 30, uxg: 1, maq: 'alimentador', act: true },
              { n: '348', d: 'Corte Cuch Untar Mgo Madera', ppk: 84, uxg: 2, maq: 'alimentador', act: true },
              { n: '62', d: 'Corte Pinza Fiambre Derecha', ppk: 40, uxg: 1, maq: 'alimentador', act: false } ],
  matriz_fleje: { '28': { comp_id: 176, codigo: 'A1', descripcion: 'Fleje 13' } },
  // La 28 corta de DOS flejes segun la pieza: A15 sale del 94 (inox), J2 del 13.
  matriz_fleje_pieza: { '28': {
    '29': { comp_id: 176, codigo: 'A1',  descripcion: 'Fleje 13' },
    '86': { comp_id: 217, codigo: 'F1A', descripcion: 'Fleje 94' } } },
  matriz_salidas: {},
  rollos_saldo: [ { comp_id: 176, codigo: 'A1',  kg_por_rollo: 50, rollos: 3 },
                  { comp_id: 217, codigo: 'F1A', kg_por_rollo: 67, rollos: 2 } ],
  rollos_abiertos: {},
};

const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    window.__calls = (window.__calls||[]); window.__calls.push({name:name, args:args});
    if(name==='registro_operarios_bundle') return { data: ${JSON.stringify(BUNDLE)}, error: null };
    if(name==='registrar_evento_prod') return { data: { ok:true, id: window.__calls.length }, error: null };
    if(name==='tomar_rollo') return { data: { ok:true, uso_id: 1 }, error: null };
    if(name==='anular_evento_prod') return { data: { ok:true, anulados: 1 }, error: null };
    return { data: { ok:true }, error: null };
  },
  from: function(){ throw new Error('DIRECT TABLE ACCESS: ' + 'la app no debe tocar tablas directo'); }
};}};
`;

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const page = await browser.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  page.on('dialog', d => d.accept());

  await page.route('**/@supabase/supabase-js@2', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route(/Operarios_GP2\.html$/, r => r.continue()).catch(()=>{});

  await page.goto(ROOT + '/Produccion/RegistroApp/Operarios_GP2.html');
  await page.waitForFunction(() => (window.__calls||[]).some(c => c.name === 'registro_operarios_bundle'));

  const ok = (c, m) => { console.log((c?'OK  ':'FAIL')+' '+m); if(!c) process.exitCode = 1; };
  const calls = () => page.evaluate(() => window.__calls);

  // legajo -> opciones
  await page.fill('#legajoInput', '19');
  await page.click('#btnContinuar');
  await page.waitForSelector('.box[data-code="E"]');

  // E: matriz 28 + rollo
  await page.click('.box[data-code="E"]');
  await page.fill('#textInput', '28');
  await page.dispatchEvent('#textInput', 'input');
  await page.waitForSelector('#rolloGrid .rl');
  ok(await page.locator('#rolloGrid select').count() === 0, 'los rollos son BOTONES, no un desplegable');
  await page.locator('#rolloGrid .rl').first().click();   // A1 50 kg (primer boton)
  ok(await page.locator('#rolloGrid .rl.sel').count() === 1, 'el rollo elegido queda marcado');
  await page.click('#btnEnviar');
  await page.waitForFunction(() => (window.__calls||[]).some(c =>
    c.name === 'registrar_evento_prod' && c.args.p && c.args.p.matriz === '28' && c.args.p.uni === 0));
  let cs = await calls();
  const evE = cs.find(c => c.name === 'registrar_evento_prod' && c.args.p.matriz === '28');
  ok(evE.args.p.nombre_matriz === 'Pinza Grande' && evE.args.p.legajo === '19', 'evento E: matriz 28 Pinza Grande legajo 19');
  ok(cs.some(c => c.name === 'tomar_rollo' && c.args.p_comp_id === 176 && c.args.p_kg_por_rollo === 50 && c.args.p_matriz === '28'),
     'tomar_rollo A1 50kg matriz 28');

  // C: 500 GOLPES del contador (la app vuelve a la pantalla de legajo tras cada envio).
  // La app manda golpes crudos; multiplicar por uni_x_golpe es tarea de la RPC.
  await page.click('#btnContinuar');
  await page.waitForSelector('.box[data-code="C"]');
  await page.click('.box[data-code="C"]');
  ok((await page.textContent('#inputLabel')).toUpperCase().includes('GOLPES'), 'el cajon pide GOLPES, no unidades');
  await page.fill('#textInput', '500');
  await page.click('#btnEnviar');
  await page.waitForFunction(() => (window.__calls||[]).some(c =>
    c.name === 'registrar_evento_prod' && c.args.p && c.args.p.golpes === 500));
  cs = await calls();
  const evC = cs.find(c => c.name === 'registrar_evento_prod' && c.args.p.golpes === 500);
  ok(evC.args.p.matriz === '28' && evC.args.p.hora_inicio && evC.args.p.hora_fin, 'cajon 500 golpes con matriz y horas');
  ok(evC.args.p.uni === undefined, 'no manda uni: el factor lo aplica la base, no la app');

  // cartel de rollo: 500/30 = 16,7 kg usados -> quedan ~33,3
  await page.click('#btnContinuar');
  await page.waitForSelector('.box[data-code="C"]');
  await page.click('.box[data-code="C"]');
  await page.waitForSelector('#matrizInfo:not(.hidden)');
  const info = await page.textContent('#matrizInfo');
  ok(info.includes('Rollo de 50 kg') && info.includes('33,3'), 'rollo: quedan ~33,3 kg — ' + info.trim().slice(-60));

  // RM (volver de la seleccion C con la flecha; seguimos en la pantalla de opciones)
  await page.click('#btnResetSelection');
  await page.waitForSelector('.box[data-code="RM"]');
  await page.click('.box[data-code="RM"]');
  await page.click('#btnEnviar');
  await page.waitForFunction(() => (window.__calls||[]).some(c =>
    c.name === 'registrar_evento_prod' && c.args.p && c.args.p.nombre_matriz === 'Rotura Matriz'));
  cs = await calls();
  const evRM = cs.find(c => c.name === 'registrar_evento_prod' && c.args.p.nombre_matriz === 'Rotura Matriz');
  ok(evRM.args.p.matriz === '28' && evRM.args.p.uni === 0, 'RM sobre matriz 28');

  // borrar del historial (pantalla legajo) -> RPC anular_evento_prod (ya no update directo)
  await page.waitForSelector('.hist-del');
  await page.click('.hist-del');
  await page.waitForFunction(() => (window.__calls||[]).some(c => c.name === 'anular_evento_prod'));
  cs = await calls();
  const evDel = cs.find(c => c.name === 'anular_evento_prod');
  ok(typeof evDel.args.p_id_ejecucion === 'string' && evDel.args.p_id_ejecucion.length > 10, 'baja logica via RPC con id_ejecucion');

  // Matriz que saca 2 piezas por golpe: la app avisa la cuenta y sigue mandando GOLPES
  await page.click('#btnContinuar');
  await page.waitForSelector('.box[data-code="E"]');
  await page.click('.box[data-code="E"]');
  await page.fill('#textInput', '348');
  await page.dispatchEvent('#textInput', 'input');
  await page.click('#btnEnviar');
  await page.waitForFunction(() => (window.__calls||[]).some(c =>
    c.name === 'registrar_evento_prod' && c.args.p && c.args.p.matriz === '348'));
  await page.click('#btnContinuar');
  await page.waitForSelector('.box[data-code="C"]');
  await page.click('.box[data-code="C"]');
  await page.fill('#textInput', '240');
  await page.dispatchEvent('#textInput', 'input');
  const hint = await page.textContent('#golpeHint');
  ok(hint.includes('2') && hint.includes('480'), 'avisa 240 golpes x 2 = 480 unidades — ' + hint.trim());
  await page.click('#btnEnviar');
  await page.waitForFunction(() => (window.__calls||[]).some(c =>
    c.name === 'registrar_evento_prod' && c.args.p && c.args.p.golpes === 240));
  cs = await calls();
  const evG = cs.find(c => c.name === 'registrar_evento_prod' && c.args.p.golpes === 240);
  ok(evG.args.p.matriz === '348' && evG.args.p.uni === undefined, 'matriz de 2 por golpe: manda 240 golpes, no 480 uni');

  // Matriz dada de baja: ni aparece en la lista ni se acepta tipeada
  await page.click('#btnContinuar');
  await page.waitForSelector('.box[data-code="E"]');
  await page.click('.box[data-code="E"]');
  // el buscador de abajo se saco (v1.9.0): el campo de arriba filtra numero Y nombre
  await page.fill('#textInput', '62');
  await page.dispatchEvent('#textInput', 'input');
  ok(!(await page.textContent('#matrizGrid')).includes('Fiambre'), 'la matriz de baja no se ofrece en la lista');
  // el campo de arriba tambien filtra por NOMBRE (por eso el buscador de abajo sobraba)
  await page.fill('#textInput', 'untar');
  await page.dispatchEvent('#textInput', 'input');
  const porNombre = await page.textContent('#matrizGrid');
  ok(porNombre.includes('348') && !porNombre.includes('Pinza Grande'),
     'escribiendo un NOMBRE arriba se filtra la lista (sin buscador aparte)');
  // match EXACTO de numero: la lista colapsa a esa sola matriz (usuario: "cuando elijo 1
  // no me muestres las demas"). '28' matchea exacto la 28 y NO debe mostrar 348 ni otras.
  await page.fill('#textInput', '28');
  await page.dispatchEvent('#textInput', 'input');
  ok(await page.locator('#matrizGrid .mz').count() === 1, 'match exacto de numero: la lista muestra SOLO esa matriz');
  ok((await page.textContent('#matrizGrid')).includes('28'), 'y es la matriz que se tipeo');
  const antes = (await calls()).length;
  await page.fill('#textInput', '62');
  await page.dispatchEvent('#textInput', 'input');
  await page.click('#btnEnviar');
  ok((await calls()).length === antes, 'la matriz de baja tampoco se acepta tipeada');
  await page.click('#btnResetSelection');

  // EL ROLLO DEPENDE DE LA PIEZA, no solo de la matriz (usuario 2026-08-31: "A15 usa un
  // tipo de rollo (inox) y J2/J5 usa otro"). Antes se ofrecia siempre el mismo fleje y el
  // stock se descontaba del equivocado.
  {
    const rollosDe = (compSalidaId) => page.evaluate(id => {
      piezaSel = id === null ? null : { comp_id: id };
      actualizarRolloPicker('28');
      const msg = document.querySelector('#rolloGrid .rl-msg');
      if (msg) return [msg.textContent];
      return [...document.querySelectorAll('#rolloGrid .rl')].map(o => o.textContent);
    }, compSalidaId);

    // sin selector de pieza en pantalla (matriz_salidas vacio en este stub) se ofrecen
    // los rollos de LOS DOS flejes, con el codigo a la vista: nunca deja sin opciones
    const sinPieza = (await rollosDe(null)).join(' | ');
    ok(/A1/.test(sinPieza) && /F1A/.test(sinPieza),
       'sin pieza elegida ofrece los rollos de los dos flejes — ' + sinPieza);

    const deJ2 = (await rollosDe(29)).join(' | ');
    ok(/A1/.test(deJ2) && !/F1A/.test(deJ2), 'J2 ofrece SOLO rollos del Fleje 13 — ' + deJ2);

    const deA15 = (await rollosDe(86)).join(' | ');
    ok(/F1A/.test(deA15) && !/A1/.test(deA15), 'A15 ofrece SOLO rollos del Fleje 94 (inox) — ' + deA15);

    await page.evaluate(() => { piezaSel = null; });
  }

  // badge sync sin pendientes
  const badge = await page.textContent('#syncBadge');
  ok(badge.includes('✓'), 'cola sincronizada: ' + badge.trim());

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
