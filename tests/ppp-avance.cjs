/* v16.97 — AVANCE DEL DÍA en la PPP: "85 % listo · 60 % armado".
   Verifica (a) que el front pide el dato a la RPC del backend gv_ppp_avance_dias con el rango
   de días que está mirando (el número NO se calcula en el front: tiene que ser el mismo que
   manda el Telegram de las 16 y la tarea de Planify), (b) que la tarjeta grande de un día
   muestra los dos porcentajes y lo que falta armar, (c) que la tarjeta de la grilla de 6 días
   muestra la línea chiquita, y (d) que con el día completo cambia el cartel. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const fila = (f, o) => Object.assign({
      fecha: f, pedidos: 20, m3: 7.12, pick_ped: 17, pick_m3: 6.05, arm_ped: 12, arm_m3: 4.27,
      curso_ped: 5, sin_ped: 3, pct_listo: 85, pct_armado: 60, pct_listo_ped: 85,
      pct_armado_ped: 60, pct_listo_m3: 85, pct_armado_m3: 60, base: "m3",
      curso_m3: 1.78, sin_m3: 1.07, fact_ped: 5, fact_m3: 1.71, pct_fact: 40,
      pct_curso: 25, pct_sin: 15
    }, o || {});

    // (a) pide el rango a la RPC del backend
    const calls = [];
    const realFetch = window.fetch;
    window.fetch = async (url, opt) => {
      const u = String(url);
      if (/\/rpc\/gv_ppp_avance_dias/.test(u)) {
        calls.push(JSON.parse((opt && opt.body) || "{}"));
        return { ok: true, status: 200, json: async () => [fila("2026-09-15"), fila("2026-09-16", { pedidos: 0, m3: 0, pick_ped: 0, pick_m3: 0, arm_ped: 0, arm_m3: 0, curso_ped: 0, sin_ped: 0, pct_listo: 0, pct_armado: 0, pct_listo_ped: 0, pct_armado_ped: 0, pct_curso: 0, pct_sin: 0, fact_ped: 0, fact_m3: 0, pct_fact: 0, base: "pedidos" })] };
      }
      return realFetch(url, opt);
    };
    _pppAvance = null; _pppAvanceTs = 0; _pppAvanceRango = ""; _pppAvanceBusy = false;
    pppAvanceNeed("20260915", "20260916");
    await new Promise((res) => setTimeout(res, 300));
    out.calls = calls;
    out.cargo = !!(_pppAvance && _pppAvance.get("20260915"));

    // (b) tarjeta grande de UN día
    out.dia = _pppAvanceHtml("20260915");
    // (c) la barra de la grilla: % visibles + segunda barra de facturado
    const est = { armado: 12, curso: 5, sin: 3 };
    out.barra = _pppPlanBarraHtml(est, 20, "20260915");
    // adentro de un día el facturado va en la tarjeta, no en la barra
    out.barraDia = _pppPlanBarraHtml(est, 20, "20260915", true);
    // sin dato del backend la barra igual se dibuja, con el conteo de pedidos
    out.barraSinDato = _pppPlanBarraHtml(est, 20, "20261231");
    // día sin pedidos: no dibuja nada
    out.vacio = _pppAvanceHtml("20260916");
    // (d) día completo
    _pppAvance.set("20260917", fila("2026-09-17", { arm_ped: 20, arm_m3: 7.12, pick_ped: 20, pick_m3: 7.12, curso_ped: 0, sin_ped: 0, pct_listo: 100, pct_armado: 100 }));
    out.completo = _pppAvanceHtml("20260917");
    return out;
  });

  const fail = [];
  const ok = (c, m) => { if (!c) fail.push(m); };
  ok(r.calls.length === 1, "esperaba 1 llamada a gv_ppp_avance_dias, hubo " + r.calls.length);
  ok(r.calls[0] && r.calls[0].p_desde === "2026-09-15" && r.calls[0].p_hasta === "2026-09-16",
     "rango mal armado: " + JSON.stringify(r.calls[0]));
  ok(r.cargo, "no guardó la respuesta en _pppAvance");
  ok(/85 %<\/b>listo/.test(r.dia), "falta el % listo en la tarjeta del día");
  ok(/60 %<\/b>armado/.test(r.dia), "falta el % armado en la tarjeta del día");
  ok(/Armado 12 de 20 pedidos/.test(r.dia), "falta el detalle de pedidos armados");
  ok(/falta armar <b>8 pedidos<\/b>/.test(r.dia), "falta lo que queda por armar: " + r.dia);
  ok(/width:85%/.test(r.dia) && /width:60%/.test(r.dia), "la barra no refleja los dos %");
  ok(/40 %<\/b>facturado/.test(r.dia), "falta el % facturado en la tarjeta del día");
  ok(/5 de 12 pedidos · 1,7 de 4,3 m³/.test(r.dia), "falta el detalle de facturado: " + r.dia);
  ok(/<b>60 %<\/b>armado/.test(r.barra) && /<b>25 %<\/b>en curso/.test(r.barra) && /<b>15 %<\/b>sin empezar/.test(r.barra),
     "la barra de la grilla no muestra los tres porcentajes: " + r.barra);
  ok(/pn-bar big/.test(r.barra), "la barra de estado no es la gruesa");
  ok(/pn-facw/.test(r.barra) && /Facturado/.test(r.barra) && /<b>40 %<\/b>/.test(r.barra) && /5 de 12 armados/.test(r.barra),
     "falta la segunda barra (facturado sobre lo armado): " + r.barra);
  ok(/width:60%/.test(r.barra) && /width:25%/.test(r.barra) && /width:15%/.test(r.barra), "los anchos no siguen los %");
  ok(!/pn-facw/.test(r.barraDia), "adentro de un día el facturado va en la tarjeta, no en la barra");
  ok(/<b>60 %<\/b>armado/.test(r.barraSinDato) && /pn-facw/.test(r.barraSinDato) && /buscando…/.test(r.barraSinDato),
     "sin dato del backend: % por conteo de pedidos y la barra de facturado visible pero vacía: " + r.barraSinDato);
  ok(r.vacio === "", "un día sin pedidos no tiene que dibujar nada: " + r.vacio);
  ok(/ya está todo armado/.test(r.completo) && /pn-av ok/.test(r.completo), "el día completo no avisa que está todo armado");
  ok(!errs.length, "errores de página: " + errs.join(" | "));

  await b.close();
  if (fail.length) { console.error("ppp-avance FALLÓ:\n - " + fail.join("\n - ")); process.exit(1); }
  console.log("ppp-avance: OK — % listo / % armado del día salen de la RPC del backend.");
})();
