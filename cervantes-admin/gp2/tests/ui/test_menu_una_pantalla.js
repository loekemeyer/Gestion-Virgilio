const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const ROOT = 'file://' + path.resolve(__dirname, '..', '..').replace(/\\/g, '/');
const EXE = process.env.CHROMIUM_PATH || (fs.existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

/* Requisito del usuario (2026-08-29): en el celular los grupos del menu tienen que
   entrar TODOS en una sola pantalla, con botones grandes y legibles, y sin texto que
   no sea un modulo. Este test lo fija: si manana alguien agrega un grupo o agranda
   algo y deja de entrar, salta aca en vez de descubrirlo en el telefono. */

const PANTALLAS = [
  { nom: 'iPhone 14 (app)', w: 390, h: 790 },   // instalada: sin barra del navegador
  { nom: 'pantalla baja',   w: 375, h: 600 },   // SE, o el navegador con su barra
];

(async () => {
  const browser = await chromium.launch(EXE ? { executablePath: EXE } : {});
  const ok = (c, m) => { console.log((c ? 'OK  ' : 'FAIL') + ' ' + m); if (!c) process.exitCode = 1; };

  for (const p of PANTALLAS) {
    const ctx = await browser.newContext({ viewport: { width: p.w, height: p.h }, isMobile: true, hasTouch: true });
    const page = await ctx.newPage();
    page.on('pageerror', e => { console.log('PAGEERROR:', e.message); process.exitCode = 1; });
    // el login esta apagado y el service worker no hace falta para medir el layout
    await page.route('**/auth-guard.js*', r => r.fulfill({ contentType: 'application/javascript', body: 'window.GP2_AUTH_ON=false;' }));
    await page.route('**/pwa.js*', r => r.fulfill({ contentType: 'application/javascript', body: '' }));
    await page.goto(ROOT + '/GP2_MODULOS.html');
    await page.waitForSelector('.card');

    const m = await page.evaluate(() => {
      const cards = [...document.querySelectorAll('.card')];
      const titles = [...document.querySelectorAll('.card-head .title')];
      return {
        grupos: cards.length,
        fondo: Math.max(...cards.map(c => c.getBoundingClientRect().bottom)),
        alto_min: Math.min(...cards.map(c => c.getBoundingClientRect().height)),
        fuente_min: Math.min(...titles.map(t => parseFloat(getComputedStyle(t).fontSize))),
        horizontal: document.documentElement.scrollWidth > window.innerWidth,
        version: (document.getElementById('appVersion') || {}).textContent || '',
        foot: getComputedStyle(document.querySelector('.foot')).display,
        sub: (document.querySelector('.header-sub') || {}).textContent || '',
      };
    });

    ok(m.fondo <= p.h, `${p.nom}: los ${m.grupos} grupos entran en una pantalla (terminan en ${Math.round(m.fondo)} de ${p.h})`);
    ok(m.alto_min >= 44, `${p.nom}: cada grupo es tocable (${Math.round(m.alto_min)}px, minimo 44)`);
    ok(m.fuente_min >= 14, `${p.nom}: titulos legibles (${m.fuente_min}px)`);
    ok(!m.horizontal, `${p.nom}: sin scroll horizontal`);
    ok(/^v?\d+\.\d+\.\d+$/.test(m.version.trim()), `${p.nom}: muestra el numero de version (${m.version})`);
    ok(m.foot === 'none', `${p.nom}: el pie de pagina no ocupa lugar`);
    ok(!/pendientes de migraci/i.test(m.sub), `${p.nom}: sin el cartel viejo, solo la version`);

    /* Abrir CADA grupo (el usuario pidio "botones grandes y ordenados siempre, en
       todos los rubros"): se ve solo ese, los modulos son baldosas en 2 columnas
       parejas y el grupo entra en la pantalla sin scrollear. Un grupo de 1 modulo
       ocupa el ancho entero: ahi 1 columna es lo correcto, no un boton a medias. */
    const grupos = await page.evaluate(() =>
      [...document.querySelectorAll('.card-head .title')].map(t => t.textContent.trim()));
    ok(grupos.length === m.grupos, `${p.nom}: se listan los ${m.grupos} rubros`);

    for (const g of grupos) {
      await page.click(`.card-head:has-text("${g}")`);
      await page.waitForTimeout(200);
      const a = await page.evaluate(() => {
        const ops = [...document.querySelectorAll('.card.open .btns > *')].map(el => {
          const r = el.getBoundingClientRect();
          return { w: r.width, h: r.height, x: Math.round(r.x), fs: parseFloat(getComputedStyle(el).fontSize) };
        });
        return {
          solo: [...document.querySelectorAll('.card:not(.open)')].every(c => getComputedStyle(c).display === 'none'),
          n: ops.length,
          alto: Math.min(...ops.map(o => o.h)),
          fuente: Math.min(...ops.map(o => o.fs)),
          cols: new Set(ops.map(o => o.x)).size,
          anchos: new Set(ops.map(o => Math.round(o.w))).size,   // baldosas parejas
          fondo: Math.max(...[...document.querySelectorAll('.card.open')].map(c => c.getBoundingClientRect().bottom)),
          horizontal: document.documentElement.scrollWidth > window.innerWidth,
        };
      });
      const colsEsperadas = a.n === 1 ? 1 : 2;
      ok(a.solo, `${p.nom}/${g}: al abrir se ve solo ese grupo`);
      ok(a.cols === colsEsperadas, `${p.nom}/${g}: ${a.n} modulos en ${colsEsperadas} columna(s) (mide ${a.cols})`);
      ok(a.anchos <= 2, `${p.nom}/${g}: baldosas parejas (${a.anchos} anchos distintos)`);
      ok(a.alto >= 44, `${p.nom}/${g}: baldosas tocables (${Math.round(a.alto)}px, minimo 44)`);
      ok(a.fuente >= 15, `${p.nom}/${g}: texto legible (${a.fuente}px)`);
      ok(a.fondo <= p.h, `${p.nom}/${g}: entra sin scrollear (termina en ${Math.round(a.fondo)} de ${p.h})`);
      ok(!a.horizontal, `${p.nom}/${g}: sin scroll horizontal`);
      // Jerarquia de Insumos, pedida por el usuario con screenshot: primero y a
      // todo el ancho lo de todos los dias (comprar y recibir), despues el
      // stock rubro por rubro, y ultimo y apagado Inyectores, que es config.
      // Se fija aca para que no se aplane sin querer en un rediseno futuro.
      if (g === 'Insumos') {
        const j = await page.evaluate(() => [...document.querySelectorAll('.card.open .btns > *')]
          .map(el => ({ t: el.textContent.replace('\u203a', '').trim(),
                        cls: el.className, w: Math.round(el.getBoundingClientRect().width) })));
        const anchoMax = Math.max(...j.map(x => x.w));
        const principales = j.filter(x => /\bprincipal\b/.test(x.cls));
        ok(j[0].t.startsWith('Órdenes de Compra') && j[1].t.startsWith('Recepción Insumos'),
           `${p.nom}/Insumos: arriba van Órdenes de Compra y Recepción (hoy: ${j[0].t} / ${j[1].t})`);
        ok(principales.length === 2 && principales.every(x => x.w === anchoMax),
           `${p.nom}/Insumos: los 2 principales ocupan el ancho entero`);
        // Los dos "quien hace cada parte" (Inyectores y Pintores) cierran el grupo, apagados.
        ok(/\bsecundario\b/.test(j[j.length - 1].cls) && j[j.length - 1].t.startsWith('Pintores') &&
           /\bsecundario\b/.test(j[j.length - 2].cls) && j[j.length - 2].t.startsWith('Inyectores'),
           `${p.nom}/Insumos: Inyectores y Pintores van ultimos y apagados`);
      }

      await page.click(`.card-head:has-text("${g}")`);   // cerrar antes del siguiente
      await page.waitForTimeout(120);
    }
    await ctx.close();
  }

  await browser.close();
  console.log(process.exitCode ? 'HAY FALLOS' : 'TODO OK');
})();
