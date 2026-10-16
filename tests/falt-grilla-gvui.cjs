/* Faltantes x día con la regla GV-UI §5 (Luis, 16/10/2026, «D1 sí»): la grilla estaba en 12 px con
   encabezados de 11 px alineados a la izquierda, emojis en los botones y un párrafo al pie que explicaba
   las columnas. Mide, con la grilla corriendo (datos de prueba, «Ver días» con días de súper = 2 filas
   de encabezado), a 1920 y a 430 px:
   (a) dato >= 14 px, y a 1920 escala (> 14)
   (b) encabezados centrados, >= 13 px
   (c) sticky: con el wrapper scrolleado, la fila de los días queda pegada DEBAJO de la de la «S»
       (no la tapa ni deja hueco, ±1 px) — el top lo mide _faltStickyFix, no un 17 px supuesto
   (d) sin emojis decorativos en botones, buscador, resumen ni pie (queda 🔴 = faltó al armar, ☑/☐ y ✓/✕)
   (e) el pie es una línea («N artículos con demanda»), sin la explicación de columnas
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const out = {};
  for (const W of [1920, 430]) {
    const p = await b.newPage({ viewport: { width: W, height: 900 } });
    const errs = []; p.on("pageerror", (e) => errs.push(e.message));
    await p.route("**/rest/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "[]" }));
    await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
    out[W] = await p.evaluate(async () => {
      window.alert = () => {};
      try { openStockAdmin(); } catch (e) {}
      await new Promise((r) => setTimeout(r, 500));
      const hoy = _faltHoy(), d = (n) => _faltAddHabiles(hoy, n), dem = {}, sMap = {}, provMap = {};
      for (let i = 0; i < 30; i++) {
        const c = String(600 + i);
        dem[c] = [{ fecha: d(i % 6), cajas: 10 + i * 3, np: "44" + (600 + i), esSuper: i % 4 === 0 }, { fecha: d((i + 3) % 9), cajas: 5 + i, np: "45" + (100 + i), esSuper: false }];
        sMap[c] = { total: i % 3 === 0 ? 2 : 40, totalGross: 40, desc: "Articulo " + c };
        provMap[c] = "Fujian";
      }
      _stk = Object.assign(_stk || {}, { tab: "faltante", faltLoaded: true, falt: { demanda: dem, saldoMap: sMap, provMap, demTotDet: dem, verDias: true, ajustes: {} } });
      const body = document.getElementById("stkBody") || (() => { const x = document.createElement("div"); x.id = "stkBody"; document.body.appendChild(x); return x; })();
      body.innerHTML = stkBodyFaltante();
      await new Promise((r) => setTimeout(r, 200));
      const t = document.querySelector(".falt-tbl"), rows = t.tHead.rows, w = document.querySelector(".falt-wrap");
      const ths = [...rows[0].cells].filter((c) => !c.classList.contains("falt-dia") && !c.classList.contains("falt-sep"));
      const td = t.querySelector("tbody td.num");
      w.scrollTop = 300; await new Promise((r) => setTimeout(r, 100));
      const s = rows[0].querySelector("th.falt-dia").getBoundingClientRect(), d2 = rows[1].cells[0].getBoundingClientRect();
      const fuera = [...body.querySelectorAll(".falt-top, .falt-sum, .falt-foot, .falt-sim-bar")].map((x) => x.textContent).join(" ")
        + " " + (body.querySelector(".falt-search") || {}).placeholder;
      return { dos: rows.length === 2, tdFs: parseFloat(getComputedStyle(td).fontSize),
        thOk: ths.every((c) => getComputedStyle(c).textAlign === "center" && parseFloat(getComputedStyle(c).fontSize) >= 13),
        pegado: Math.abs(d2.top - s.bottom) <= 1, scrolleo: w.scrollTop > 0,
        emo: /[\u{1F300}-\u{1F534}\u{1F536}-\u{1FAFF}⏳⇄]/u.test(fuera),
        pie: (document.querySelector(".falt-foot") || {}).textContent || "" };
    });
    out[W].errs = errs.length;
    await p.close();
  }
  await b.close();
  const c = {
    a_dato14: out[1920].tdFs > 14 && out[430].tdFs >= 14,
    b_th: out[1920].thOk && out[430].thOk,
    c_sticky: [1920, 430].every((W) => out[W].dos && out[W].scrolleo && out[W].pegado),
    d_sinEmojis: !out[1920].emo && !out[430].emo,
    e_pie: /^\d+ artículos con demanda$/.test(out[1920].pie),
    sinErrores: !out[1920].errs && !out[430].errs
  };
  const pass = Object.values(c).every(Boolean);
  console.log("falt-grilla-gvui:", JSON.stringify(c), "· dato", out[1920].tdFs + "px", "·", pass ? "✓ OK" : "✗ FAIL");
  if (!pass) console.log(JSON.stringify(out));
  process.exit(pass ? 0 : 1);
})();
