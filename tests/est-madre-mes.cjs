/* v27.36 · Est. Madre y Costos por mes (Luis, 06/10/2026) — candado.
   Lo que no puede romperse:
     A) subir la Est. Madre: toma la hoja «Loeke Madre…» (no la copia «(2)»), la columna «Cod Nuevo Isis»,
        conserva el TIPO del código (505 número, '026' texto) y los renglones en blanco / títulos;
        «Chef Madre» con «Cod. Isis»;
     B) subir Costos: los bloques «Loeke» y «Chef» de «Aportes Gastos», sin cortar en una fila en blanco;
     C) bajar: un mes por columna, del más nuevo al más viejo, en unidades, fila por fila igual a la plantilla;
        LK suma lo de Chef con L (031 = 031 + 031L), CH no;
     D) disruptivo: la celda del mes con estilo rojo/amarillo (s=3) y el detalle como COMENTARIO;
     E) pantalla: barra en la Est. Madre, baja el .xlsx y una RPC vacía no baja nada; el botón viejo no está. */
const path = require("path");
const fs = require("fs");
const X = require(path.join(__dirname, "..", "vendor", "xlsx.full.min.js"));
const em = require(path.join(__dirname, "..", "estadisticas.js"));

let fallas = 0;
function ok(c, m) { if (!c) { fallas++; console.log("  ✗ " + m); } }
function fin() { if (fallas) { console.log("est-madre-mes: " + fallas + " falla(s)"); process.exit(1); } console.log("est-madre-mes: ok (plantillas Est. Madre / Costos, bajada por mes en unidades, LK+L, disruptivos con comentario, pantalla)"); }

/* ---------- libros de prueba ---------- */
function libroMadre() {
  const wb = X.utils.book_new();
  const lk = X.utils.aoa_to_sheet([
    [null, null, null, "Actualizar Cada 3 Meses"],
    [null, null, null, "LOEKEMEYER"],
    [],
    ["TIPO", "Cat.\nArt", "Ranking", "Descripcion", "Cod Nuevo Isis", null, null, null, "E.Madre Uni x Mes"],
    [null, "Peladores", 1, "Pelador Mgo Plastico", 505, null, null, null, 30000],
    [null, "Coladores", 2, "Colador N°8", "026", null, null, null, 9000],
    [],
    [null, "Varios", 3, "Abrelata", "702E"],
    [null, null, null, null, "Articulos  Discontinuos"],
    [null, "Varios", 4, "Pinza", 561],
    [null, "Varios", 5, "Rallador", "323"],
    [null, "Varios", 6, "Sacayerba", 556]
  ]);
  const copia = X.utils.aoa_to_sheet([["TIPO", "x", "x", "Descripcion", "Cod Nuevo Isis"], [null, null, null, "z", 999], [null, null, null, "z", 998]]);
  const ch = X.utils.aoa_to_sheet([
    [], [], [null, null, null, null, null, "CHEF"], [],
    ["TIPO", "Cod.Art.", null, "Cod.Art.", "Ranking", "Cod. Isis", "Stock", "Entra", "Descripcion"],
    [null, 706, 706, 706, 2, 706, 300, 576, "Abrelatas Uñas"],
    [null, 99, 99, 99, 23, "099", 170, 300, "Pelapapas"],
    [null, "702E", "702E", "702E", 9, "702E", 150, null, "Abrelatas Mariposa"],
    [null, 1077, 1077, 1077, null, "H Lider", "X", null, "Pinza De Hielo"],
    [null, 809, 809, 809, 5, 809, 1, 1, "Colador"],
    [null, 824, 824, 824, 5, 824, 1, 1, "Colador 2"]
  ]);
  X.utils.book_append_sheet(wb, copia, "Loeke Madre - 7-26 (2)");
  X.utils.book_append_sheet(wb, lk, "Loeke Madre - 7-26");
  X.utils.book_append_sheet(wb, ch, "Chef Madre - 7-26");
  X.utils.book_append_sheet(wb, X.utils.aoa_to_sheet([["Cod Nuevo Isis"], [1], [2], [3], [4], [5], [6]]), "Loeke Madre por menor vta");
  return X.read(X.write(wb, { type: "array", bookType: "xlsx" }), { type: "array" });
}
function libroCostos() {
  const filas = [];
  for (let i = 0; i < 7; i++) filas.push([]);
  filas.push([null, null, null, "Loeke", "Uni x  mes Buca V isis", null, "Vtas Agosto  2026 Uni"]);
  ["026", "026T", 31, "031T", null, 207, "R", 513, "198E"].forEach((c) => filas.push([null, null, null, c]));
  filas.push([]); filas.push([]); filas.push([]);
  filas.push([null, null, null, "Chef", "Uni x  mes Buca V isis"]);
  ["043", "052", 307, "437E", 609, 615].forEach((c) => filas.push([null, null, null, c]));
  const wb = X.utils.book_new();
  X.utils.book_append_sheet(wb, X.utils.aoa_to_sheet([["otra"]]), "Costos");
  X.utils.book_append_sheet(wb, X.utils.aoa_to_sheet(filas), "Aportes Gastos");
  return X.read(X.write(wb, { type: "array", bookType: "xlsx" }), { type: "array" });
}

/* ---------- A) Est. Madre ---------- */
const m = em.emParsearMadre(X, libroMadre());
ok(m.lk && m.lk.hoja === "Loeke Madre - 7-26", "madre LK: toma «Loeke Madre - 7-26», no la copia (2) ni «por menor vta» (vino " + (m.lk && m.lk.hoja) + ")");
const fl = m.lk ? m.lk.filas : [];
ok(fl.length === 8, "madre LK: 8 filas desde la fila 5 (con el blanco y el título) — vino " + fl.length);
ok(fl[0] && fl[0].c === "505" && fl[0].n === true && fl[0].d === "Pelador Mgo Plastico", "madre LK: 505 es NÚMERO con su descripción");
ok(fl[1] && fl[1].c === "026" && !fl[1].n, "madre LK: '026' queda TEXTO");
ok(fl[2] && fl[2].c === null && !fl[2].t, "madre LK: el renglón en blanco se conserva");
ok(fl[4] && fl[4].c === null && fl[4].t === "Articulos  Discontinuos", "madre LK: un título en la columna del código queda como título");
ok(m.lk && m.lk.meta.col_cod === "E" && m.lk.meta.fila_desde === 5, "madre LK: meta col E desde fila 5");
ok(m.ch && m.ch.hoja === "Chef Madre - 7-26" && m.ch.meta.col_cod === "F", "madre CH: «Chef Madre», columna «Cod. Isis» (F)");
const fc = m.ch ? m.ch.filas : [];
ok(fc[1] && fc[1].c === "099" && fc[3] && fc[3].c === null && fc[3].t === "H Lider", "madre CH: '099' texto y «H Lider» como título");

/* ---------- B) Costos ---------- */
const c = em.emParsearCostos(X, libroCostos());
ok(c.lk && c.lk.hoja === "Aportes Gastos" && c.lk.filas.length === 9, "costos LK: 9 filas del bloque «Loeke» sin cortar en el blanco (vino " + (c.lk && c.lk.filas.length) + ")");
ok(c.lk && c.lk.filas[4].c === null && c.lk.filas[6].t === "R" && c.lk.filas[5].c === "207" && c.lk.filas[5].n, "costos LK: blanco, 'R' título, 207 número");
ok(c.ch && c.ch.filas.length === 6 && c.ch.filas[0].c === "043", "costos CH: 6 filas del bloque «Chef»");

/* ---------- C/D) bajada ---------- */
ok(em.emRotulo("ped", "2026-09") === "Sep 26 Uni" && em.emRotulo("fac", "2026-08") === "Vtas Agosto 2026 Uni", "rótulos de mes como las planillas");
ok(JSON.stringify(em.emRangoMes("2026-02")) === JSON.stringify({ desde: "2026-02-01", hasta: "2026-02-28" }), "rango del mes");
const pedLk = { "2026-09": [{ cod: "505", unidades: 26124, cajas: 2177 }, { cod: "026", unidades: 4248, cajas: 118 }, { cod: "561", unidades: null, cajas: 3 }],
                "2026-08": [{ cod: "505", unidades: 20000, cajas: 1 }] };
const pedCh = { "2026-09": [{ cod: "702EL", unidades: 1680, cajas: 1 }, { cod: "026L", unidades: 100, cajas: 1 }, { cod: "706", unidades: 50, cajas: 1 }], "2026-08": [] };
const disCh = [{ cod: "702EL", cliente: "2444", razon_social: "Cencosud", fecha: "2026-09-10", cajas: 70, unidades: 1680, tipo: "incorporacion" }];
const datos = {};
["2026-09", "2026-08"].forEach((ym) => {
  const u = em.emAcumular({}, pedLk[ym], "unidades", false); em.emAcumular(u, pedCh[ym], "unidades", true);
  const dis = ym === "2026-09" ? em.emDisAcumular({}, disCh, true) : {};
  datos[ym] = { u, dis };
});
ok(datos["2026-09"].u["26"].u === 4348, "LK suma lo de Chef con L: 026 = 4.248 + 100 de 026L");
ok(!datos["2026-09"].u["706"], "LK NO suma lo de Chef sin L (706)");
const h = em.emArmarHoja(X, "ped", "lk", m.lk, ["2026-09", "2026-08"], datos);
h.nombre = "Pedidos LK";
const bytes = em.emXlsxBytes(X, [h], 10);
const wb = X.read(bytes, { type: "array" });
const ws = wb.Sheets["Pedidos LK"];
const v = (a) => (ws[a] ? ws[a].v : undefined);
ok(v("A1") === "Cod Nuevo Isis" && v("B1") === "Descripcion" && v("C1") === "Sep 26 Uni" && v("D1") === "Ago 26 Uni", "encabezado: código, descripción y meses del más nuevo al más viejo");
ok(v("A2") === 505 && ws.A2.t === "n" && v("A3") === "026" && ws.A3.t === "s", "el código sale con su tipo (505 número, '026' texto)");
ok(v("C2") === 26124 && v("D2") === 20000 && v("C3") === 4348, "unidades por mes en su fila");
ok(v("A4") === undefined && v("C4") === undefined, "renglón en blanco sigue en blanco (no corre las filas)");
ok(v("A6") === "Articulos  Discontinuos", "el título sale en su fila");
ok(v("C5") === 1680, "702E LK = 1.680 de 702EL de Chef");
ok(v("C7") === 0 && ws.C7.c && /Sin UxB/.test(ws.C7.c[0].t), "sin UxB: 0 con comentario que lo dice");
ok(ws.C5.c && /Incorporación/.test(ws.C5.c[0].t) && /Cencosud/.test(ws.C5.c[0].t), "disruptivo: el detalle va como COMENTARIO de la celda");
ok(h.nDis === 1 && h.estilo("C5") === 3 && h.estilo("D5") === 2 && h.estilo("A5") === 0 && h.estilo("C1") === 1, "estilos: disruptivo 3, número 2, código 0, encabezado 1");
/* el xlsx de verdad: styles.xml con el fondo amarillo y la letra roja, y la celda con s=3 */
const cfb = X.CFB.read(new Uint8Array(bytes), { type: "array" });
const leer = (re) => { const i = cfb.FullPaths.findIndex((p) => re.test(p)); return i < 0 ? "" : new TextDecoder().decode(new Uint8Array(cfb.FileIndex[i].content)); };
const st = leer(/\/xl\/styles\.xml$/), sh = leer(/\/xl\/worksheets\/sheet1\.xml$/);
ok(/FFFFFF00/.test(st) && /FFFF0000/.test(st) && /<cellXfs count="4">/.test(st), "styles.xml: fondo amarillo, letra roja, 4 estilos");
ok(/<c r="C5" s="3"/.test(sh) && /<c r="C2" s="2"/.test(sh) && /<c r="A1" s="1"/.test(sh), "sheet1.xml: C5 con s=3, números s=2, encabezado s=1");
ok(cfb.FullPaths.some((p) => /comments\d*\.xml$/.test(p)), "el xlsx trae los comentarios");
/* CH: no suma lo de L */
const uCh = em.emAcumular({}, pedCh["2026-09"], "unidades", false);
ok(uCh["702EL"] && !uCh["702E"], "CH usa su propio código (702EL queda 702EL)");
/* facturación: A código + meses, sin descripción */
const hf = em.emArmarHoja(X, "fac", "lk", c.lk, ["2026-08"], { "2026-08": { u: em.emAcumular({}, [{ cod: "026", cantidad: 4319 }], "cantidad", false), dis: {} } });
ok(hf.ws.A1.v === "Loeke" && hf.ws.B1.v === "Vtas Agosto 2026 Uni" && hf.ws.B2.v === 4319 && hf.ws.A2.v === "026", "facturación: formato del «costo lk final»");

/* ---------- E) puertas ---------- */
const idx = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
const src = fs.readFileSync(path.join(__dirname, "..", "estadisticas.js"), "utf8");
ok(!/onclick="openEstadisticasIsis\(\)"/.test(idx), "el botón viejo de Estadísticas ISIS no está en el panel");
ok(/<div id="emBar"><\/div>/.test(idx) && /emBarPintar\(\)/.test(idx), "la barra va arriba del iframe de la Est. Madre");
ok(!/emBar|emParsear/.test(fs.readFileSync(path.join(__dirname, "..", "admin", "est-madre.js"), "utf8")), "est-madre.js (compartido con LK) no se tocó");
ok(/volvió vacío/.test(src) && /No se bajó nada/.test(src), "una RPC vacía o con error no baja nada");

(async () => {
  let chromium;
  try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
  catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { chromium = null; } }
  if (!chromium) { console.log("  (sin Playwright: se saltea la pantalla)"); return fin(); }
  const b = await chromium.launch();
  try {
    const ctx = await b.newContext({ viewport: { width: 1400, height: 900 }, serviceWorkers: "block", acceptDownloads: true });
    const p = await ctx.newPage();
    const errs = []; p.on("pageerror", (e) => errs.push(e.message));
    await p.route("**/rest/v1/**", (r) => r.abort());
    await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
    await p.evaluate(async (PL) => {
      const espera = (ms) => new Promise((res) => setTimeout(res, ms));
      for (let i = 0; i < 50 && typeof window.emBarPintar !== "function"; i++) await espera(100);
      window.__vacio = false;
      window.sb = { rpc: async (name, args) => {
        if (name === "gv_est_plantilla_leer") return { data: [{ clave: "madre_lk", archivo: "x.xlsx", hoja: "Loeke Madre", filas: PL, subido_en: "2026-10-06T12:00:00Z" }], error: null };
        if (name === "gv_isis_estad_pedidos_disruptivos") return { data: [], error: null };
        if (name === "gv_isis_estad_pedidos") return { data: window.__vacio || args.p_empresa === "ch" ? [] : [{ cod: "505", unidades: 12, cajas: 1 }], error: null };
        return { data: [], error: null };
      } };
      const d = document.createElement("div"); d.id = "emBar"; document.body.prepend(d);
      window.emBarPintar();
      for (let i = 0; i < 30 && !/Madre LK <b>/.test(d.innerHTML); i++) await espera(100);
    }, m.lk.filas);
    const bar = await p.$eval("#emBar", (e) => e.textContent);
    ok(/Subir Estadística Madre/.test(bar) && /Subir Costos/.test(bar) && /Bajar por mes/.test(bar), "pantalla: la barra tiene los tres botones");
    ok(/Madre LK 6/.test(bar) && /Costos LK sin subir/.test(bar), "pantalla: dice qué plantillas hay (" + bar.slice(0, 160) + ")");
    await p.evaluate(() => { window._em.sel = { "2026-09": true }; window.emAbrir(); });
    const dis = await p.$$eval("#emOv .sal button", (bs) => bs.map((b) => b.disabled));
    ok(dis[0] === false && dis[2] === true, "pantalla: Pedidos LK habilitado, Facturación LK no (falta Costos)");
    const [dl] = await Promise.all([p.waitForEvent("download", { timeout: 15000 }), p.click("#emOv .sal button")]);
    ok(dl.suggestedFilename() === "Pedidos_LK_sep26.xlsx", "pantalla: nombre (" + dl.suggestedFilename() + ")");
    const w2 = X.read(fs.readFileSync(await dl.path()), { type: "buffer" });
    const s2 = w2.Sheets[w2.SheetNames[0]];
    ok(s2.A2 && s2.A2.v === 505 && s2.C2 && s2.C2.v === 12, "pantalla: el .xlsx bajado trae 505 → 12 u");
    await p.evaluate(() => { window.__vacio = true; });
    let bajo = false; p.once("download", () => { bajo = true; });
    await p.click("#emOv .sal button");
    await p.waitForFunction(() => /No se bajó nada/.test(document.querySelector("#emOv .res").textContent), null, { timeout: 5000 });
    ok(!bajo, "pantalla: un mes vacío no baja nada");
    ok(!errs.length, "pantalla sin errores JS: " + errs.join(" | "));
  } finally { await b.close(); }
  fin();
})();
