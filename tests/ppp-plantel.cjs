/* v29.46 — PPP → Plantel de la semana (plantel.js). Corre la pantalla de verdad dentro de
   index.html con la RPC gv_ppp_plantel mockeada y mide:
     (a) la solapa «Plantel» está en la barra de la PPP y pppRenderProg la intercepta;
     (b) la cuenta: horas = m³ ÷ m³/h medido, tareas fijas = por día × hábiles, personas =
         horas ÷ (horas útiles × hábiles), redondeado para ARRIBA (números de la base del 12/10);
     (c) las horas van en H:MM y los m³ con coma decimal;
     (d) las horas útiles cargadas a mano cambian las personas;
     (e) una lectura que FALLA se dice, no se dibuja como 0 personas.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

const DATA = {
  hoy: "2026-10-12", lunes: "2026-10-19", desde: "2026-10-19", hasta: "2026-10-23", habiles: 5, habiles_antes: 4,
  meta: 10, dias_antes: 2,
  dias: [{ dia: "2026-10-19", habil: true }, { dia: "2026-10-20", habil: true }, { dia: "2026-10-21", habil: true }, { dia: "2026-10-22", habil: true }, { dia: "2026-10-23", habil: true }],
  hist: { dias: 20, desde: "2026-09-14", hasta: "2026-10-11", ops_dia: 3.5, hs_pick: 88.3, hs_arm: 200.9, hs_carga: 75.2, hs_mov: 116.4,
          m3_pick: 100.47, m3_arm: 96.71, ritmo_pick: 1.137, ritmo_arm: 0.481, carga_dia: 3.76, mov_dia: 5.82,
          util_persona_dia: 6.97, jornada_persona_dia: 8.42, m3_dia_pick: 5.02, m3_dia_arm: 4.84 },
  demanda_semana: 32.2,
  pendiente: { nps: 99, m3_pick: 46.87, m3_arm: 49.76, m3_vencido: 11.98, nps_vencidas: 13, pedido_mas_viejo: "2026-09-15",
               habiles_mas_viejo: 18, ultima_fecha_prog: "2026-11-19",
               por_semana_limite: [{ semana: "2026-09-21", m3_pick: 3.23, m3_arm: 3.23 }, { semana: "2026-10-19", m3_pick: 20.26, m3_arm: 20.79 }] },
  semana: { oblig_pick: 26.77, oblig_arm: 30.41, no_acumular: 32.2, m3_pick: 32.2, m3_arm: 32.2 }
};

(async () => {
  const b = await chromium.launch();
  const p = await (await b.newContext({ viewport: { width: 1300, height: 900 }, serviceWorkers: "block" })).newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  let modo = "ok", llamadas = 0;
  await p.route("**/rest/v1/**", (r) => {
    if (/rpc\/gv_ppp_plantel/.test(r.request().url())) {
      llamadas++;
      if (modo === "error") return r.fulfill({ status: 500, contentType: "application/json", body: '{"message":"canceling statement"}' });
      return r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(DATA) });
    }
    return r.abort();
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const out = await p.evaluate(async () => {
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    for (let i = 0; i < 50 && typeof window.plantelHtml !== "function"; i++) await espera(100);
    const o = {};
    try { localStorage.removeItem("gv_plantel_cfg"); } catch (_e) {}
    _plantel.util = null;
    o.tab = /b\("plantel"/.test(String(pppTabsHtml)) && /Plantel/.test(pppTabsHtml(1, 1, 1, 1));
    o.intercepta = /_pppTab === "plantel"[\s\S]{0,200}plantelHtml/.test(String(pppRenderProg));
    plantelCargar(true);
    for (let i = 0; i < 40 && !_plantel.data && !_plantel.err; i++) await espera(50);
    const c = plantelCalc(_plantel.data, null);
    o.total = Math.round(c.total * 100) / 100;
    o.personas = c.personas; o.exacto = Math.round(c.exacto * 100) / 100;
    o.orden = c.filas.map((f) => f.k).join(",");
    const div = document.createElement("div"); div.innerHTML = plantelHtml(); document.body.appendChild(div);
    o.txt = div.textContent;
    _plantel.util = 9;
    o.personas9 = plantelCalc(_plantel.data, _plantel.util).personas;
    _plantel.util = null;
    return o;
  });
  modo = "error";
  const err = await p.evaluate(async () => {
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    plantelCargar(true);
    for (let i = 0; i < 40 && !_plantel.err; i++) await espera(50);
    return { err: _plantel.err, html: plantelHtml() };
  });
  await b.close();

  const fallas = [];
  const ok = (c, m) => { if (!c) fallas.push(m); };
  ok(out.tab, "(a) falta la solapa Plantel en la barra de la PPP");
  ok(out.intercepta, "(a) pppRenderProg no intercepta la solapa plantel");
  // 32,2/1,137 = 28,32 · 32,2/0,481 = 66,94 · 3,76×5 = 18,8 · 5,82×5 = 29,1 → 143,16 h
  ok(Math.abs(out.total - 143.16) < 0.05, "(b) total de horas " + out.total + " (esperado 143,16)");
  ok(Math.abs(out.exacto - 4.11) < 0.02, "(b) personas exactas " + out.exacto + " (esperado 4,11)");
  ok(out.personas === 5, "(b) personas redondeadas para arriba: " + out.personas + " (esperado 5)");
  ok(out.orden === "arm,mov,pick,carga", "(b) las tareas van de más horas a menos: " + out.orden);
  ok(/143:10/.test(out.txt), "(c) el total va en H:MM (143:10)");
  ok(/66:57/.test(out.txt) && /28:19/.test(out.txt), "(c) armado 66:57 y picking 28:19 en H:MM");
  ok(/32,20/.test(out.txt) && !/32\.20/.test(out.txt), "(c) m³ con coma decimal");
  ok(/13 NP/.test(out.txt), "(c) muestra las NP que ya pasaron la demora");
  ok(out.personas9 === 4, "(d) con 9 h útiles por persona son 4 personas, dio " + out.personas9);
  ok(/No se pudo leer/.test(err.err) && /No se pudo leer/.test(err.html) && !/personas toda la semana/.test(err.html), "(e) una lectura rota se dice, no muestra personas");
  ok(errs.length === 0, "errores de página: " + errs.join(" | "));
  if (fallas.length) { console.log("FALLA ppp-plantel:\n  " + fallas.join("\n  ")); process.exit(1); }
  console.log("OK ppp-plantel — " + out.personas + " personas, " + out.total + " h, " + llamadas + " llamadas");
})().catch((e) => { console.error(e); process.exit(1); });
