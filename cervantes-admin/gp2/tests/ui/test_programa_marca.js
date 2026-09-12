// El selector de "¿Qué necesito para producir?" va en DOS PASOS: primero la marca
// (Loeke / Loke / Chef / Todas) y despues el articulo. La lista agrupa por familia y
// muestra la DESCRIPCION, no la familia repetida. El <select id="art"> sigue existiendo
// oculto: es el modelo que lee el resto de la pantalla.
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

const B = {
  art: [
    { id: 25, cod: '501', fam: 'Abrelatas',   d: 'Abrelatas A Manija',  mk: 'LOEKE', disc: false },
    { id: 64, cod: '701', fam: 'Abrelatas',   d: 'Abrelatas A Manija',  mk: 'CHEF',  disc: false },
    { id: 40, cod: '520', fam: 'Sacacorchos', d: 'Sacacorcho Tipo Mozo Cromado', mk: 'LOEKE', disc: false },
    { id: 13, cod: '108', fam: 'Peladores',   d: 'Pelapapas Mango Metálico', mk: 'LOKE', disc: false },
    { id: 77, cod: '809', fam: 'Cortadores',  d: null,                  mk: null,    disc: true },
  ],
  sect: { '12': { t: 'terminado' } },
  comp: { '412': { cod: '501', d: '501 Terminado', s: 12 } },
  mat: {}, prov: {}, tall: {}, bom: [], children: {}, tall_art: {},
  rp: {}, rutas: [], rutas_by_art: {},
};

const ok = [];
function check(cond, msg) { console.log((cond ? 'OK   ' : 'FALLA ') + msg); ok.push(!!cond); }

(async () => {
  const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name){ if(name==='programa_bundle') return { data: ${JSON.stringify(B)}, error:null };
    return { data:null, error:{message:'rpc '+name} }; },
  from: function(){ var o={}; ['select','eq','order','single'].forEach(m=>o[m]=()=>o);
    o.then=(r)=>Promise.resolve({data:[],error:null}).then(r); return o; }
};}};`;

  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const page = await browser.newPage({ viewport: { width: 390, height: 800 } });
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  await page.route('**/@supabase/supabase-js@2', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/*.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));
  await page.goto(ROOT + '/Programa/Programa.html');
  await page.waitForSelector('#art option', { state: 'attached' });

  // el boton de articulo muestra el elegido y el panel arranca cerrado
  const rotulo = await page.$eval('#artBtn', b => b.textContent);
  check(/501/.test(rotulo) && /Abrelatas A Manija/.test(rotulo),
    'el boton muestra el articulo elegido — ' + rotulo.trim());
  check(await page.isHidden('#pick'), 'el panel arranca cerrado');

  // paso 1: al tocar Articulo aparecen las marcas, no los articulos
  await page.click('#artBtn');
  const marcas = await page.$$eval('#pickMarcas button', bs => bs.map(b => b.textContent.trim()));
  check(JSON.stringify(marcas) === JSON.stringify(['Loeke', 'Loke', 'Chef', 'Todas']),
    'paso 1: primero se elige la marca — ' + marcas.join(' / '));
  check(await page.isHidden('#pickArts'), 'paso 1: los articulos todavia no se despliegan');

  // helper: elegir marca y leer los codigos que quedan
  const porMarca = async (mk) => {
    if (await page.isHidden('#pickMarcas')) await page.click('#pickBack');
    await page.click(`#pickMarcas button[data-mk="${mk}"]`);
    return page.$$eval('#pickList button[data-id]', bs => bs.map(b => b.textContent.trim().split(' ')[0]));
  };

  await porMarca('');
  const grupos = await page.$$eval('#pickList .fam', gs => gs.map(g => g.textContent));
  check(JSON.stringify(grupos) === JSON.stringify(['Abrelatas', 'Cortadores', 'Peladores', 'Sacacorchos']),
    'paso 2: la lista se agrupa por familia — ' + grupos.join(' / '));

  const txt501 = await page.$eval('#pickList button[data-id="25"]', o => o.textContent);
  check(/Abrelatas A Manija/.test(txt501) && !/—\s*Abrelatas\s*$/.test(txt501),
    'la fila muestra la descripcion, no la familia — ' + txt501.trim());

  const txt809 = await page.$eval('#pickList button[data-id="77"]', o => o.textContent);
  check(/discontinuado/.test(txt809), 'el discontinuado se avisa en la fila — ' + txt809.trim());

  // el boton lleva la flechita de desplegar
  const caret = await page.$eval('#artBtn .caret', e => e.textContent.trim());
  check(caret === '\u25be', 'el boton tiene la flecha de desplegar — ' + caret);

  const cods = await porMarca('CHEF');
  check(JSON.stringify(cods) === JSON.stringify(['701']), 'eligiendo Chef queda solo el 701 — ' + cods.join(','));
  const tit = await page.$eval('#pickTit', e => e.textContent);
  check(/Chef/.test(tit), 'el panel dice que marca se eligio — ' + tit.trim());

  const cods2 = await porMarca('LOEKE');
  check(JSON.stringify(cods2) === JSON.stringify(['501', '520']), 'eligiendo Loeke quedan 501 y 520 — ' + cods2.join(','));

  const cods3 = await porMarca('LOKE');
  check(JSON.stringify(cods3) === JSON.stringify(['108']), 'Loke es una marca propia, no se mezcla con Loeke — ' + cods3.join(','));

  const cods4 = await porMarca('');
  check(cods4.length === 5, 'Todas vuelve a los 5 — ' + cods4.length);

  // filtrar NO mueve el articulo elegido: nada resaltado salvo el que se eligio de verdad
  const onTodas = await page.$$eval('#pickList button.on', bs => bs.map(b => b.textContent.trim().split(' ')[0]));
  check(JSON.stringify(onTodas) === JSON.stringify(['501']), 'solo se resalta el elegido de verdad — ' + onTodas.join(','));
  for (const mk of ['LOEKE', 'CHEF', 'LOKE']) {
    await porMarca(mk);
    const on = await page.$$eval('#pickList button.on', bs => bs.map(b => b.textContent.trim().split(' ')[0]));
    const val = await page.$eval('#art', e => e.value);
    check(JSON.stringify(on) === JSON.stringify(mk === 'LOEKE' ? ['501'] : []) && val === '25',
      'filtrar por ' + mk + ' no resalta ni cambia el elegido — resaltado=[' + on.join(',') + '] art=' + val);
  }
  await porMarca('');

  // buscador: por descripcion, por codigo, sin acentos, y combinado con la marca
  await page.fill('#buscar', 'pelapapas');
  const b1 = await page.$$eval('#pickList button[data-id]', os => os.map(o => o.textContent.trim().split(' ')[0]));
  check(JSON.stringify(b1) === JSON.stringify(['108']), 'busca por descripcion — ' + b1.join(','));

  await page.fill('#buscar', 'sacacorcho');
  const b2 = await page.$$eval('#pickList button[data-id]', os => os.map(o => o.textContent.trim().split(' ')[0]));
  check(JSON.stringify(b2) === JSON.stringify(['520']), 'busca sin acentos ni mayusculas — ' + b2.join(','));

  await page.fill('#buscar', '70');
  const b3 = await page.$$eval('#pickList button[data-id]', os => os.map(o => o.textContent.trim().split(' ')[0]));
  check(JSON.stringify(b3) === JSON.stringify(['701']), 'busca por codigo — ' + b3.join(','));

  await page.click('#pickBack');
  await page.click('#pickMarcas button[data-mk="LOEKE"]');
  await page.fill('#buscar', '70');
  const b4 = await page.$$eval('#pickList button[data-id]', os => os.length);
  const b4txt = await page.$eval('#pickList', e => e.textContent);
  check(b4 === 0 && /ningún artículo/.test(b4txt), 'buscador y marca se combinan — ' + b4 + ' filas');

  await page.fill('#buscar', '');
  await page.click('#pickList button[data-id="25"]');
  check(await page.isHidden('#pick'), 'al elegir el articulo el panel se cierra');
  const rotulo2 = await page.$eval('#artBtn', b => b.textContent);
  check(/501/.test(rotulo2), 'el boton se actualiza con lo elegido — ' + rotulo2.trim());
  const hero = await page.$eval('.hero .fam', e => e.textContent);
  check(/Abrelatas A Manija/.test(hero) && /LOEKE/.test(hero),
    'el encabezado muestra descripcion, familia y marca — ' + hero.trim());

  const ovf = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  check(ovf <= 0, 'sin scroll horizontal en 390px (overflow=' + ovf + ')');

  await browser.close();
  if (ok.every(Boolean)) { console.log('TODO OK'); process.exit(0); }
  process.exit(1);
})().catch(e => { console.error(e); process.exit(1); });
