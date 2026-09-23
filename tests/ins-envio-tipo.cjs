/* v21.74 — Entregar insumos: primero "Envío a inyectores" / "Envío a otros".
   Inyectores → sólo la lista de GP2 (sin texto libre); si GP2 no responde, abre el texto libre.
   Otros → sólo texto libre, sin llamar a GP2. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); } catch (_e) { ({ chromium } = require("playwright")); }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage(); const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const vis = (id) => { const e = document.getElementById(id); return !!e && e.offsetParent !== null; };
    let rpc = 0;
    window.insGp2Rpc = async () => { rpc++; return { inyectores: ["JL Matriceria", "Kollplast"], materiales: [] }; };
    insChooserGo("EI");
    const ch = document.getElementById("insChooserModal").innerText;
    const out = { botones: /Envío a inyectores/.test(ch) && /Envío a otros/.test(ch) };
    insEnvioTipoGo("otros");
    out.otros = vis("insUbicInput") && vis("insUbicContinuar") && rpc === 0 && !/inyector/i.test(document.getElementById("insUbicGp2").innerText);
    insUbicCancel();
    insEnvioTipoGo("iny"); await new Promise((s) => setTimeout(s, 50));
    const g = document.getElementById("insUbicGp2").innerText;
    out.iny = /JL Matriceria/.test(g) && /Kollplast/.test(g) && !vis("insUbicInput") && !vis("insUbicContinuar") && !/otro destino/.test(g);
    insUbicCancel();
    window.insGp2Rpc = async () => { throw new Error("caido"); };
    insEnvioTipoGo("iny"); await new Promise((s) => setTimeout(s, 50));
    out.caido = vis("insUbicInput") && vis("insUbicContinuar");
    return out;
  });
  await b.close();
  const ok = r.botones && r.otros && r.iny && r.caido && !errs.length;
  console.log("ins-envio-tipo:", JSON.stringify(r), errs.length ? "· errores: " + errs.join(" | ") : "", ok ? "✓ OK" : "✗ FALLA");
  process.exit(ok ? 0 : 1);
})();
