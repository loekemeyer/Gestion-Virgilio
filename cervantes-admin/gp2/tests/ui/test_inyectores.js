const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
// Raiz del repo (los tests viven en tests/ui/) y Chromium portable si existe.
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const BUNDLE = {
  generado_en: '2026-08-29T10:00:00Z',
  sector: { id: 4, nombre: 'Sector Plástico' },
  sectores: [
    { id: 4, nombre: 'Sector Plástico', n: 3, sin_prov: 2 },
    { id: 11, nombre: 'Sector Remache', n: 8, sin_prov: 8 },
  ],
  proveedores: [
    { nombre: 'Kollplast', modo_control: 'ninguno', n: 0 },
    { nombre: 'Pat Bet Plast', modo_control: 'ninguno', n: 1 },
    { nombre: 'Pettofrezza Rafael', modo_control: 'ninguno', n: 0 },
  ],
  partes: [
    { comp_id: 101, codigo: 'PA1', descripcion: 'Plaquita 3 en 1 LK', proveedor: 'Pat Bet Plast',
      um: 'unidad', kg_x_uni: null, uni_x_cajon: null, lo_produce: null, stock: 500, en_recetas: 2 },
    { comp_id: 102, codigo: 'PA10B', descripcion: 'Capuchon 8 S/Serig', proveedor: null,
      um: 'unidad', kg_x_uni: null, uni_x_cajon: null, lo_produce: null, stock: 0, en_recetas: 1 },
    { comp_id: 103, codigo: 'PEP7', descripcion: 'Mgo sacafuente pizzero', proveedor: null,
      um: 'unidad', kg_x_uni: null, uni_x_cajon: null, lo_produce: 'Maspoli SRL', stock: 12, en_recetas: 1 },
    { comp_id: 104, codigo: 'PB9', descripcion: 'Inserto viejo', proveedor: null, estado_compra: 'discontinuo',
      um: 'unidad', kg_x_uni: null, uni_x_cajon: null, lo_produce: null, stock: 0, en_recetas: 0 },
  ],
};

const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    window.__calls = window.__calls || [];
    window.__calls.push({name:name, args:args});
    if(name==='inyectores_bundle') return { data: ${JSON.stringify(BUNDLE)}, error: null };
    if(name==='marcar_estado_compra')
      return { data: { ok:true, comp_id: args.p_comp_id, estado: args.p_estado }, error: null };
    if(name==='asignar_proveedor_parte'){
      if(args.p_proveedor==='Proveedor Trucho')
        return { data:null, error:{ message:'El proveedor "Proveedor Trucho" no existe o esta inactivo.' } };
      return { data: { ok:true, comp_id: args.p_comp_id, proveedor: args.p_proveedor }, error: null };
    }
    return { data: null, error: { message: 'rpc desconocida '+name } };
  },
  // si la pantalla tocara una tabla directo (RLS la bloquearia), que reviente el test
  from: function(t){ throw new Error('acceso directo a la tabla '+t); }
};}};
`;

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const page = await browser.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  page.on('console', m => { if (m.type() === 'error') console.log('CONSOLE:', m.text()); });

  await page.route('**/@supabase/supabase-js@2', r =>
    r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/gp2-modulo.css**', r =>
    r.fulfill({ contentType: 'text/css', body: '.hidden{display:none!important}' }));
  await page.route('**/GP2_favicon.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));

  await page.goto(ROOT + '/Compras/Inyectores_GP2.html');
  await page.waitForFunction(() => /partes/.test(document.getElementById('status').textContent));

  const ok = (c, msg) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + msg); if (!c) process.exitCode = 1; };

  // una fila por parte, con la botonera de los 3 inyectores + "sin asignar"
  ok(await page.$$eval('.parte', x => x.length) === 4, '4 partes listadas');
  const btns = await page.$$eval('.parte:first-child .pbtn', xs => xs.map(x => x.textContent));
  ok(btns.join('|') === 'Kollplast|Pat Bet Plast|Pettofrezza Rafael|Se fabrica|Discontinuo|— sin asignar',
     'botonera: ' + btns.join('|'));

  // el proveedor actual viene marcado; las partes sin asignar se resaltan
  ok(await page.$eval('.parte:first-child .pbtn.on', b => b.textContent) === 'Pat Bet Plast',
     'PA1 marca Pat Bet Plast');
  // el discontinuado NO cuenta como pendiente: es una decision tomada, no un faltante
  ok(await page.$$eval('.parte.sin', x => x.length) === 2, '2 partes sin asignar resaltadas');
  ok(await page.$$eval('.parte.nocompra', x => x.length) === 1, 'el discontinuado va aparte, no como faltante');
  ok(/Discontinuo/.test(await page.textContent('.parte:nth-child(4) .p-meta')), 'la fila dice Discontinuo');

  // aviso de que PEP7 lo fabrica un tallerista (no se compra)
  const meta = await page.textContent('.parte:nth-child(3) .p-meta');
  ok(/Maspoli SRL/.test(meta) && /no se compra/.test(meta), 'avisa que PEP7 lo fabrica Maspoli');

  // asignar: click en Kollplast sobre PA10B manda la RPC y queda marcado
  await page.click('.parte:nth-child(2) .pbtn:has-text("Kollplast")');
  await page.waitForFunction(() => (window.__calls || []).some(c => c.name === 'asignar_proveedor_parte'));
  const call = await page.evaluate(() => window.__calls.filter(c => c.name === 'asignar_proveedor_parte')[0].args);
  ok(call.p_comp_id === 102 && call.p_proveedor === 'Kollplast',
     'RPC con comp_id 102 y Kollplast: ' + JSON.stringify(call));
  ok(await page.$eval('.parte:nth-child(2) .pbtn.on', b => b.textContent) === 'Kollplast',
     'PA10B queda marcado en Kollplast');
  ok(await page.$$eval('.parte.sin', x => x.length) === 1, 'queda 1 sin asignar');
  ok(/quedan 1 sin asignar/.test(await page.textContent('#status')), 'status cuenta las pendientes');

  // marcar "Se fabrica": manda la RPC nueva y saca la parte de los pendientes
  await page.click('.parte:nth-child(3) .pbtn:has-text("Se fabrica")');
  await page.waitForFunction(() => (window.__calls||[]).some(c => c.name === 'marcar_estado_compra'));
  const est = await page.evaluate(() => window.__calls.filter(c => c.name === 'marcar_estado_compra')[0].args);
  ok(est.p_comp_id === 103 && est.p_estado === 'fabricacion', 'RPC estado: ' + JSON.stringify(est));
  ok(/fuera de la OC/.test(await page.textContent('#status')), 'avisa que queda fuera de la OC');
  ok(await page.$$eval('.parte.nocompra', x => x.length) === 2, 'ahora hay 2 que no se compran');

  // el resumen por proveedor se recalcula sin recargar
  const res = await page.$$eval('.rcard', xs => xs.map(x => x.textContent));
  ok(res.some(t => /1Kollplast/.test(t)) && res.some(t => /1Pat Bet Plast/.test(t)),
     'resumen por proveedor: ' + res.join(' / '));
  // lo que no se compra se cuenta aparte, NO como pendiente
  ok(res.some(t => /1Se fabrica/.test(t)) && res.some(t => /1Discontinuo/.test(t)),
     'el resumen separa lo que no se compra: ' + res.join(' / '));
  ok(!res.some(t => /2\(sin asignar\)/.test(t)), 'no cuenta lo decidido como sin asignar');

  // desasignar vuelve a dejarla pendiente (PEP7 y PB9 ya no cuentan: no se compran)
  await page.click('.parte:nth-child(2) .pbtn.clear');
  await page.waitForFunction(() => document.querySelectorAll('.parte.sin').length === 1);
  const call2 = await page.evaluate(() => { const c = window.__calls.filter(x => x.name === 'asignar_proveedor_parte'); return c[c.length-1].args; });
  ok(call2.p_proveedor === null, 'desasignar manda proveedor null');

  // el buscador filtra
  await page.fill('#q', 'capuchon');
  ok(await page.$$eval('.parte', x => x.length) === 1, 'buscador filtra a 1');
  await page.fill('#q', '');

  // cambiar de rubro pide el bundle de ese sector
  await page.click('#secChips .chip:has-text("Remache")');
  await page.waitForFunction(() => (window.__calls || []).some(
    c => c.name === 'inyectores_bundle' && c.args && c.args.p_sector_id === 11));
  ok(true, 'el chip de rubro pide el bundle del sector 11');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
