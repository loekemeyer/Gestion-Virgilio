const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
// Raiz del repo (los tests viven en tests/ui/) y Chromium portable si existe.
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);
const BUNDLE = {
  paq: 250, insumos: [],
  ocs: [ { id: 9, numero: 1, proveedor: 'Basconia', rubro: 'Fleje', estado: 'enviada', nota: 'urgente',
    creado_en: '2026-08-29T10:00:00Z',
    // Asi la manda oc_bundle: la columna se llama fecha_entrega_estimada. La pantalla leia
    // o.fecha_entrega y la fecha se perdia (idea 7271, y ya habia pasado en v1.18.0).
    fecha_entrega_estimada: '2026-09-20',
    total_usd: 750, total_ars: 12000,
    items: [ { codigo: 'A1', descripcion: 'Fleje N 13', cantidad: 500, unidad: 'kg', recibido: 0,
               precio_uni: 1.5, moneda: 'USD', subtotal: 750 },
             { codigo: 'CAJ1', descripcion: 'Caja 12', cantidad: 12, unidad: 'uni', recibido: 0,
               precio_uni: 1000, moneda: 'ARS', subtotal: 12000 } ] } ],
};
const STUB = `
window.supabase = { createClient: function(){ return {
  rpc: async function(name, args){
    if(name==='oc_bundle') return { data: ${JSON.stringify(BUNDLE)}, error: null };
    return { data: { ok: true }, error: null };
  }
};}};
`;
(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
  await page.route('**/@supabase/supabase-js@2', r => r.fulfill({ contentType: 'application/javascript', body: STUB }));
  await page.route('**/gp2-modulo.css**', r => r.fulfill({ contentType: 'text/css', body: '.hidden{display:none!important}' }));
  await page.route('**/GP2_favicon.png', r => r.fulfill({ contentType: 'image/png', body: Buffer.from('') }));
  await page.goto(ROOT + '/Compras/OC_GP2.html');
  await page.waitForFunction(() => document.getElementById('status').textContent === '');
  const ok = (c, m) => { console.log((c?'OK  ':'FAIL')+' '+m); if(!c) process.exitCode = 1; };
  await page.click('#tabOcs');
  ok(await page.$('.oc-acts button.imp') !== null, 'boton imprimir presente');
  // La fecha de entrega llega como fecha_entrega_estimada y tiene que verse en la tarjeta.
  const tarjeta = await page.textContent('.oc-card');
  ok(tarjeta.includes('Entrega 20/09/2026'), 'fecha de entrega en la tarjeta de la OC');
  // stub print en las ventanas nuevas para que no bloquee
  await ctx.addInitScript(() => { window.print = () => { window.__printed = true; }; });
  const [pop] = await Promise.all([ ctx.waitForEvent('page'), page.click('.oc-acts button.imp') ]);
  await pop.waitForFunction(() => document.body && document.body.textContent.includes('Orden de Compra'));
  const txt = await pop.textContent('body');
  ok(txt.includes('Orden de Compra N° 1') && txt.includes('Basconia') && txt.includes('A1') && txt.includes('500') && txt.includes('urgente'),
     'hoja de impresion completa');
  // precios en la hoja del proveedor: unitario, subtotales por moneda y total mixto
  ok(txt.includes('Precio unit.') && txt.includes('US$ 1,5') && txt.includes('US$ 750'),
     'precio unitario y subtotal USD impresos');
  ok(txt.includes('$ 1.000') && txt.includes('$ 12.000'), 'precio y subtotal en pesos impresos');
  ok(txt.includes('Total: US$ 750 + $ 12.000'), 'total mixto impreso (US$ + $ separados)');
  // La hoja que va al proveedor tiene que llevar la fecha, no la linea en blanco para completar.
  ok(txt.includes('20/09/2026'), 'fecha de entrega impresa en la hoja del proveedor');
  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
