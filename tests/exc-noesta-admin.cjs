/* v31.85 (Luis, 16/10/2026) — EXCEDENTE QUE NO ESTABA, en la landing del admin.
   "Que sale como notificacion en el admin como cuando un conteo difiere con lo que el sistema tiene que debería
    haber del articulo en gondola. Si el admin lo aprueba, esa gondola se marca como vacia."
   Corre cgLoad/cgRender/enResolver con las RPC mockeadas:
     (a) el aviso sale en el cuadro de conteos aunque no haya conteos: código · posición · cajas sin posición;
     (b) ✓ llama a gv_exc_noesta_resolver(id, true) y el cuadro se va; ✕ con false;
     (c) con conteos y avisos, salen los dos;
     (d) lectura rota del aviso lo dice (no lo dibuja como «no hay»). Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {}; const calls = [];
    const en = [{ id: 7, ts: "2026-10-16T15:10:00-03:00", legajo: "104", nombre: "Jhonny Cartaya", cod: "66", tanda: "F12A", sector: "P13", cajas_sin_pos: 3 }];
    const cg = [{ client_id: "cg_1", ts: "2026-10-16T12:00:00-03:00", legajo: "104", nombre: "Jhonny", cod: "574E", empresa: null,
      tanda: "F60A", gondolas: "F49", contado: 50, esperado: 45, dif: 5, saldo_hoy: 15, contado_hoy: 20 }];
    let enErr = false;
    window.sb = { rpc: async function (n, a) {
      calls.push([n, a]);
      if (n === "gv_conteo_picking_pendientes") return { data: window.__cg, error: null };
      if (n === "gv_exc_noesta_pendientes") return enErr ? { data: null, error: { message: "x" } } : { data: window.__en, error: null };
      return { data: { ok: true }, error: null };
    } };
    window.confirm = function () { return true; };
    const box = document.getElementById("cgAside");
    // (a)
    window.__cg = []; window.__en = en; await cgLoad();
    out.txtA = box.textContent.replace(/\s+/g, " ");
    out.a = box.style.display !== "none" && /Excedente que no estaba \(1\)/.test(out.txtA) && /066 · P13/.test(out.txtA) && /3 cj sin posici/.test(out.txtA);
    // (b)
    window.__en = []; await enResolver(0, true);
    const res = calls.filter((c) => c[0] === "gv_exc_noesta_resolver");
    out.b = res.length === 1 && res[0][1].p_id === 7 && res[0][1].p_vaciar === true && box.style.display === "none";
    window.__en = en; await cgLoad(); await enResolver(0, false);
    const res2 = calls.filter((c) => c[0] === "gv_exc_noesta_resolver");
    out.bNo = res2.length === 2 && res2[1][1].p_vaciar === false;
    // (c)
    window.__cg = cg; window.__en = en; await cgLoad();
    const t = box.textContent;
    out.c = /574E · F49/.test(t) && /066 · P13/.test(t);
    // (d)
    window.__cg = []; enErr = true; await cgLoad();
    out.d = box.style.display !== "none" && /Excedente que no estaba/.test(box.textContent) && /No se pudieron leer/.test(box.textContent);
    return out;
  });
  await b.close();
  const pass = r.a && r.b && r.bNo && r.c && r.d && !errs.length;
  console.log("exc-noesta-admin:", JSON.stringify(r), errs.join("|") || "", pass ? "✓ OK" : "✗ FAIL");
  process.exit(pass ? 0 : 1);
})();
