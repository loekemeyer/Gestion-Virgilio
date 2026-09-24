/* Regresión v22.36 — UNA CARGA POR LOTE EN VUELO NO PISA LA INVALIDACIÓN.
   Luis, 24/09: "web CH 218 · Ierakuin no tiene monto ni comentarios" — el backend devolvía 7
   comentarios y $2.100.319. La carga de comentarios de la 1.ª marcación (LK+ISIS, sin Chef) seguía
   en vuelo cuando la 2.ª marcación (con Chef) la invalidó; al volver escribió su mapa sin Chef y
   nadie la volvió a pedir. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const espera = (ms) => new Promise((ok) => setTimeout(ok, ms));
    const lk = { order_id: 1500, empresa: "lk", cod: "1", cuarentena_motivos: ["deuda"] };
    const ch = { order_id: 218, empresa: "chef", cod: "1665", cuarentena_motivos: ["deuda"] };
    let llamadas = 0;
    window.aprRpc = async function (fn, body) {
      if (fn !== "gv_cuarentena_comentarios_lote") return [];
      llamadas++;
      const ps = body.p_pedidos || [];
      await espera(llamadas === 1 ? 150 : 10);
      return ps.map((x) => ({ empresa: x.empresa, clave: x.clave, n: x.empresa === "chef" ? 7 : 1 }));
    };
    _pppTab = "otra";
    _apr.pedidos = [lk]; _apr.cuarComN = null;
    const pr = cuarComLoteCargar();            // 1.ª vuelta, sólo LK, lenta
    await espera(20);
    _apr.pedidos = [lk, ch];                   // llega Chef y la 2.ª marcación invalida
    aprInvalidarLotes(); _apr.cuarComN = null;
    await pr;                                  // la vieja vuelve y escribe su mapa sin Chef
    aprDescartarLotesViejos();                 // lo que hace el render siguiente
    if (_apr.cuarComN === null && !_apr.cuarComNLoading) await cuarComLoteCargar();
    return { n: (_apr.cuarComN || {})["chef:218"], llamadas };
  });
  await b.close();
  const f = [];
  if (r.n !== 7) f.push("el pedido de Chef quedó con " + r.n + " comentarios (esperado 7)");
  if (errs.length) f.push("errores: " + errs.join(" | "));
  if (f.length) { console.error("apr-lotes-carrera: FALLA\n  - " + f.join("\n  - ")); process.exit(1); }
  console.log("apr-lotes-carrera: OK — la carga vieja se descarta y se vuelve a pedir con Chef (" + r.llamadas + " llamadas)");
})();
