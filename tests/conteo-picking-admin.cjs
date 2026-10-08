/* v28.58 (Luis, 08/10) — conteos de góndola del picking en la landing del admin.
   Corre cgLoad/cgRender/cgResolver con la RPC mockeada: dibuja código · góndola · contó hoy · dif,
   ✓ llama al resolver con p_ajustar=true, ✕ con false; sin filas no se dibuja; lectura rota lo dice. */
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
    const rows = [{ client_id: "cg_1", ts: "2026-10-08T12:00:00-03:00", legajo: "104", nombre: "Jhonny", cod: "574E", empresa: null,
      tanda: "F60A", gondolas: "F49", contado: 50, esperado: 45, dif: 5, saldo_hoy: 15, contado_hoy: 20 }];
    window.sb = { rpc: async function (n, a) { calls.push([n, a]); if (n === "gv_conteo_picking_pendientes") return { data: window.__rows, error: null }; return { data: { ok: true }, error: null }; } };
    window.confirm = function () { return true };
    const box = document.getElementById("cgAside");
    window.__rows = rows; await cgLoad();
    out.visible = box.style.display !== "none";
    out.txt = box.textContent;
    out.tieneCod = /574E · F49/.test(out.txt) && /Contó 20/.test(out.txt) && /\+5/.test(out.txt);
    window.__rows = []; await cgResolver(0, true);
    const res = calls.filter(function (c) { return c[0] === "gv_conteo_picking_resolver"; });
    out.ok = res.length === 1 && res[0][1].p_cid === "cg_1" && res[0][1].p_ajustar === true;
    out.vacio = box.style.display === "none";
    window.__rows = rows; await cgLoad(); await cgResolver(0, false);
    const res2 = calls.filter(function (c) { return c[0] === "gv_conteo_picking_resolver"; });
    out.no = res2.length === 2 && res2[1][1].p_ajustar === false;
    window.sb = { rpc: async function () { return { data: null, error: { message: "x" } }; } };
    await cgLoad(); out.rota = /No se pudieron leer/.test(box.textContent);
    return out;
  });
  const pass = r.visible && r.tieneCod && r.ok && r.vacio && r.no && r.rota && !errs.length;
  console.log("conteo-picking-admin:", JSON.stringify(r), errs.join("|") || "", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
