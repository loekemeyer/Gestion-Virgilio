const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT_DIR = path.resolve(__dirname, '..', '..');
const ROOT = 'file://' + ROOT_DIR.replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

/* Que el icono de la app llegue al telefono.
   iOS NO usa el manifest para "Agregar a inicio": usa <link rel="apple-touch-icon">.
   Cuando index.html y login.html no lo tenian, iOS se inventaba un cuadrado negro
   con una "G" (2026-08-29). Este test evita que vuelva a pasar en silencio. */

// Paginas desde las que alguien puede agregar la app a la pantalla de inicio.
// index.html es un redirector (se va solo antes de poder inspeccionar el DOM),
// asi que ese se chequea sobre el fuente.
const ENTRADAS = ['GP2_MODULOS.html', 'login.html', 'envios-only.html'];

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) process.exitCode = 1; };

  // index.html: chequeo sobre el archivo, es la pagina que arranca la app
  const idx = fs.readFileSync(path.join(ROOT_DIR, 'index.html'), 'utf8');
  ok(/rel="apple-touch-icon"[^>]*apple-touch-icon\.png/.test(idx),
     'index.html: declara el apple-touch-icon en el <head>');
  ok(/rel="manifest"/.test(idx), 'index.html: declara el manifest');

  for (const pagina of ENTRADAS) {
    const ctx = await browser.newContext();
    const page = await ctx.newPage();
    // el login apagado hace que index redirija; se corta la navegacion para
    // poder inspeccionar el <head> de la pagina pedida
    await page.route('**/*', r => {
      const u = r.request().url();
      if (r.request().isNavigationRequest() && !u.includes(pagina)) return r.abort();
      return r.continue();
    });
    await page.goto(ROOT + '/' + pagina).catch(() => {});
    await page.waitForTimeout(400);   // pwa.js inyecta lo que falte

    const head = await page.evaluate(() => ({
      ati: (document.querySelector('link[rel="apple-touch-icon"]') || {}).getAttribute
        ? document.querySelector('link[rel="apple-touch-icon"]').getAttribute('href') : null,
      manifest: (document.querySelector('link[rel="manifest"]') || {}).getAttribute
        ? document.querySelector('link[rel="manifest"]').getAttribute('href') : null,
    }));

    ok(!!head.ati, pagina + ': tiene apple-touch-icon (' + head.ati + ')');
    ok(!!head.manifest, pagina + ': tiene manifest');
    // el favicon viejo NO sirve de icono de app: trae esquinas redondeadas dibujadas
    ok(!/GP2_favicon/.test(head.ati || ''), pagina + ': el apple-touch-icon no es el favicon viejo');
    await ctx.close();
  }

  // los archivos que las paginas prometen tienen que existir de verdad
  const manifest = JSON.parse(fs.readFileSync(path.join(ROOT_DIR, 'manifest.json'), 'utf8'));
  for (const ic of manifest.icons) {
    const rel = ic.src.split('?')[0];
    ok(fs.existsSync(path.join(ROOT_DIR, rel)), 'existe ' + rel + ' (' + ic.purpose + ')');
  }
  ok(fs.existsSync(path.join(ROOT_DIR, 'apple-touch-icon.png')), 'existe apple-touch-icon.png');
  ok(manifest.icons.some(i => i.purpose === 'maskable'), 'el manifest declara un icono maskable');
  // sin ?v= los telefonos se quedan con el icono viejo cacheado para siempre
  ok(manifest.icons.every(i => i.src.includes('?v=')), 'los iconos del manifest llevan token de version');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
