// El selector de "¿Qué necesito para producir?" va en UN SOLO PASO: se abre en el buscador
// con TODOS los articulos a la vista (usuario 2026-09-23: "no me hagas elegir por marca, que
// el buscador aparezca en todas directamente"). La marca quedo como filtro opcional en chips
// y arranca en "Todas" en cada apertura. La lista agrupa por familia y muestra la DESCRIPCION,
// no la familia repetida. El <select id="art"> sigue existiendo oculto: es el modelo que lee
// el resto de la pantalla.
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

  // UN SOLO PASO: al tocar Articulo estan el buscador y los articulos, sin pedir marca
  await page.click('#artBtn');
  check(await page.isVisible('#buscar'), 'el buscador aparece apenas se abre el panel');
  const primeros = await page.$$eval('#pickList button[data-id]', bs => bs.map(b => b.textContent.trim().split(' ')[0]));
  // 4 y no 5: el fixture tiene 5 articulos y uno esta discontinuado
  check(primeros.length === 4, 'abre en TODAS las marcas, sin elegir nada — ' + primeros.join(','));
  check(await page.$('#pickBack') === null, 'ya no hay boton de volver: no hay paso previo');
  const tit = await page.$eval('#pickTit', e => e.textContent);
  check(/artículo/i.test(tit) && !/marca/i.test(tit), 'el titulo pide el articulo, no la marca — ' + tit.trim());

  // los chips de marca son un filtro opcional, arrancan en Todas y estan DENTRO del panel de articulos
  const chips = await page.$$eval('#pickMarcas button', bs => bs.map(b => b.textContent.trim()));
  check(JSON.stringify(chips) === JSON.stringify(['Todas', 'Loeke', 'Loke', 'Chef']),
    'los chips de marca quedan como filtro — ' + chips.join(' / '));
  const chipOn = await page.$$eval('#pickMarcas button.on', bs => bs.map(b => b.textContent.trim()));
  check(JSON.stringify(chipOn) === JSON.stringify(['Todas']), 'arranca en Todas — ' + chipOn.join(','));
  check(await page.$eval('#pickMarcas', e => e.closest('#pickArts') !== null),
    'los chips viven adentro del panel de articulos, no en una pantalla aparte');

  const grupos = await page.$$eval('#pickList .fam', gs => gs.map(g => g.textContent));
  check(JSON.stringify(grupos) === JSON.stringify(['Abrelatas', 'Peladores', 'Sacacorchos']),
    'la lista se agrupa por familia — ' + grupos.join(' / '));

  const txt501 = await page.$eval('#pickList button[data-id="25"]', o => o.textContent);
  check(/Abrelatas A Manija/.test(txt501) && !/—\s*Abrelatas\s*$/.test(txt501),
    'la fila muestra la descripcion, no la familia — ' + txt501.trim());

  // 2026-09-23 [usuario: "lo discontinuado no quiero seguir viendolo en el programa"]:
  // el 809 del fixture es discontinuado, asi que su familia (Cortadores) tampoco aparece.
  const hay809 = await page.$('#pickList button[data-id="77"]');
  check(hay809 === null, 'el discontinuado NO aparece en la lista');
  const opts = await page.$$eval('#art option', os => os.map(o => o.value));
  check(!opts.includes('77'), 'el discontinuado tampoco esta en el select — ' + opts.join(','));
  const rot = await page.$eval('#pickList', e => e.textContent);
  check(!/discontinuado/i.test(rot), 'no queda el rotulo "(discontinuado)" en ninguna fila');

  // el boton lleva la flechita de desplegar
  const caret = await page.$eval('#artBtn .caret', e => e.textContent.trim());
  check(caret === '▾', 'el boton tiene la flecha de desplegar — ' + caret);

  // el chip filtra en el acto, sin cerrar ni cambiar de pantalla
  const porMarca = async (mk) => {
    await page.click(`#pickMarcas button[data-mk="${mk}"]`);
    return page.$$eval('#pickList button[data-id]', bs => bs.map(b => b.textContent.trim().split(' ')[0]));
  };
  const cods = await porMarca('CHEF');
  check(JSON.stringify(cods) === JSON.stringify(['701']), 'el chip Chef deja solo el 701 — ' + cods.join(','));
  check(await page.isVisible('#buscar'), 'con la marca filtrada el buscador sigue a la vista');
  const onChip = await page.$$eval('#pickMarcas button.on', bs => bs.map(b => b.textContent.trim()));
  check(JSON.stringify(onChip) === JSON.stringify(['Chef']), 'el chip elegido queda marcado — ' + onChip.join(','));

  const cods2 = await porMarca('LOEKE');
  check(JSON.stringify(cods2) === JSON.stringify(['501', '520']), 'el chip Loeke deja 501 y 520 — ' + cods2.join(','));

  const cods3 = await porMarca('LOKE');
  check(JSON.stringify(cods3) === JSON.stringify(['108']), 'Loke es una marca propia, no se mezcla con Loeke — ' + cods3.join(','));

  const cods4 = await porMarca('');
  check(cods4.length === 4, 'Todas vuelve a los 4 vivos — ' + cods4.length);

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

  await page.click('#pickMarcas button[data-mk="LOEKE"]');
  const b4 = await page.$$eval('#pickList button[data-id]', os => os.length);
  const b4txt = await page.$eval('#pickList', e => e.textContent);
  check(b4 === 0 && /ningún artículo/.test(b4txt),
    'el chip no borra lo tipeado: buscador y marca se combinan — ' + b4 + ' filas');

  // al reabrir, el filtro NO queda pegado: vuelve a Todas y con el buscador limpio
  await page.click('#pickX');
  await page.click('#artBtn');
  const reabre = await page.$$eval('#pickList button[data-id]', bs => bs.length);
  const buscado = await page.$eval('#buscar', e => e.value);
  check(reabre === 4 && buscado === '',
    'al reabrir vuelve a Todas y sin busqueda pegada — ' + reabre + ' filas, buscador="' + buscado + '"');

  await page.click('#pickList button[data-id="25"]');
  check(await page.isHidden('#pick'), 'al elegir el articulo el panel se cierra');
  const rotulo2 = await page.$eval('#artBtn', b => b.textContent);
  check(/501/.test(rotulo2), 'el boton se actualiza con lo elegido — ' + rotulo2.trim());
  const hero = await page.$eval('.hero .fam', e => e.textContent);
  check(/Abrelatas A Manija/.test(hero) && /LOEKE/.test(hero),
    'el encabezado muestra descripcion, familia y marca — ' + hero.trim());

  // los chips tienen que seguir siendo tocables en 390px y no empujar la pagina
  const altoChip = await page.evaluate(() => {
    document.getElementById('artBtn').click();
    const b = document.querySelector('#pickMarcas button');
    return b.getBoundingClientRect().height;
  });
  check(altoChip >= 44, 'los chips de marca son tocables (>=44px) — ' + Math.round(altoChip) + 'px');

  const ovf = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  check(ovf <= 0, 'sin scroll horizontal en 390px (overflow=' + ovf + ')');

  await browser.close();
  if (ok.every(Boolean)) { console.log('TODO OK'); process.exit(0); }
  process.exit(1);
})().catch(e => { console.error(e); process.exit(1); });
