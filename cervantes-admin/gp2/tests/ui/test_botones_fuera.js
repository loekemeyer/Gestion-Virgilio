const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
// Raiz del repo (los tests viven en tests/ui/) y Chromium portable si existe.
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);
const BUNDLE = { empleados: { '19': { nombre: 'Eduardo B', activo: true } }, matrices: [], matriz_fleje: {}, matriz_salidas: {}, rollos_saldo: [], rollos_abiertos: {} };
const STUB = `window.supabase={createClient:function(){return{rpc:async function(n){return {data:${JSON.stringify(BUNDLE)},error:null};},from:function(){throw new Error('no');}}}};`;
(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const ok = (c,m)=>{ console.log((c?'OK  ':'FAIL')+' '+m); if(!c) process.exitCode=1; };

  // 1) app operarios: RD/CM/REM fuera, el resto sigue
  let page = await browser.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  await page.route('**/@supabase/supabase-js@2', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.goto(ROOT + '/Produccion/RegistroApp/Operarios_GP2.html');
  await page.fill('#legajoInput', '19');
  await page.click('#btnContinuar');
  await page.waitForSelector('.box[data-code="E"]');
  const codes = await page.$$eval('.box', xs => xs.map(x => x.dataset.code));
  ok(!codes.includes('RD') && !codes.includes('CM') && !codes.includes('REM'), 'RD/CM/REM fuera: ' + codes.join(','));
  ['E','C','PB','BC','MOV','LIMP','Perm','AL','PR','PC','MOV P','PM','RM','CT'].forEach(c =>
    ok(codes.includes(c), 'sigue ' + c));
  await page.close();

  // 2) menu: sin Stock Online / Informes Virgilio / Prov AT candados
  const fakeJwt = () => {
    const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64').replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
    return b64({alg:'none'})+'.'+b64({exp: Math.floor(Date.now()/1000)+3600})+'.x';
  };
  const ctx = await browser.newContext();
  page = await ctx.newPage();
  await page.addInitScript(jwt => {
    sessionStorage.setItem('gp_auth','ok'); sessionStorage.setItem('gp_role','admin');
    localStorage.setItem('sb-test-auth-token', JSON.stringify({access_token: jwt}));
  }, fakeJwt());
  await page.goto(ROOT + '/GP2_MODULOS.html');
  await page.waitForSelector('.card');
  const t = await page.textContent('body');
  ok(!t.includes('Stock Online'), 'sin Stock Online duplicado');
  ok(!t.includes('Informes Virgilio'), 'sin Informes Virgilio');
  ok(!t.includes('Entrega Art. Terminado'), 'sin Entrega Art. Terminado');
  const provAT = await page.$$eval('.card', cards => {
    const c = cards.find(x => x.textContent.includes('Prov. Art. Terminado'));
    return c ? c.textContent : '';
  });
  // El grupo arranco con un candado "Control" a la app vieja, que se saco en
  // v1.23.0 ("el online ya esta en Stocks General"). Desde 2026-08-30 hay un
  // modulo GP2 propio (ControlAT_GP2.html), asi que Control vuelve — pero como
  // pantalla GP2, no como candado. Lo que el test cuida es eso ultimo.
  ok(provAT.includes('Envío Cartón/Cajas'), 'Prov AT conserva Envío Cartón/Cajas');
  ok(!/🔒/.test(provAT), 'Prov AT sin candados a la app vieja: ' + provAT.replace(/\s+/g,' ').trim());
  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
