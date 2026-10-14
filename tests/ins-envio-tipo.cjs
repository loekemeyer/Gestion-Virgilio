/* v30.86 (Luis, 14/10) — Entregar insumos: «Cervantes» (directo al remito) / «Otros» (a quién, obligatorio,
   con los inyectores habilitados como botones). Lo de abajo es la historia del test.
   v21.74 — Entregar insumos: primero "Envío a inyectores" / "Envío a otros".
   Inyectores → sólo la lista de GP2 (sin texto libre); si GP2 no responde, abre el texto libre.
   Otros → sólo texto libre, sin llamar a GP2.
   v29.27 (Thomas, D12): el botón de Pat Bet Plast dice «(Manolo)».
   v29.82 (Luis, 13/10): de los inyectores de GP2 se ofrecen SÓLO los habilitados
   (gv_insumo_origenes('inyector')): JL Matriceria queda afuera. ⚠ Esa lectura va STUBEADA —
   sin stub el test le pega a la base de verdad y deja de ser determinístico. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); } catch (_e) { ({ chromium } = require("playwright")); }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage(); const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const abierto = (id) => { const e = document.getElementById(id); return !!e && e.style.display !== "none"; };
    const vis = (id) => { const e = document.getElementById(id); return !!e && e.offsetParent !== null; };
    let rpc = 0, origCae = false;
    window.insGp2Rpc = async () => { rpc++; return { inyectores: ["JL Matriceria", "Kollplast", "Pat Bet Plast"], materiales: [] }; };
    // v29.82: los inyectores habilitados (lo que contesta gv_insumo_origenes). Nada sale a la red.
    window.fetch = async function (u) {
      if (/gv_insumo_origenes/.test(String(u)) && !origCae) {
        return { ok: true, json: async () => [{ nombre: "Kollplast", fuente: "inyector", orden: 2 }, { nombre: "Pat Bet Plast", fuente: "inyector", orden: 2 }, { nombre: "Pettofrezza Rafael", fuente: "inyector", orden: 2 }] };
      }
      return { ok: false, status: 500, json: async () => null, text: async () => "" };
    };
    insChooserGo("EI");
    const ch = document.getElementById("insChooserModal").innerText;
    /* v30.86 (Luis, 14/10): los dos botones son «Cervantes» y «Otros». */
    const out = { botones: /Cervantes/.test(ch) && /Otros/.test(ch) && !/Envío a inyectores/.test(ch) };
    // Cervantes: sin preguntar a quién, directo al remito que sale
    insEnvioTipoGo("cerv");
    out.cerv = window._insUbicacion === "Cervantes" && abierto("insDocModal") && !vis("insUbicInput");
    try { insDocCancel(); } catch (_e) {}
    const dm = document.getElementById("insDocModal"); if (dm) dm.style.display = "none";
    // Otros: a quién (texto obligatorio) + los inyectores habilitados como botones
    insEnvioTipoGo("otros"); await new Promise((s) => setTimeout(s, 50));
    const g = document.getElementById("insUbicGp2").innerText;
    out.otros = vis("insUbicInput") && vis("insUbicContinuar") && /A quién/.test(document.getElementById("insUbicModal").innerText);
    out.iny = !/JL Matriceria/.test(g) && /Kollplast/.test(g) && /Pat Bet Plast \(Manolo\)/.test(g) && !/Kollplast \(/.test(g);
    let alerto = ""; const oa = window.alert; window.alert = (m) => { alerto = String(m); };
    insUbicOk("EI"); window.alert = oa;
    out.obligatorio = /a quién/i.test(alerto) && abierto("insUbicModal");
    insUbicCancel();
    /* v29.82: si la lista de habilitados NO se puede leer, se ofrecen los de GP2 (lo de antes). */
    origCae = true;
    insEnvioTipoGo("otros"); await new Promise((s) => setTimeout(s, 50));
    out.sinFiltro = /JL Matriceria/.test(document.getElementById("insUbicGp2").innerText);
    insUbicCancel(); origCae = false;
    window.insGp2Rpc = async () => { throw new Error("caido"); };
    insEnvioTipoGo("otros"); await new Promise((s) => setTimeout(s, 50));
    out.caido = vis("insUbicInput") && vis("insUbicContinuar");
    return out;
  });
  await b.close();
  const ok = r.botones && r.cerv && r.otros && r.iny && r.obligatorio && r.sinFiltro && r.caido && !errs.length;
  console.log("ins-envio-tipo:", JSON.stringify(r), errs.length ? "· errores: " + errs.join(" | ") : "", ok ? "✓ OK" : "✗ FALLA");
  process.exit(ok ? 0 : 1);
})();
