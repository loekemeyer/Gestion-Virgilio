/* Humo de TODAS las pantallas GP2 (2026-09-05): cada *_GP2.html (mas Programa, Validacion
 * de Stock y Orden de Produccion, que no llevan sufijo) se abre con Supabase STUBEADO y sin
 * red, y se mira lo que revienta al cargar.
 *
 * Existe porque el refactor de helpers (gp2-ui.js, gp2-numero.js) toca 41 pantallas y solo
 * ~25 tienen test propio: una pantalla sin test que cargue el helper en el orden equivocado
 * (o con la ruta relativa mal) se rompia en silencio hasta que alguien la abria en el celular.
 *
 * Falla si en alguna pagina:
 *   - un <script src> local no existe (ruta relativa mal, token mal, archivo borrado);
 *   - hay un ReferenceError / "is not a function" sobre un helper de la casa (GP2UI, GP2N,
 *     GP2EE, GP2M, GP2ConsumoDetalle, GP2Composicion, GP2StockSector, esc, $, fmt...).
 * Otros errores (la pantalla no tolera el stub vacio) se listan como aviso y no fallan:
 * son de datos, no de estructura.
 */
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const RAIZ = path.resolve(__dirname, '..', '..');
const ROOT = 'file://' + RAIZ.replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

// cliente supabase falso: rpc devuelve error "stub"; from() es una cadena thenable que resuelve vacio
const STUB = `
(function(){
  function cadena(){
    var p = new Proxy(function(){}, {
      get: function(_, k){
        if (k === 'then') return function(res){ return Promise.resolve({ data: [], error: null, count: 0 }).then(res); };
        return function(){ return p; };
      },
      apply: function(){ return p; }
    });
    return p;
  }
  window.supabase = { createClient: function(){ return {
    rpc: async function(name){ return { data: null, error: { message: 'stub: ' + name } }; },
    from: function(){ return cadena(); },
    schema: function(){ return this; },
    auth: { getSession: async function(){ return { data: { session: null } }; }, signOut: async function(){} },
    channel: function(){ return { on: function(){ return this; }, subscribe: function(){ return this; } }; }
  }; } };
})();`;

const EXCLUIR = /(^|[\\/])(_backup|node_modules|\.git|tests)([\\/]|$)/;
const paginas = [];
(function walk(dir) {
  for (const f of fs.readdirSync(dir)) {
    const p = path.join(dir, f);
    if (EXCLUIR.test(p)) continue;
    if (fs.statSync(p).isDirectory()) walk(p);
    else if (f.endsWith('_GP2.html') || ['Programa.html', 'Validacion_Stock.html', 'OrdenProduccion.html', 'GP2_MODULOS.html', 'envios-only.html'].includes(f)) paginas.push(p);
  }
})(RAIZ);
paginas.sort();

const RE_HELPER = /(GP2UI|GP2N|GP2EE|GP2M|GP2ConsumoDetalle|GP2Composicion|GP2StockSector|GP2_AUTH|\besc|\$|fmt|hoyAR|fechaAR|exportarCSV|autoMiles|conMiles)\b[^\n]*(is not defined|is not a function)|Cannot read propert[^\n]*\((?:reading )?'(esc|\$|cls|hoyAR|fechaAR|exportarCSV|num|fmt|entero|conMiles|autoMiles|autoMilesEn|abrir|sb|buffer)'\)/;

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  let fallas = 0, avisos = 0;
  for (const p of paginas) {
    const rel = path.relative(RAIZ, p);
    const page = await ctx.newPage();
    const errores = [], faltantes = [];
    page.on('pageerror', e => errores.push(String(e && e.message || e)));
    page.on('requestfailed', r => { const u = r.url(); if (u.startsWith('file://') && /\.(js|css)(\?|$)/.test(u)) faltantes.push(u.replace(ROOT + '/', '').split('?')[0]); });
    await page.route('**/*', r => {
      const u = r.request().url();
      if (/@supabase\/supabase-js/.test(u)) return r.fulfill({ contentType: 'application/javascript', body: STUB });
      if (u.startsWith('file://')) return r.continue();
      return r.abort();              // sin red: fuentes, CDNs, imagenes externas
    });
    try {
      await page.goto(ROOT + '/' + rel.replace(/\\/g, '/'), { waitUntil: 'load', timeout: 15000 });
      await page.waitForTimeout(400);
    } catch (e) { errores.push('goto: ' + e.message.split('\n')[0]); }
    await page.close();
    const graves = errores.filter(m => RE_HELPER.test(m));
    const leves = errores.filter(m => !RE_HELPER.test(m));
    if (faltantes.length || graves.length) {
      fallas++;
      console.log('FAIL ' + rel);
      faltantes.forEach(f => console.log('       falta el archivo: ' + f));
      graves.forEach(m => console.log('       ' + m.split('\n')[0]));
    } else {
      console.log('OK   ' + rel + (leves.length ? '   (aviso: ' + leves[0].split('\n')[0].slice(0, 90) + ')' : ''));
      if (leves.length) avisos++;
    }
  }
  await browser.close();
  console.log((fallas ? 'HAY FALLOS' : 'TODO OK') + ' — ' + paginas.length + ' paginas, ' + fallas + ' con fallos, ' + avisos + ' con avisos de datos');
  if (fallas) process.exitCode = 1;
})();
