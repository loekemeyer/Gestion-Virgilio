/* Regresión v15.66 — Corregir códigos: el stock del SECUNDARIO se reparte entre TODAS las NP que lo
   piden (dueño, 11/09: "mirá el 565 primero: el stock y sus pedidos"). Antes cada NP se comparaba sola
   contra el stock total (565 = 2 salía "alcanza" para 7 NP / 8 cajas). La regla vive en
   vista_correcciones_pedido_rich.sec_cubre; el front la lee y la usa en panel, badge y chip.

   Caso real del 11/09: 565 → 607E, stock 2, 7 NP / 8 cajas; 338 → 941E, stock 23, 1 NP. Chequea:
   - facCorreccDataRich pide las columnas nuevas y mapea secCubre/secOrden/secDisp/secTot/secNps;
     _corrItemUrgente = !secCubre; _corrNpsUrgentes cuenta NP distintas (6).
   - El panel pinta 98662 en verde ("le alcanza") y 98671 en rojo ("cambiá NP a 607E"), muestra la
     cola ("pedidas 8 en 7 NP, ésta es la 4.ª") y los botones dicen Urgentes (6) / Ver todos (8);
     "Solo urgentes" esconde las cubiertas.
   - El chip (render y facCorreccRefreshCount) y los badges (corrLoadBadge: rojo 6, verde 2) dan el
     mismo número que el panel.
   - Sin sec_cubre (vista vieja / rollback) cae al criterio viejo stk_sec >= cajas.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {}; const urls = [];
    const R = (np, sec, ppal, cajas, tanda, estado, stkSec, stkPpal, tot, nps, orden, antes) => ({
      np, sec, ppal, descripcion: sec === "565" ? "Pinza De Hielo" : "Espatula Lisa", cajas, razon_social: "RS " + np,
      tanda, fecha: np === "98621" ? "2026-09-14 00:00:00" : "2026-09-10 00:00:00", stk_sec: stkSec, stk_ppal: stkPpal,
      ent_ped: null, ent_entr: null, ent_falto: null, estado,
      sec_pedido_total: tot, sec_np_total: nps, sec_orden: orden, sec_acum_antes: antes,
      sec_disp: Math.max(stkSec - antes, 0), sec_cubre: (stkSec - antes) >= cajas });
    const ROWS = [
      R("98532", "338", "941E", 1, "D60E", "afacturar",  23, 36,  1, 1, 1, 0),
      R("98662", "565", "607E", 2, "D67A", "pickeado",    2, 296, 8, 7, 1, 0),
      R("98671", "565", "607E", 1, "D67E", "pickeado",    2, 296, 8, 7, 2, 2),
      R("98674", "565", "607E", 1, "D67F", "pickeado",    2, 296, 8, 7, 3, 3),
      R("98664", "565", "607E", 1, "D67I", "sinpickear",  2, 296, 8, 7, 4, 4),
      R("98678", "565", "607E", 1, "D67G", "sinpickear",  2, 296, 8, 7, 5, 5),
      R("98688", "565", "607E", 1, "D67L", "sinpickear",  2, 296, 8, 7, 6, 6),
      R("98621", "565", "607E", 1, "D69B", "sinpickear",  2, 296, 8, 7, 7, 7)
    ];
    const SIN = ["sec_pedido_total", "sec_np_total", "sec_orden", "sec_acum_antes", "sec_disp", "sec_cubre"];
    let modo = "nueva";
    window.fetch = async function (url) {
      urls.push(String(url));
      const J = (rows) => ({ ok: true, status: 200, json: async () => rows, headers: { get: () => null } });
      if (String(url).indexOf("vista_correcciones_pedido_rich") >= 0) {
        return J(modo === "nueva" ? ROWS : ROWS.map((x) => { const c = Object.assign({}, x); SIN.forEach((k) => delete c[k]); return c; }));
      }
      return J([]);
    };
    const rows = await facCorreccDataRich();
    out.pideColumnas = (urls[0] || "").indexOf("sec_pedido_total,sec_np_total,sec_orden,sec_acum_antes,sec_disp,sec_cubre") >= 0;
    out.mapeo = rows.length === 8 && rows[1].np === "98662" && rows[1].secCubre === true && rows[1].secOrden === 1 && rows[1].secDisp === 2
      && rows[2].np === "98671" && rows[2].secCubre === false && rows[2].secDisp === 0 && rows[2].secTot === 8 && rows[2].secNps === 7 && rows[2].secAntes === 2;
    out.urgente = _corrItemUrgente(rows[2]) === true && _corrItemUrgente(rows[1]) === false && _corrItemUrgente(rows[0]) === false;
    out.npsUrgentes = _corrNpsUrgentes(rows) === 6;
    // panel
    let body = document.getElementById("facCorreccBody");
    if (!body) { body = document.createElement("div"); body.id = "facCorreccBody"; document.body.appendChild(body); }
    _facCorrRows = rows; _facCorrSoloUrg = false; _facCorrFiltro = "todo";
    facCorreccRender();
    const h = body.innerHTML;
    const card = (np) => { const i = h.indexOf("NP " + np); return i < 0 ? "" : h.slice(i, h.indexOf("✓ Ya lo cambié", i)); };
    out.verde98662 = card("98662").indexOf("le alcanza") >= 0 && card("98662").indexOf("mandalo tal cual") >= 0 && card("98662").indexOf("cambiá NP") < 0;
    out.rojo98671 = card("98671").indexOf("cambiá NP a 607E") >= 0 && card("98671").indexOf("le quedan <b>0</b> de 1") >= 0 && card("98671").indexOf("mandalo tal cual") < 0;
    out.cola = card("98664").indexOf("pedidas 8 en 7 NP, ésta es la 4.ª") >= 0 && card("98664").indexOf("(pedidas 8 en 7 NP)") >= 0;
    out.sinCola338 = card("98532").indexOf("le alcanza") >= 0 && card("98532").indexOf("pedidas") < 0;
    out.botones = h.indexOf("Urgentes (6)") >= 0 && h.indexOf("Ver todos (8)") >= 0;
    _facCorrSoloUrg = true; facCorreccRender(); const h2 = body.innerHTML;
    out.soloUrgentes = h2.indexOf("NP 98662") < 0 && h2.indexOf("NP 98532") < 0 && h2.indexOf("NP 98671") >= 0 && h2.indexOf("NP 98621") >= 0;
    // chip: lo pinta el render con las filas que tiene, y facCorreccRefreshCount lo vuelve a pedir
    const cnt = document.getElementById("facCntCorr");
    out.chipRender = !!cnt && cnt.textContent === "6";
    if (cnt) cnt.textContent = "x";
    await facCorreccRefreshCount();
    out.chipRefresh = !!cnt && cnt.textContent === "6";
    // badges del panel supervisor
    await corrLoadBadge();
    out.badges = document.getElementById("corrBadge").textContent === "6" && document.getElementById("corrBadgeGreen").textContent === "2";
    // vista vieja (rollback): sin sec_cubre → criterio viejo stk_sec >= cajas
    modo = "vieja"; const rv = await facCorreccDataRich();
    out.fallbackViejo = rv[1].secCubre === true && rv[2].secCubre === true && rv[2].secTot === 0 && _corrNpsUrgentes(rv) === 0;
    return out;
  });
  const pass = Object.keys(r).every((k) => r[k] === true) && !errs.length;
  console.log("corr-reparto-sec:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join(" | ") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
