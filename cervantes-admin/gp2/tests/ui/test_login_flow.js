const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
// Raiz del repo (los tests viven en tests/ui/) y Chromium portable si existe.
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

// El login se prende/apaga con GP2_AUTH_ON en auth-guard.js. El test prueba
// LAS DOS POSICIONES del interruptor: sirve hoy (apagado) y el dia que se vuelva
// a prender, sin tener que reescribirlo.
const GUARD = fs.readFileSync(path.resolve(__dirname, '..', '..', 'auth-guard.js'), 'utf8');
const REAL_ON = /^\s*var GP2_AUTH_ON\s*=\s*true\s*;/m.test(GUARD);
// Sirve el auth-guard real con el interruptor forzado a la posicion que se prueba.
const guardCon = on => GUARD.replace(/var GP2_AUTH_ON\s*=\s*(true|false)\s*;/,
                                     'var GP2_AUTH_ON = ' + on + ';');

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const ok = (c,m)=>{ console.log((c?'OK  ':'FAIL')+' '+m); if(!c) process.exitCode=1; };

  const fakeJwt = () => {
    const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
    return b64({alg:'none'})+'.'+b64({exp: Math.floor(Date.now()/1000)+3600})+'.x';
  };
  const nuevoCtx = async (on) => {
    const ctx = await browser.newContext();
    await ctx.route('**/auth-guard.js*', r =>
      r.fulfill({ contentType: 'application/javascript', body: guardCon(on) }));
    return ctx;
  };
  const logueado = async (page) => page.addInitScript(jwt => {
    sessionStorage.setItem('gp_auth','ok'); sessionStorage.setItem('gp_role','admin');
    localStorage.setItem('sb-test-auth-token', JSON.stringify({access_token: jwt}));
  }, fakeJwt());

  console.log('-- interruptor APAGADO (GP2_AUTH_ON=false): se entra suelto');

  // 1) sin ninguna sesion, el menu abre igual (antes pateaba a login)
  let ctx = await nuevoCtx(false);
  let page = await ctx.newPage();
  await page.goto(ROOT + '/GP2_MODULOS.html');
  await page.waitForSelector('.card');
  ok(page.url().includes('GP2_MODULOS'), 'sin login el menu abre igual');
  ok((await page.$$eval('.card', x => x.length)) > 8,
     'menu renderizado (' + (await page.$$eval('.card', x=>x.length)) + ' grupos)');
  // sin sesion no hay nada que cerrar: el link no se muestra
  ok(await page.$eval('#sesion', e => e.hidden) === true, 'Cerrar sesion oculto');
  await ctx.close();

  // 2) el entry point manda derecho al menu, sin pasar por login
  ctx = await nuevoCtx(false);
  page = await ctx.newPage();
  await page.goto(ROOT + '/index.html');
  await page.waitForURL(/GP2_MODULOS\.html/);
  ok(!page.url().includes('login'), 'index.html entra directo al menu, no al login');
  await ctx.close();

  console.log('-- interruptor PRENDIDO (GP2_AUTH_ON=true): vuelve a pedir login');

  // 3) sin login patea a login.html
  ctx = await nuevoCtx(true);
  page = await ctx.newPage();
  await page.goto(ROOT + '/GP2_MODULOS.html');
  await page.waitForURL(/login\.html/);
  ok(page.url().includes('login.html'), 'sin login -> login.html');
  await ctx.close();

  // 4) logueado se queda en el menu y ve Cerrar sesion
  ctx = await nuevoCtx(true);
  page = await ctx.newPage();
  await logueado(page);
  await page.goto(ROOT + '/GP2_MODULOS.html');
  await page.waitForSelector('.card');
  ok(page.url().includes('GP2_MODULOS'), 'logueado se queda en el menu');
  ok(await page.$eval('#sesion', e => e.hidden) === false, 'Cerrar sesion visible');
  ok(await page.$('a[href="login.html?logout=1"]') !== null, 'link de logout presente');
  await ctx.close();

  // 5) la landing vieja sigue redirigiendo al menu
  ctx = await nuevoCtx(true);
  page = await ctx.newPage();
  await logueado(page);
  await page.goto(ROOT + '/Inicio/index.html');
  await page.waitForURL(/GP2_MODULOS\.html/);
  ok(page.url().includes('GP2_MODULOS.html'), 'landing vieja redirige al menu');
  await ctx.close();

  // 6) el archivo del repo dice lo que creemos que dice
  console.log('-- estado real del repo');
  ok(REAL_ON === false, 'auth-guard.js tiene el login APAGADO (GP2_AUTH_ON=false)');

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
