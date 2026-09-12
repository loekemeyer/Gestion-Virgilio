/* Panel "Material plastico en poder de cada inyector" de Compras/Inyectores_GP2.html (2026-09-10).
 * El bundle trae `materiales` (bolsas del sector 14 con su stock en Virgilio) y `material` (por
 * inyector x material: lo que necesita para sus OC abiertas, lo que tiene, lo que hay que enviarle).
 * Chequea que el panel aparezca solo con datos, que la fila proponga las bolsas calculadas, que
 * "Enviar" mande enviar_material_inyector con los kg = bolsas x kg_x_bolsa, que el envio manual
 * funcione con los selects, y que cada parte muestre su material.
 */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const BUNDLE = {
  generado_en: '2026-09-10T10:00:00Z',
  sector: { id: 6, nombre: 'Sector Plástico' },
  sectores: [{ id: 6, nombre: 'Sector Plástico', n: 2, sin_prov: 0 }],
  proveedores: [
    { nombre: 'Indarnyl', modo_control: 'ninguno', n: 0, es_inyector: false },
    { nombre: 'Pat Bet Plast', modo_control: 'ninguno', n: 1, es_inyector: true },
    { nombre: 'Pettofrezza Rafael', modo_control: 'ninguno', n: 1, es_inyector: true },
  ],
  partes: [
    { comp_id: 622, codigo: 'PC2', descripcion: 'Mgo Pelapapa 505 Sin Calar', proveedor: 'Pettofrezza Rafael',
      um: 'unidad', kg_x_uni: 0.0054, material_id: 742, material: '2405', lo_produce: null, stock: 100, en_recetas: 1 },
    { comp_id: 253, codigo: 'PC8', descripcion: 'Cachas Azules', proveedor: 'Pat Bet Plast',
      um: 'unidad', kg_x_uni: 0.023, material_id: 742, material: '2405', lo_produce: null, stock: 0, en_recetas: 2 },
  ],
  materiales: [
    { comp_id: 742, codigo: '2405', descripcion: 'PP 2630 (Polipropileno)', kg_virgilio: 3075 },
    { comp_id: 743, codigo: '2455', descripcion: 'ABS GP 22 Natural', kg_virgilio: 350 },
  ],
  material: [
    { prov_id: 31, proveedor: 'Pettofrezza Rafael', ubic_id: 58, material_id: 742, material_codigo: '2405',
      material: 'PP 2630 (Polipropileno)', kg_requerido_oc: 56.16, kg_en_inyector: 10, kg_en_virgilio: 3075,
      desperdicio_pct: 4, kg_a_enviar: 46.16, bolsas_a_enviar: 2, kg_x_bolsa: 25 },
  ],
  desperdicio_pct: 4,
  kg_x_bolsa: 25,
};

const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    window.__calls = window.__calls || [];
    window.__calls.push({name:name, args:args});
    if(name==='inyectores_bundle') return { data: ${JSON.stringify(BUNDLE)}, error: null };
    if(name==='enviar_material_inyector')
      return { data: { ok:true, movimiento_id: 1, codigo: '2405', kg: args.p_kg, virgilio_despues: 3075-args.p_kg, virgilio_negativo: false }, error: null };
    return { data: null, error: { message: 'rpc desconocida '+name } };
  },
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

  // el panel se ve, con el stock de Virgilio en bolsas
  ok(await page.$eval('#matPanel', e => !e.classList.contains('hidden')), 'el panel de material aparece cuando el bundle trae materiales');
  const virg = await page.textContent('#matVirgilio');
  ok(/2405/.test(virg) && /123 bolsas/.test(virg), 'Virgilio: 3.075 kg de PP = 123 bolsas: ' + virg.trim());

  // la fila del inyector propone las bolsas calculadas por la base y marca lo que falta
  ok(await page.$$eval('#matTabla tbody tr', x => x.length) === 1, 'una fila inyector x material');
  ok(await page.$eval('#matTabla tbody .mat-bolsas', i => i.value) === '2', 'propone 2 bolsas (46,16 kg / 25)');
  ok(await page.$eval('#matTabla tbody td.falta', t => t.textContent).then(t => /46,2/.test(t)), 'lo que falta va resaltado y con coma decimal');

  // Enviar: manda la RPC en KG (bolsas x 25) al inyector de la fila, y recarga
  await page.fill('#matTabla tbody .mat-bolsas', '3');
  await page.click('#matTabla tbody .mat-btn');
  await page.waitForFunction(() => (window.__calls || []).some(c => c.name === 'enviar_material_inyector'));
  const call = await page.evaluate(() => window.__calls.filter(c => c.name === 'enviar_material_inyector')[0].args);
  ok(call.p_proveedor === 'Pettofrezza Rafael' && call.p_comp_id === 742 && call.p_kg === 75,
     'RPC: Pettofrezza, PP, 3 bolsas = 75 kg: ' + JSON.stringify(call));
  await page.waitForFunction(() => /75 kg/.test(document.getElementById('matStatus').textContent));
  ok(/3 bolsas/.test(await page.textContent('#matStatus')), 'status confirma las 3 bolsas');
  ok((await page.evaluate(() => window.__calls.filter(c => c.name === 'inyectores_bundle').length)) >= 2, 'recarga el bundle despues de enviar');

  // envio manual: solo los inyectores en el select (Indarnyl vende bolsas, no inyecta)
  const inys = await page.$$eval('#matIny option', xs => xs.map(x => x.value));
  ok(inys.join('|') === 'Pat Bet Plast|Pettofrezza Rafael', 'select de inyectores: ' + inys.join('|'));
  await page.selectOption('#matIny', 'Pat Bet Plast');
  await page.selectOption('#matMat', '743');
  await page.fill('#matBolsas', '4');
  await page.click('#matEnviar');
  await page.waitForFunction(() => (window.__calls || []).filter(c => c.name === 'enviar_material_inyector').length === 2);
  const call2 = await page.evaluate(() => { const c = window.__calls.filter(x => x.name === 'enviar_material_inyector'); return c[c.length - 1].args; });
  ok(call2.p_proveedor === 'Pat Bet Plast' && call2.p_comp_id === 743 && call2.p_kg === 100,
     'envio manual: Pat Bet Plast, ABS, 4 bolsas = 100 kg: ' + JSON.stringify(call2));

  // 0 bolsas no manda nada
  await page.fill('#matBolsas', '0');
  await page.click('#matEnviar');
  await page.waitForFunction(() => /más de 0/.test(document.getElementById('matStatus').textContent));
  ok((await page.evaluate(() => window.__calls.filter(c => c.name === 'enviar_material_inyector').length)) === 2, '0 bolsas no llama a la RPC');

  // cada parte dice de que material esta hecha y cuantos gramos pesa
  const meta = await page.textContent('.parte:first-child .p-meta');
  ok(/material 2405/.test(meta) && /5,4 g/.test(meta), 'la parte muestra material y gramos: ' + meta.trim());

  // teclado numerico en los campos de bolsas (regla de la casa)
  ok(await page.$$eval('input.mat-bolsas, #matBolsas', xs => xs.every(x => x.getAttribute('inputmode') === 'numeric')), 'inputs de bolsas con inputmode=numeric');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
