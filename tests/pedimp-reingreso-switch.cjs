/* v22.08 (Luis, 23/09) — switch «Cartel web» por importado en Pedidos Importación.
   ON = el badge de reingreso sale en las páginas y el pedido se parte; OFF = fila en
   GV_Reingreso_Excluido. Se corre la pantalla de verdad:
   (a) mientras la lista no cargó, el switch NO se dibuja (un ON supuesto mentiría);
   (b) cargada, 584E sale OFF y 505E ON (el código normalizado: 0584E también es 584E);
   (c) apagar 505E manda gv_reingreso_web_set {p_cod:'505E', p_activo:false} con el
       header de supervisor y la fila queda OFF;
   (d) sin sesión no manda nada.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  const sets = [];
  await p.route("**/rest/v1/**", async (r) => {
    const u = r.request().url();
    if (u.includes("/rpc/gv_reingreso_excluidos")) return r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify([{ cod: "584E" }]) });
    if (u.includes("/rpc/gv_reingreso_web_set")) { sets.push({ body: r.request().postDataJSON(), auth: r.request().headers()["authorization"] }); return r.fulfill({ status: 200, contentType: "application/json", body: "true" }); }
    return r.fulfill({ status: 200, contentType: "application/json", body: "[]" });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const it = (cod) => ({ cod, desc: "art " + cod, prov: "X", proyUni: 10, objetivoUni: 0, stockUni: 0, enCurso: 0, aPedirUni: 100, aPedirCajas: 10, uniMaster: 10, det: [{ id: 1, curso: 0, marca: "" }] });
  const a = await p.evaluate((items) => {
    _reingExcl = null; _reingExclCargando = true;           // simula la carga en vuelo
    _stkPopShell("📦 Pedidos Importación", "stkPopBody", true);
    _stkPop = { kind: "pedImp", data: { items: items, meses: 10 }, soloPedir: false, mcOverride: {} };
    _pedImpRender();
    const filas = document.querySelectorAll(".mva-tbl.wide tbody tr").length;
    const n = filas ? document.querySelectorAll(".mva-tbl.wide input[type=checkbox][onchange*=pedImpReingresoWeb]").length : -1;
    _reingExclCargando = false;
    return n;
  }, [it("0584E"), it("505E")]);
  if (a !== 0) fail("(a) con la lista sin cargar se dibujó el switch (" + a + ")");
  await p.evaluate(() => _reingExclCargar());
  const est = () => p.evaluate(() => [...document.querySelectorAll(".mva-tbl.wide tbody tr")].map((tr) => {
    const c = tr.querySelector("input[onchange*=pedImpReingresoWeb]");
    return tr.cells[0].textContent.trim().slice(0, 5).replace(/^0+/, "") + "=" + (c ? (c.checked ? "ON" : "OFF") : "-");
  }));
  const pis = await p.evaluate(() => [...document.querySelectorAll(".mva-tbl.wide td")].filter((c) => c.cellIndex !== 1 && c.scrollWidth > c.clientWidth + 1).map((c) => c.cellIndex));
  if (pis.length) fail("(b) el switch desborda la celda: columnas " + pis.join());
  const b1 = await est();
  if (b1.join() !== "584E=OFF,505E=ON") fail("(b) esperaba 584E=OFF,505E=ON y dio " + b1.join());
  await p.evaluate(() => { facAuthWriteHeaders = async (h) => Object.assign({ apikey: "k", Authorization: "Bearer SUP" }, h || {}); });
  await p.evaluate(() => pedImpReingresoWeb(encodeURIComponent("505E"), false));
  const c1 = await est();
  if (sets.length !== 1 || sets[0].body.p_cod !== "505E" || sets[0].body.p_activo !== false) fail("(c) request: " + JSON.stringify(sets));
  else if (sets[0].auth !== "Bearer SUP") fail("(c) no fue con el header de supervisor: " + sets[0].auth);
  if (c1.join() !== "584E=OFF,505E=OFF") fail("(c) tras apagar dio " + c1.join());
  await p.evaluate(() => { facAuthWriteHeaders = async () => null; window.alert = () => {}; });
  await p.evaluate(() => pedImpReingresoWeb(encodeURIComponent("584E"), true));
  if (sets.length !== 1) fail("(d) sin sesión igual mandó el cambio");
  if (errs.length) fail("errores de página: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("pedimp-reingreso-switch: OK — " + b1.join() + " → " + c1.join());
})();
