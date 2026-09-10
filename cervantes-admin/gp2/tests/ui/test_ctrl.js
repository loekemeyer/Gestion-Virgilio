const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
// Raiz del repo (los tests viven en tests/ui/) y Chromium portable si existe.
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const BUNDLE = {
  filas: [
    { fecha: '2026-08-05', tipo: 'envio_ps', comp_id: 1, codigo: 'J2', descripcion: 'Cuchilla',
      um: 'unidad', kg_x_uni: 0.02, uni_x_cajon: 1000, orig: 'Sector Crudo', dest: 'Prov. Serv. Becker',
      cantidad: 500, unidad: 'uni', canon: 500 },
    { fecha: '2026-08-05', tipo: 'envio_ps', comp_id: 1, codigo: 'J2', descripcion: 'Cuchilla',
      um: 'unidad', kg_x_uni: 0.02, uni_x_cajon: 1000, orig: 'Sector Crudo', dest: 'Prov. Serv. Becker',
      cantidad: 300, unidad: 'uni', canon: 300 },
    { fecha: '2026-08-12', tipo: 'envio_ps', comp_id: 1, codigo: 'J2', descripcion: 'Cuchilla',
      um: 'unidad', kg_x_uni: 0.02, uni_x_cajon: 1000, orig: 'Sector Crudo', dest: 'Prov. Serv. Becker',
      cantidad: 200, unidad: 'uni', canon: 200 },
    { fecha: '2026-08-07', tipo: 'entrega_ps', comp_id: 2, codigo: 'A10', descripcion: 'Cpo Una',
      um: 'unidad', kg_x_uni: 0.0177, uni_x_cajon: 1695, orig: 'Prov. Serv. Becker', dest: 'Sector Procesado',
      cantidad: 400, unidad: 'uni', canon: 400 },
    { fecha: '2026-08-09', tipo: 'envio_tallerista', comp_id: 2, codigo: 'A10', descripcion: 'Cpo Una',
      um: 'unidad', kg_x_uni: 0.0177, uni_x_cajon: 1695, orig: 'Sector Procesado', dest: 'Tallerista Alex',
      cantidad: 100, unidad: 'uni', canon: 100 },
  ],
};

const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    window.__calls = window.__calls || [];
    window.__calls.push({name:name, args:args});
    if(name==='control_envios_bundle') return { data: ${JSON.stringify(BUNDLE)}, error: null };
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

  await page.goto(ROOT + '/Control%20Envios%20y%20Entregas/ControlEnvios_GP2.html');
  await page.waitForFunction(() => (window.__calls || []).some(c => c.name === 'control_envios_bundle'));
  await page.waitForFunction(() => document.querySelectorAll('#tbody tr').length > 0);

  const ok = (c, msg) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + msg); if (!c) process.exitCode = 1; };

  // rango del mes actual
  const args = await page.evaluate(() => window.__calls[0].args);
  ok(/^\d{4}-\d{2}-01$/.test(args.p_desde), 'p_desde primer dia: ' + args.p_desde);

  // vista inicial PS/Envios: 1 fila pivote (J2 x Becker) con cols 5 y 12
  let ths = await page.$$eval('#thead th', xs => xs.map(x => x.textContent));
  ok(ths.join(',').includes('5') && ths.join(',').includes('12'), 'columnas dias 5 y 12: ' + ths.join(','));
  let rows = await page.$$eval('#tbody tr', xs => xs.map(x => x.textContent));
  ok(rows.length === 2 && rows[0].includes('J2') && rows[0].includes('Becker'), 'fila J2 Becker + total');
  ok(rows[0].includes('800'), 'celda dia 5 = 800 (500+300)');
  ok(rows[0].includes('1.000'), 'total fila = 1.000');

  // Entregas PS
  await page.click('#tipoChips .chip:has-text("Entregas")');
  rows = await page.$$eval('#tbody tr', xs => xs.map(x => x.textContent));
  ok(rows.length === 2 && rows[0].includes('A10') && rows[0].includes('Becker'), 'entrega PS: contraparte = origen');

  // Medida Kg: 400 x 0.0177 = 7,08 -> 7,1
  await page.click('#medChips .chip:text-is("Kg")');
  await page.waitForFunction(() => document.querySelector('#tbody tr')?.textContent.includes('7,1'));
  rows = await page.$$eval('#tbody tr', xs => xs.map(x => x.textContent));
  ok(rows[0].includes('7,1') && rows[0].includes('kg'), 'medida kg: 7,1 kg — ' + rows[0].slice(0, 60));

  // Talleristas / Envios
  await page.click('#medChips .chip:text-is("Kg/Uni")');
  await page.click('#origChips .chip:has-text("Talleristas")');
  await page.click('#tipoChips .chip:text-is("Envíos")');
  await page.waitForFunction(() => document.querySelector('#tbody tr')?.textContent.includes('Alex'));
  rows = await page.$$eval('#tbody tr', xs => xs.map(x => x.textContent));
  ok(rows.length === 2 && rows[0].includes('Alex') && rows[0].includes('100'), 'talleristas envios: Alex 100 uni');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
