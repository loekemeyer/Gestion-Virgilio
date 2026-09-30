const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
// Raiz del repo (los tests viven en tests/ui/) y Chromium portable si existe.
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

// El login se prende/apaga con GP2_AUTH_ON en auth-guard.js. El test prueba
// LAS DOS POSICIONES del interruptor. Desde el 2026-09-28 el repo lo tiene PRENDIDO
// (seguridad punto 1, fase A) y el test fija ademas que un token de acceso vencido
// NO desloguea (el bug que obligaba a entrar con Google cada hora) y que el ?next=
// del login solo sigue rutas propias.
const GUARD = fs.readFileSync(path.resolve(__dirname, '..', '..', 'auth-guard.js'), 'utf8');
const REAL_ON = /^\s*var GP2_AUTH_ON\s*=\s*true\s*;/m.test(GUARD);
// Sirve el auth-guard real con el interruptor forzado a la posicion que se prueba.
// GP2_GUARD_EN_FILE: el guard ignora file:// (asi abren los tests); aca se lo obliga a actuar.
const guardCon = on => 'window.GP2_GUARD_EN_FILE = true;\n' +
                       GUARD.replace(/var GP2_AUTH_ON\s*=\s*(true|false)\s*;/, 'var GP2_AUTH_ON = ' + on + ';');

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const ok = (c,m)=>{ console.log((c?'OK  ':'FAIL')+' '+m); if(!c) process.exitCode=1; };

  const fakeJwt = (segs = 3600) => {
    const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
    return b64({alg:'none'})+'.'+b64({exp: Math.floor(Date.now()/1000)+segs})+'.x';
  };
  const nuevoCtx = async (on) => {
    const ctx = await browser.newContext();
    await ctx.route('**/auth-guard.js*', r =>
      r.fulfill({ contentType: 'application/javascript', body: guardCon(on) }));
    return ctx;
  };
  // Sesion como la guarda supabase-js v2: access_token (dura 1 h) + refresh_token.
  const logueado = async (page, segs = 3600, conPestana = true) => page.addInitScript(([jwt, pest]) => {
    if (pest) { sessionStorage.setItem('gp_auth','ok'); sessionStorage.setItem('gp_role','admin'); }
    localStorage.setItem('sb-hrxfctzncixxqmpfhskv-auth-token', JSON.stringify({access_token: jwt, refresh_token: 'r-test'}));
  }, [fakeJwt(segs), conPestana]);

  console.log('-- interruptor APAGADO (GP2_AUTH_ON=false): se entra suelto');

  // 1) sin ninguna sesion, el menu abre igual (antes pateaba a login)
  let ctx = await nuevoCtx(false);
  let page = await ctx.newPage();
  await page.goto(ROOT + '/GP2_MODULOS.html');
  await page.waitForSelector('.card');
  ok(page.url().includes('GP2_MODULOS'), 'sin login el menu abre igual');
  ok((await page.$$eval('.card', x => x.length)) === 2,   // v1.196.0: Stocks + Herramientas
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

  // 3) sin login patea a login.html, y le dice a donde volver (?next=)
  ctx = await nuevoCtx(true);
  page = await ctx.newPage();
  await page.goto(ROOT + '/GP2_MODULOS.html');
  await page.waitForURL(/login\.html/);
  ok(page.url().includes('login.html'), 'sin login -> login.html');
  ok(decodeURIComponent(new URL(page.url()).searchParams.get('next') || '').endsWith('/GP2_MODULOS.html'),
     'el login sabe a que pantalla volver (?next=)');
  await ctx.close();

  // 3b) EL BUG DE LA HORA: token de acceso VENCIDO pero con refresh_token -> se queda.
  //     El guard viejo deslogueaba aca y obligaba a entrar con Google cada hora.
  ctx = await nuevoCtx(true);
  page = await ctx.newPage();
  await logueado(page, -600);
  await page.goto(ROOT + '/GP2_MODULOS.html');
  await page.waitForSelector('.card');
  ok(page.url().includes('GP2_MODULOS'), 'token de acceso vencido NO desloguea (lo renueva el cliente)');
  await ctx.close();

  // 3c) pestana nueva (sin sessionStorage) pero con sesion guardada -> pasa por login a
  //     revalidar el rol, con ?next= para volver, sin logout.
  ctx = await nuevoCtx(true);
  page = await ctx.newPage();
  await logueado(page, 3600, false);
  await page.goto(ROOT + '/GP2_MODULOS.html');
  await page.waitForURL(/login\.html/);
  ok(!/logout=1/.test(page.url()) && /next=/.test(page.url()), 'pestana nueva: revalida en login y vuelve, sin cerrar la sesion');
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
  ok(REAL_ON === true, 'auth-guard.js tiene el login PRENDIDO (GP2_AUTH_ON=true, desde el 2026-09-28)');

  // 7) login.html vuelve a la pantalla de origen, pero SOLO a rutas propias.
  //    Supabase stubeado: hay sesion y la whitelist contesta "admin".
  console.log('-- login.html: ?next= seguro');
  const STUB_LOGIN = `window.supabase={createClient:function(){return{
    auth:{getSession:async function(){return{data:{session:{user:{email:'a@b.c'}}}}},
          onAuthStateChange:function(){},signOut:async function(){}},
    schema:function(){return{rpc:async function(){return{data:'admin',error:null}}}}}}};`;
  const irLogin = async (next) => {
    const c = await nuevoCtx(true);
    await c.route('**/*', r => {
      const u = r.request().url();
      if (/supabase-js/.test(u)) return r.fulfill({ contentType: 'application/javascript', body: STUB_LOGIN });
      if (/auth-guard\.js/.test(u)) return r.fulfill({ contentType: 'application/javascript', body: guardCon(true) });
      if (u.startsWith('file://')) return r.continue();
      return r.abort();
    });
    const pg = await c.newPage();
    await logueado(pg, 3600, false);
    await pg.goto(ROOT + '/login.html?next=' + encodeURIComponent(next));
    await pg.waitForTimeout(1500);
    const url = pg.url(); await c.close(); return url;
  };
  const destino = new URL(ROOT + '/Faltantes/Faltantes_GP2.html').pathname;
  ok((await irLogin(destino)).endsWith('/Faltantes/Faltantes_GP2.html'), 'login vuelve a la pantalla de origen');
  ok((await irLogin('//evil.example/x')).includes('GP2_MODULOS.html'), '"//otro-sitio" NO se sigue: va al menu');
  ok((await irLogin('https://evil.example/x')).includes('GP2_MODULOS.html'), '"https://otro-sitio" NO se sigue: va al menu');

  // 8) 29/09: la sesion de OTRA app del mismo origen (github.io, otro proyecto Supabase)
  //    no cuenta como sesion GP2.
  console.log('-- sesion ajena y sesion caida');
  ctx = await nuevoCtx(true);
  page = await ctx.newPage();
  await page.addInitScript(() => {
    sessionStorage.setItem('gp_auth','ok'); sessionStorage.setItem('gp_role','admin');
    localStorage.setItem('sb-otroproyecto-auth-token', JSON.stringify({access_token:'x', refresh_token:'r'}));
  });
  await page.goto(ROOT + '/GP2_MODULOS.html');
  await page.waitForURL(/login\.html/);
  ok(page.url().includes('login.html'), 'token de otro proyecto Supabase NO deja pasar -> login');
  await ctx.close();

  // 9) 29/09: la sesion se cae con la pantalla abierta (refresh_token invalido ->
  //    SIGNED_OUT de supabase-js) -> vuelve al login, no sigue como anonimo.
  const STUB_SB = `window.supabase={createClient:function(){return{
    auth:{onAuthStateChange:function(cb){window.__authCb=cb;}},
    rpc:async function(){return{data:null,error:null}},
    from:function(){var q={select:function(){return q},eq:function(){return q},order:function(){return q},
      then:function(r){return Promise.resolve({data:[],error:null}).then(r)}};return q}}}};`;
  ctx = await nuevoCtx(true);
  await ctx.route('**/supabase-js*', r => r.fulfill({ contentType: 'application/javascript', body: STUB_SB }));
  page = await ctx.newPage();
  await logueado(page);
  await page.goto(ROOT + '/GP2_MODULOS.html');
  await page.waitForSelector('.card');
  ok(await page.evaluate(() => typeof window.__authCb === 'function'), 'GP2_SB escucha los cambios de sesion');
  await page.evaluate(() => window.__authCb('SIGNED_OUT', null));
  await page.waitForURL(/login\.html/);
  ok(/next=/.test(page.url()), 'sesion caida -> login, con ?next= para volver');
  await ctx.close();

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
