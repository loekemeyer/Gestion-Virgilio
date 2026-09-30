/* Tablet → Enviar: box "📄 Ver O.C." arriba del buscador (v1.37.0, 2026-09-28).
   [usuario: "en el envío a prov de art terminado y talleristas o.c. … me aparezca arriba de
   'buscar por código' una box que me diga ver o.c. y pueda ver la o.c. de gestión virgilio"].
   Fija: (1) la box está para el tallerista O.C. y para el prov. AT, y NO para un tallerista
   común; (2) al tocarla lee GP2.v_oc_virgilio_pendiente filtrada por tipo + ref de ESA
   contraparte y muestra código, descripción y pendiente; (3) se vuelve a cerrar; (4) sin O.C.
   pendiente lo dice. Supabase STUBEADO (reusa el fixture de test_tablet.js). */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

// el bundle con la forma real, tomado del test principal para no duplicar el fixture
const src = fs.readFileSync(path.join(__dirname, 'test_tablet.js'), 'utf8');
const m = src.match(/const BUNDLE = (\{[\s\S]*?\n\});/);
if (!m) { console.log('FAIL no encontré el BUNDLE de test_tablet.js'); process.exit(1); }
const BUNDLE = eval('(' + m[1] + ')');

// O.C. pendiente de Cabral (proveedor_at 1); Carlos Aguirre (tallerista 14) sin O.C.
const OC = [
  { tipo: 'proveedor_at', ref_id: 1, articulo_id: 70, codigo: '922', fecha: '2026-09-23', cajas_ped: 40, cajas_rec: 10, cajas_pend: 30, unidad: 'Cajas' },
  { tipo: 'proveedor_at', ref_id: 1, articulo_id: 71, codigo: '223', fecha: '2026-09-16', cajas_ped: 12, cajas_rec: 0, cajas_pend: 12, unidad: 'Cajas' },
];
const ART = [ { id: 70, descripcion: 'Bombilla Resorte' }, { id: 71, descripcion: 'Bombilla Pico Loro' } ];

const STUB = `
window.__from = [];
function __q(tabla, rows){
  var f = {};
  var b = {
    select: function(){ return b; },
    eq: function(k, v){ f[k] = v; return b; },
    in: function(k, v){ f[k] = { in: v }; return b; },
    then: function(res, rej){
      window.__from.push({ tabla: tabla, filtros: JSON.parse(JSON.stringify(f)) });
      var out = rows.filter(function(r){ return Object.keys(f).every(function(k){
        var v = f[k]; return (v && v.in) ? v.in.indexOf(r[k]) >= 0 : String(r[k]) === String(v); }); });
      return Promise.resolve({ data: out, error: null }).then(res, rej);
    }
  };
  return b;
}
window.supabase = { createClient: function(){ return {
  rpc: async function(name){
    if(name==='tablet_bundle') return { data: JSON.parse(JSON.stringify(${JSON.stringify(BUNDLE)})), error: null };
    return { data: null, error: { message: 'rpc desconocida '+name } };
  },
  from: function(t){
    if (t === 'v_oc_virgilio_pendiente') return __q(t, ${JSON.stringify(OC)});
    if (t === 'articulo') return __q(t, ${JSON.stringify(ART)});
    return __q(t, []);
  }
};}};
`;

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  await page.route('**/@supabase/supabase-js@2**', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/GP2_favicon.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));
  const ok = (c, msg) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + msg); if (!c) process.exitCode = 1; };
  const oculto = sel => page.$eval(sel, e => e.classList.contains('hidden'));
  const aTipos = async () => page.waitForFunction(() => document.querySelectorAll('#tipoGrid .tipo-btn').length > 0);
  const enCarga = async () => page.waitForFunction(() => !document.getElementById('fase1').classList.contains('hidden'));

  await page.goto(ROOT + '/Tablet/Tablet_GP2.html');
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await aTipos();

  // tallerista común: sin box
  await page.click('#tipoGrid .tipo-btn[data-tipo="tallerista"]');
  await page.click('#cpGrid .prov-btn:has-text("Martin")');
  await enCarga();
  ok(await oculto('#ocBox'), 'tallerista común (Martin): NO tiene la box Ver O.C.');
  await page.click('#btnVolver');
  await page.click('#btnVolverTipo').catch(() => {});
  await aTipos();

  // prov. AT: box arriba del buscador
  await page.click('#tipoGrid .tipo-btn[data-tipo="proveedor_at"]');
  await enCarga();
  ok(!(await oculto('#ocBox')), 'prov. AT (Cabral): aparece la box Ver O.C.');
  const antes = await page.evaluate(() => {
    const b = document.getElementById('ocBox'), q = document.getElementById('q');
    return !!(b.compareDocumentPosition(q) & Node.DOCUMENT_POSITION_FOLLOWING);
  });
  ok(antes, 'la box va ARRIBA del "Buscar por código"');
  ok(await oculto('#ocBody'), 'arranca cerrada');
  await page.click('#btnVerOC');
  await page.waitForSelector('#ocBody table');
  const txt = await page.$eval('#ocBody', e => e.textContent.replace(/\s+/g, ' '));
  ok(txt.includes('922') && txt.includes('Bombilla Resorte') && txt.includes('30') && txt.includes('223'),
     'muestra la O.C. pendiente con código, descripción y pendiente — ' + txt.slice(0, 160));
  ok(txt.includes('42'), 'suma el total pendiente (30 + 12 = 42)');
  const f = await page.evaluate(() => window.__from.filter(x => x.tabla === 'v_oc_virgilio_pendiente'));
  ok(f.length === 1 && f[0].filtros.tipo === 'proveedor_at' && Number(f[0].filtros.ref_id) === 1,
     'lee v_oc_virgilio_pendiente filtrada por ESA contraparte — ' + JSON.stringify(f));
  const ancho = await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
  ok(ancho, 'a 390px la página no scrollea horizontal con la O.C. abierta');
  await page.click('#btnVerOC');
  ok(await oculto('#ocBody'), 'el mismo botón la vuelve a cerrar');
  await page.click('#btnVolver');
  await aTipos();

  // tallerista O.C. sin pendiente: box + cartel
  await page.click('#tipoGrid .tipo-btn[data-tipo="tallerista_oc"]');
  await enCarga();
  ok(!(await oculto('#ocBox')) && await oculto('#ocBody'), 'tallerista O.C.: box presente y cerrada al entrar');
  await page.click('#btnVerOC');
  await page.waitForFunction(() => /No hay O\.C\. pendiente/.test(document.getElementById('ocBody').textContent));
  ok(true, 'sin O.C. pendiente lo dice');

  await browser.close();
})().catch(e => { console.log('FAIL', e.message); process.exit(1); });
