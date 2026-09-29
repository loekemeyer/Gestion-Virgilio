/* v23.86 (Luis) — tarjeta «¿Llegan?» de monitor/tv.html: se arma hoy lo que sale 2 hábiles después.
   Ritmo = m³ terminados hoy (½ picking + ½ armado) ÷ horas desde las 8; capacidad = ritmo × horas
   hasta las 17. Si no alcanza, se pasan a otro día los ÚLTIMOS camiones del orden (un camión entero,
   no dos a medias), y desde las 15:00 sale el cartel de CORTE.
   Lunes 28/09 → meta miércoles 30/09. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage(); const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/*supabase.co/**", r => r.fulfill({ status: 200, contentType: "application/json", body: "[]" }));
  await p.clock.install({ time: new Date("2026-09-28T15:10:00-03:00").getTime() });
  await p.goto("file://" + path.join(__dirname, "..", "monitor", "tv.html") + "?key=tv", { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const out = {};
    // meta = miércoles 30/09. Camión 1 (grande) 2 m³, camión 2 (chico) 1 m³, nada hecho de ellos.
    // Hoy se terminaron 7 m³ de trabajo en 7 h (ritmo 1 m³/h) → hasta las 17 hacen ~1,83 m³.
    const T = window.__tvMeta, calcularMeta = T.calcular, pintarMeta = T.pintar;
    T.camiones(new Map([["G1", { camion: "Capital Oeste", usa: true, orden: 1 }], ["C1", { camion: "GBA Sur", usa: true, orden: 2 }]]));
    const prog = new Map([
      ["G1", { tanda: "G1", fechaRaw: "2026-09-30", m3: 1.8, nps: ["1"] }],
      ["C1", { tanda: "C1", fechaRaw: "2026-09-30", m3: 1, nps: ["2"] }],
      ["H1", { tanda: "H1", fechaRaw: "2026-09-29", m3: 7, nps: ["3"] }]
    ]);
    const status = new Map([["H1", { picking: "done", armado: "done" }]]);
    const eventos = [
      { opcion: "TP", texto: "H1", ts_cliente: "2026-09-28T12:00:00-03:00", ts_inicio: "2026-09-28T09:00:00-03:00" },
      { opcion: "TAP", texto: "H1", ts_cliente: "2026-09-28T14:00:00-03:00", ts_inicio: "2026-09-28T12:00:00-03:00" }
    ];
    const d = { prog, status, eventos, despachadas: new Set() };
    const M = calcularMeta(d);
    out.meta = M.meta; out.cap = Math.round(M.capacidad * 100) / 100;
    out.metaMie = M.meta === "2026-09-30";
    out.orden = M.cams.map(c => c.cam + ":" + c.llega).join(",");


    const eventos2 = eventos.concat([{ opcion: "TP", texto: "C1", ts_cliente: "2026-09-28T15:00:00-03:00", ts_inicio: "2026-09-28T14:30:00-03:00" }]);
    status.set("C1", { picking: "done" });
    const M2 = calcularMeta({ prog, status, eventos: eventos2, despachadas: new Set() });
    // ahora C1 queda con 0,5 de trabajo; hecho 7,5 → capacidad ~1,92; falta 2,3 → se patea C1 (último) y G1 llega

    out.orden2 = M2.cams.map(c => c.cam + ":" + c.llega).join(",");
    out.pateaElUltimo = out.orden2 === "Capital Oeste:true,GBA Sur:false";
    const cartel = pintarMeta({ prog, status, eventos: eventos2, despachadas: new Set() });
    out.corte = /CORTE 15:00/.test(cartel) && /GBA Sur/.test(cartel) && !/Capital Oeste/.test(cartel);
    out.veredicto = document.getElementById("metaBox").textContent.indexOf("NO LLEGAN") >= 0;
    return out;
  });
  const pass = r.metaMie && r.pateaElUltimo && r.corte && r.veredicto && errs.length === 0;
  console.log("tv-meta-camion:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
