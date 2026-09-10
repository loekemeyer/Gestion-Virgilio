const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
// Raiz del repo (los tests viven en tests/ui/) y Chromium portable si existe.
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const BUNDLE = {
  talleristas: [ { id: 2, nombre: 'Alex Escalante' }, { id: 9, nombre: 'Carlos Aguirre' } ],
  online: [
    { tall_id: 2, comp_id: 85, codigo: 'A10', descripcion: 'Cpo Una LK', sector: 'Sector Procesado',
      cantidad: 100, um: 'unidad', kg_x_uni: 0.02, uni_x_cajon: 500 },
    { tall_id: 2, comp_id: 90, codigo: 'V9', descripcion: 'Remache', sector: 'Sector Remache',
      cantidad: 40, um: 'kg', kg_x_uni: null, uni_x_cajon: null },
    { tall_id: 9, comp_id: 91, codigo: 'Z23', descripcion: 'Otra parte', sector: 'Sector Crudo',
      cantidad: 10, um: 'unidad', kg_x_uni: null, uni_x_cajon: null },
  ],
  analizar: [ { comp_id: 85, codigo: 'A10', descripcion: 'Cpo Una LK', cantidad: 5, um: 'unidad' } ],
  ultimas: [ { fecha: '2026-08-29T12:00:00Z', tallerista: 'Alex Escalante', codigo: 'A10',
               cantidad: 30, unidad: 'uni', destino: 'sector', motivo: 'rebaba' } ],
};

const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    window.__calls = window.__calls || [];
    window.__calls.push({name:name, args:args});
    if(name==='devoluciones_tallerista_bundle') return { data: ${JSON.stringify(BUNDLE)}, error: null };
    if(name==='crear_devolucion_tallerista') return { data: { ok:true, id: 1, aviso: null }, error: null };
    return { data: null, error: { message: 'rpc desconocida '+name } };
  }
};}};
`;

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const page = await browser.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });

  await page.route('**/@supabase/supabase-js@2', r =>
    r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/gp2-modulo.css**', r => r.fulfill({ contentType: 'text/css', body: '.hidden{display:none!important}' }));
  await page.route('**/GP2_favicon.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));

  await page.goto(ROOT + '/Talleristas/Recepcion/DevolucionCervantes_GP2.html');
  await page.waitForFunction(() => document.getElementById('status').textContent === '');

  const ok = (c, msg) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + msg); if (!c) process.exitCode = 1; };

  ok(await page.$$eval('#talls .chip', x => x.length) === 2, '2 talleristas');
  await page.click('#talls .chip:has-text("Alex")');
  ok(await page.$$eval('#tbody tr', x => x.length) === 2, 'Alex: 2 partes online');

  // sin destino: boton deshabilitado aunque haya cantidad
  await page.fill('.dev-in[data-in="85"]', '30');
  await page.$eval('.dev-in[data-in="85"]', x => x.dispatchEvent(new Event('change')));
  ok(await page.$eval('#btnConf', b => b.disabled), 'sin destino: deshabilitado');

  await page.click('#destAna');
  ok(!(await page.$eval('#btnConf', b => b.disabled)), 'con destino analizar: habilitado');

  // parte en kg
  await page.fill('.dev-in[data-in="90"]', '2,5');
  await page.$eval('.dev-in[data-in="90"]', x => x.dispatchEvent(new Event('change')));
  ok((await page.textContent('#btnConf')).includes('(2 partes)'), 'contador 2 partes');

  await page.fill('#motivo', 'fuera de tolerancia');
  await page.click('#btnConf');
  await page.waitForFunction(() => (window.__calls || []).filter(c => c.name === 'crear_devolucion_tallerista').length === 2);
  const calls = await page.evaluate(() => window.__calls.filter(c => c.name === 'crear_devolucion_tallerista').map(c => c.args));
  ok(calls[0].p_tallerista_id === 2 && calls[0].p_comp_id === 85 && calls[0].p_cantidad === 30 &&
     calls[0].p_unidad === 'uni' && calls[0].p_destino === 'analizar' && calls[0].p_motivo === 'fuera de tolerancia',
     'payload parte uni OK: ' + JSON.stringify(calls[0]));
  ok(calls[1].p_comp_id === 90 && calls[1].p_cantidad === 2.5 && calls[1].p_unidad === 'kg',
     'payload parte kg OK: ' + JSON.stringify(calls[1]));

  ok((await page.textContent('#status')).includes('✓'), 'status exito');
  ok((await page.textContent('#anaBody')).includes('A10'), 'tabla Para Analizar pintada');
  ok((await page.textContent('#ultBody')).includes('rebaba'), 'ultimas devoluciones pintadas');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
