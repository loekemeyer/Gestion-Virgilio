/* v24.32 — pestaña 🏦 Conciliación del submódulo Cobranzas (Luis, 29/09).
   v24.41 (Luis): "cuando la abrís, cuatro botones que te abran las conciliaciones en pop-ups ·
   una pestaña «Completar datos» · un badge rojo con número cuando hay datos a completar · cuatro
   botones más chicos para cargar el registro de movimientos".

   Mide, corriendo la pantalla de verdad:
     (a) la pestaña existe, abre en «🏦 Bancos» y pide gv_conc_salud + gv_conc_sin_identificar + gv_conc_tablero;
     (b) CUATRO tarjetas-botón (una por cuenta, aunque una no tenga planilla), con el % bien calculado;
     (c) el banco flojo se ve como flojo (Credicoop Chef: 12 de 606 = 2 %);
     (d) el badge rojo: en la pestaña Conciliación (total) y en la tarjeta de la cuenta que espera;
     (e) cuatro botones chicos para cargar el extracto de cada cuenta;
     (f) la tarjeta abre el POP-UP con la planilla y la línea amarilla del Excel; la pestaña
         «Sin identificar» del pop-up muestra el TEXTO del extracto;
     (g) «✍ Completar datos» lee gv_conc_pendientes_lista y muestra una tarjeta por movimiento.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}

(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ viewport: { width: 1400, height: 900 }, serviceWorkers: "block" });
  const p = await ctx.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {}; const calls = [];
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    window.alert = function () {}; window.requireSupervisor = function () { return true; };

    const salud = [
      { banco: "credicoop", empresa: "lk", movimientos: 26619, entradas: 13845, con_cliente: 12689,
        con_recibo: 10506, sin_identificar: 1110, monto_sin_identificar: 1031493020,
        primera: "2021-01-07", ultima: "2026-09-28", archivo: "CONCILIACION CREDICOOP LOEKE.xls" },
      { banco: "credicoop", empresa: "chef", movimientos: 4444, entradas: 606, con_cliente: 12,
        con_recibo: 16, sin_identificar: 589, monto_sin_identificar: 1022438804,
        primera: "2012-03-01", ultima: "2026-09-28", archivo: "BANCO CREDICOOP CHEF.xlsm" },
      { banco: "santander", empresa: "chef", movimientos: 3850, entradas: 1085, con_cliente: 1020,
        con_recibo: 1021, sin_identificar: 62, monto_sin_identificar: 315800781,
        primera: "2023-02-01", ultima: "2026-11-21", archivo: "Bco Santander Rio Chef.xlsm" }
    ];
    const sin = [
      { banco: "credicoop", empresa: "lk", fecha: "2026-09-26", entrada: 1250000,
        detalle: "TRANSFERENCIA RECIBIDA 30712345678 BAZAR MONICA", operacion: "TR", nro_op: "88213", tipo: null, observacion: null },
      { banco: "santander", empresa: "chef", fecha: "2026-09-24", entrada: 840000,
        detalle: "DEPOSITO EN EFECTIVO SUCURSAL 044", operacion: "DEP", nro_op: null, tipo: null, observacion: null }
    ];

    const tab = [
      { banco: "credicoop", empresa: "lk", conciliado_al: "2026-09-28", saldo_linea: 41404520.43, subido_en: "2026-09-29T16:44:00-03:00", preguntas: 0, propuestos: 0, movs_extracto: 0 },
      { banco: "santander", empresa: "chef", conciliado_al: "2026-09-25", saldo_linea: 15022977.39, subido_en: "2026-09-29T17:44:00-03:00", preguntas: 2, propuestos: 1, movs_extracto: 40, ultimo_extracto: "2026-09-25" },
      { banco: "credicoop", empresa: "chef", conciliado_al: "2026-09-28", saldo_linea: 946387.6, preguntas: 0, propuestos: 0 },
      { banco: "santander", empresa: "lk", conciliado_al: null, saldo_linea: null, preguntas: 0, propuestos: 0 }
    ];
    const plan = { conciliado_al: "2026-09-25", saldo_linea: 15022977.39, filas: [
      { fecha: "2026-09-25", operacion: "Deposito", entrada: 693000, saldo: 13946821.15, detalle: "SARALI SA", det: "D", nro_recibo: "4054", cod_cliente: "2448", proyectado: false },
      { fecha: "2026-09-25", operacion: "Gastos", salida: 19843.76, saldo: 15022977.39, detalle: "Gastos", det: "G", proyectado: false },
      { fecha: "2026-10-01", operacion: "A Depositar", entrada: 1057908.92, saldo: 16080886.31, detalle: "ALOE DARIO", det: "3", proyectado: true }
    ] };
    const pend = [
      { id: 13, banco: "santander", empresa: "chef", fecha: "2026-09-10", concepto: "Transferencia recibida - De dealbera", credito: 1290068.34, estado: "pregunta", candidatos: { lista: [] } },
      { id: 14, banco: "santander", empresa: "chef", fecha: "2026-09-24", concepto: "Deposito de efectivo en sucursal", credito: 20600, estado: "pregunta", candidatos: { lista: [] } },
      { id: 11, banco: "santander", empresa: "chef", fecha: "2026-09-25", concepto: "Deposito de efectivo en sucursal", credito: 693000, estado: "propuesto", cod_cliente: "2448", candidatos: { lista: [] } }
    ];
    const ok = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o), headers: { get: () => null } });
    window.fetch = async (url, opt) => {
      const u = String(url), m = /\/rpc\/([a-z_]+)/.exec(u);
      if (m) {
        calls.push(m[1]);
        if (m[1] === "gv_conc_salud") return ok(salud);
        if (m[1] === "gv_conc_sin_identificar") return ok(sin);
        if (m[1] === "gv_conc_movs") return ok([]);
        if (m[1] === "gv_conc_tablero") return ok(tab);
        if (m[1] === "gv_conc_planilla") return ok(plan);
        if (m[1] === "gv_conc_pendientes_lista") return ok(pend);
        return ok([]);
      }
      return ok([]);
    };

    await openCobranzas("conc");
    await espera(400);
    out.vistaInicial = ((document.querySelector("#cbzWrap .cbz-seg button.on") || {}).textContent || "").trim();
    out.pestanas = Array.from(document.querySelectorAll("#cbzTabs .cbz-tab")).map((x) => x.textContent.trim());
    out.tabActiva = (document.querySelector("#cbzTabs .cbz-tab.on") || {}).textContent || "";
    out.badgeTab = ((document.getElementById("cbzConcBadge") || {}).textContent || "").trim();
    out.pidio = calls.slice();

    const cards = Array.from(document.querySelectorAll("#cbzWrap .cbz-conccard.cbz-bank"));
    out.nCards = cards.length;
    out.cards = cards.map((c) => ({
      t: (c.querySelector(".t") || {}).textContent || "",
      p: ((c.querySelector(".p") || {}).textContent || "").trim(),
      badge: ((c.querySelector(".cbz-badge") || {}).textContent || "").trim()
    }));
    out.cargas = Array.from(document.querySelectorAll("#cbzWrap .cbz-cargas .cbz-cargar-s input[type=file]")).length;

    /* (f) la tarjeta de Santander CH abre el pop-up */
    const sant = cards.filter((c) => /SANTANDER/.test(c.textContent) && /CH/.test(c.textContent))[0];
    if (sant) sant.click();
    await espera(400);
    const pop = document.getElementById("cbzPop");
    out.popVisible = !!pop && pop.style.display !== "none";
    out.linea = ((document.getElementById("cbzPlLinea") || {}).textContent || "").trim();
    out.filasPlan = document.querySelectorAll("#cbzPop .cbz-plt tbody tr").length;
    out.pidioPlanilla = calls.filter((c) => c === "gv_conc_planilla").length;
    cbzCcPopTab("sin"); await espera(200);
    out.textoSin = (pop || {}).textContent || "";
    out.filasSin = document.querySelectorAll("#cbzPop .cbz-pop-body table.cbz-t tbody tr").length;
    cbzCcPopCerrar(); await espera(100);
    out.popCerrado = pop.style.display === "none";

    /* (g) Completar datos */
    cbzCcSetVista("completar"); await espera(400);
    out.pidioPend = calls.indexOf("gv_conc_pendientes_lista") >= 0;
    out.tarjetasCompletar = document.querySelectorAll("#cbzWrap .cbz-q").length;
    out.textoCompletar = (document.getElementById("cbzWrap") || {}).textContent || "";
    return out;
  });

  await b.close();

  const fallas = [];
  const q = (c, m) => { if (!c) fallas.push(m); };

  q((r.pestanas || []).some((t) => /Conciliaci/.test(t)), "(a) no está la pestaña Conciliación: " + JSON.stringify(r.pestanas));
  q(/Conciliaci/.test(r.tabActiva || ""), "(a) openCobranzas('conc') no abrió en Conciliación (abrió en " + r.tabActiva + ")");
  q(/Bancos/.test(r.vistaInicial || ""), "(a) la pestaña tiene que abrir en «🏦 Bancos», abrió en " + JSON.stringify(r.vistaInicial));
  ["gv_conc_salud", "gv_conc_sin_identificar", "gv_conc_tablero"].forEach((f) =>
    q((r.pidio || []).indexOf(f) >= 0, "(a) no pidió " + f));

  q(r.nCards === 4, "(b) esperaba 4 tarjetas-botón (una por cuenta), hay " + r.nCards);
  const lk = (r.cards || []).filter((c) => /CREDICOOP/.test(c.t) && /LK/.test(c.t))[0];
  const ch = (r.cards || []).filter((c) => /CREDICOOP/.test(c.t) && /CH/.test(c.t))[0];
  const sch = (r.cards || []).filter((c) => /SANTANDER/.test(c.t) && /CH/.test(c.t))[0];
  q(lk && /92 %/.test(lk.p), "(b) Credicoop LK: 12.689 de 13.845 es 92 %, dice " + JSON.stringify(lk && lk.p));
  q(ch && /^2 %/.test((ch.p || "").trim()), "(c) Credicoop Chef: 12 de 606 es 2 %, dice " + JSON.stringify(ch && ch.p));

  q(r.badgeTab === "3", "(d) el badge de la pestaña tiene que decir 3 (2 preguntas + 1 propuesto), dice " + JSON.stringify(r.badgeTab));
  q(sch && sch.badge === "3" && lk && !lk.badge, "(d) el badge va en la tarjeta que espera (Santander CH = 3) y en ninguna otra: " + JSON.stringify(r.cards));

  q(r.cargas === 4, "(e) esperaba 4 botones chicos de carga de extracto, hay " + r.cargas);

  q(r.popVisible, "(f) tocar la tarjeta tiene que abrir el pop-up");
  q(r.pidioPlanilla === 1, "(f) el pop-up tiene que pedir gv_conc_planilla una vez, pidió " + r.pidioPlanilla);
  q(/conciliado al 25\/09\/26/.test(r.linea), "(f) falta la línea amarilla «conciliado al 25/09/26»: " + JSON.stringify(r.linea));
  q(r.filasPlan === 4, "(f) la planilla tiene 3 filas + la línea amarilla = 4, hay " + r.filasPlan);
  q(/BAZAR MONICA/.test(r.textoSin || "") === false && /DEPOSITO EN EFECTIVO/.test(r.textoSin || ""),
    "(f) «Sin identificar» del pop-up muestra SÓLO lo de esa cuenta (Santander CH), con el texto del extracto");
  q(r.filasSin === 1, "(f) Santander CH tiene 1 entrada sin identificar, hay " + r.filasSin);
  q(r.popCerrado, "(f) «Cerrar» tiene que cerrar el pop-up");

  q(r.pidioPend, "(g) «Completar datos» tiene que leer gv_conc_pendientes_lista");
  q(r.tarjetasCompletar === 3, "(g) esperaba una tarjeta por movimiento a completar (3), hay " + r.tarjetasCompletar);
  q(/Confirmar los 1 propuestos/.test(r.textoCompletar || ""), "(g) falta «Confirmar los 1 propuestos»");

  if (errs.length) fallas.push("errores de JS en la página: " + errs.join(" | "));

  if (fallas.length) {
    console.log("cbz-conciliacion: FALLA");
    fallas.forEach((f) => console.log("  - " + f));
    process.exit(1);
  }
  console.log("cbz-conciliacion: OK — abre en Bancos: 4 tarjetas-botón con el % (LK 92 %, Chef 2 %), badge rojo " +
    "en la pestaña y en la cuenta que espera, 4 botones de carga, pop-up con la línea amarilla y lo sin identificar " +
    "de esa cuenta, y «Completar datos» con una tarjeta por movimiento.");
  process.exit(0);
})();
