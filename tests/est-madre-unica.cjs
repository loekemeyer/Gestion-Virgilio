/* v25.79 — la ESTADÍSTICA MADRE es UN SOLO CUADRO (Tomás Beviglia, 01/10/2026: "es un solo cuadro
   que se imprime en dos lados distintos. NUNCA puede un cuadro de est madre quedar más actualizado
   que otro. Si alguien quiere cambiar uno solo NO se puede hacer").

   El módulo vive SÓLO en admin/est-madre.js (este repo, publicado por GitHub Pages). La página LK
   (repo pagina-LK-copia) y este espejo traen únicamente el cargador abrirEstadisticaMadre. Chequea:
   A) que admin/est-madre.js exista y no diga «Proyección» en ningún lado (es «Est Madre»);
   B) que admin/admin.js, admin.html y css/admin.css NO tengan una Est. Madre propia;
   C) que el cargador sea IDÉNTICO al de pagina-LK-copia (huella md5 abajo: el mismo número está en
      tests/est-madre-unica.cjs de aquel repo; si cambia acá, cambia allá en el mismo pedido);
   D) que las filas sean las de Stocks (sin las ocultas vacías), el dual en dos filas, el secundario
      sin ranking y los meses de ESA fila (corre _emArmarFilas de verdad);
   E) que la Edge Function gv-est-madre deje pasar las ventas por mes y ya no el caché viejo.
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const vm = require("vm");
const R = path.resolve(__dirname, "..");
const HUELLA_CARGADOR = "416c801a060ef3743a35ccfb476c4ff4";
const URL_MODULO = "https://loekemeyer.github.io/Gestion-Virgilio/admin/est-madre.js";
const fallas = [];
const ok = (c, m) => { if (!c) fallas.push(m); };
const leer = (p) => fs.readFileSync(path.join(R, p), "utf8").replace(/^﻿/, "");

// A
const mod = leer("admin/est-madre.js");
ok(!/royecci/i.test(mod), "A: est-madre.js dice «Proyección»");
ok(/Est Madre<br><small>caj\/mes<\/small>/.test(mod), "A: el encabezado no dice Est Madre caj/mes");
ok(/stocks_carga_rapida/.test(mod) && /get_estadistica_madre_mensual/.test(mod), "A: el módulo no lee Stocks + ventas por mes");
ok(!/get_estadistica_madre_cache/.test(mod), "A: el módulo todavía lee el caché viejo");
// B
const adm = leer("admin/admin.js");
for (const f of ["function cargarEstadisticaMadre", "function _renderEstMadreTable", "function mostrarDetalleVentaMadre",
                 "function descargarEstadisticaMadreExcel", "function descargarReporteVentasDisruptivas", "get_estadistica_madre_cache"]) {
  ok(adm.indexOf(f) < 0, "B: admin/admin.js tiene una copia propia: " + f);
}
const html = leer("admin/admin.html");
ok(/<section class="page" id="estadistica-madre"><\/section>/.test(html), "B: la sección de admin.html no está vacía");
ok(!/estMadreTable|Proyección\s*mensual/.test(html), "B: admin.html trae HTML propio de la Est. Madre");
ok(!/\.est-madre-table/.test(leer("admin/css/admin.css")), "B: css/admin.css trae estilos propios de la Est. Madre");
// C
const i = adm.indexOf("/* =========================================================\n   ESTADÍSTICA MADRE — UN SOLO CUADRO");
const fin = "window.abrirEstadisticaMadre = abrirEstadisticaMadre;\n";
const j = i >= 0 ? adm.indexOf(fin, i) : -1;
const huella = j > 0 ? crypto.createHash("md5").update(adm.slice(i, j + fin.length), "utf8").digest("hex") : "(sin cargador)";
ok(huella === HUELLA_CARGADOR, "C: el cargador cambió (" + huella + "): cambiarlo IGUAL en pagina-LK-copia y actualizar la huella en los dos tests");
ok(adm.indexOf('var EM_MODULO_URL = "' + URL_MODULO + '"') >= 0, "C: el cargador no apunta a " + URL_MODULO);
// D — se corre _emArmarFilas de verdad
const ctx = { window: {}, document: { getElementById: () => null }, console };
vm.createContext(ctx);
vm.runInContext(mod, ctx);
const armar = ctx.window.EstMadre && ctx.window.EstMadre._armarFilas;
ok(typeof armar === "function", "D: EstMadre._armarFilas no existe");
if (typeof armar === "function") {
  const stocks = [
    { cod: "26", descripcion: "Colador 8", linea: "LK", es_secundario: false, proy_cajas_mes: 197, visible_en_stock: true, stock_total: 268, cajas_pedidas: 26 },
    { cod: "437E LK", descripcion: "Colador Pasta", linea: "LK", es_secundario: false, proy_cajas_mes: 36, visible_en_stock: true, stock_total: 314, cajas_pedidas: 16 },
    { cod: "437E CH", descripcion: "Colador Pasta", linea: "CH", es_secundario: false, proy_cajas_mes: 6, visible_en_stock: true, stock_total: 14, cajas_pedidas: 1 },
    { cod: "29", descripcion: "Colador Fideos", linea: "LK", familia_principal: "437E", es_secundario: true, proy_cajas_mes: 0, visible_en_stock: true, stock_total: 0, cajas_pedidas: 0 },
    { cod: "VASTIDOR", descripcion: "", linea: "", es_secundario: false, proy_cajas_mes: 0, visible_en_stock: false, stock_total: 0, cajas_pedidas: 0 },
  ];
  const mensual = [
    { item: "026", empresa: "lk", meses: { "2026-09": 166 } },
    { item: "26", empresa: "chef", meses: { "2026-09": 4 } },
    { item: "437E", empresa: "lk", meses: { "2026-09": 28 } },
    { item: "437E", empresa: "chef", meses: { "2026-09": 12 } },
    { item: "29", empresa: "lk", meses: { "2026-09": 11 } },
    { item: "CARTONERIA", empresa: "lk", meses: { "2026-09": 5 } },
  ];
  const f = armar(stocks, mensual, [{ cod: "026", category: "Coladores" }], []);
  const by = {}; f.forEach((x) => { by[x.key] = x; });
  ok(f.length === 4, "D: tienen que salir 4 filas (sin VASTIDOR ni CARTONERIA), salieron " + f.length);
  ok(by["26"] && by["26"].cod === "026" && by["26"].byYm["2026-09"] === 170 && by["26"].codLk === "026", "D: 026 tiene que sumar LK + Chef (170) y mostrarse 026");
  ok(by["437E LK"] && by["437E LK"].byYm["2026-09"] === 28 && by["437E LK"].est === 36, "D: 437E LK: sólo las ventas de LK y su Est Madre");
  ok(by["437E CH"] && by["437E CH"].byYm["2026-09"] === 12 && by["437E CH"].est === 6 && by["437E CH"].marca === "CH", "D: 437E CH: sólo las ventas de Chef");
  ok(by["29"] && by["29"]._rank === null && by["29"].principal === "437E", "D: el secundario no rankea y apunta al principal");
  ok(by["26"] && by["26"]._rank === 1, "D: el ranking va por Est Madre");
}
// E
const ef = leer("admin/supabase/gv-est-madre/index.ts");
ok(/"rpc\/get_estadistica_madre_mensual":/.test(ef), "E: la Edge Function no deja pasar las ventas por mes");
ok(!/"rpc\/get_estadistica_madre_cache":/.test(ef), "E: la Edge Function todavía deja pasar el caché viejo");
const pe = adm.match(/var GV_EM_PERMITIDAS = \{[\s\S]*?\};/);
ok(pe && /rpc\/get_estadistica_madre_mensual/.test(pe[0]) && !/get_estadistica_madre_cache/.test(pe[0]), "E: la lista del espejo no coincide con la Edge Function");

console.log("est-madre-unica:", fallas.length ? "✗ FAIL\n  - " + fallas.join("\n  - ") : "✓ OK (cargador " + huella + ")");
process.exit(fallas.length ? 1 : 0);
