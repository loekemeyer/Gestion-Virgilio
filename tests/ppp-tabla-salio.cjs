/* v20.09 (Thomas, 2026-09-18) — COLUMNA «SALIÓ» en la tabla de Programación.
   Pedido: *"agregá columna a esa visión que sea SALIÓ a la izquierda de FACTURADO que busque en el
   módulo En salida para ver si esa tanda/NP ya salió en el camión"*.
   Lo que prueba:
     (1) la columna va 5ª, a la izquierda de Facturado, y tiene su color propio;
     (2) cuenta como SALIDA la NP cargada al camión (CCN), la dada por salida a mano y la salida
         presunta — y NO la facturada que nunca se cargó, que sigue en el depósito;
     (3) suma la NP que ya volvió con el remito (CRN): ésa se fue de «En Salida», pero salió;
     (4) el % es por día y por tanda, y la fila de la NP lleva su chip 🚚;
     (5) mientras las dos fuentes no llegaron, dice «—» y no 0 % (un 0 % sería mentira).
   Estado inyectado; no pega contra la red. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 1000 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    window.getTodayKey = () => "2026-09-18";
    _pppParsed = { prog: [{ np: "98630", tanda: "E39A", fecha_entrega: "2026-09-18", m3: 1.8,
                            cod: "1000", razon_social: "Jumbo", zona: "Zona 2", programmed: true }] };
    window._pppPlanAgrupar = function () { return { venc: [], byDay: new Map() }; };
    window.pppPaintTabs = function () {};
    window.pgaNeed = function () {};
    const mk = (f, t, np, est) => ({ fecha: f, tanda: t, np: np, np_num: 0, cod: "1000",
      razon_social: "Cliente " + np, localidad: "Barracas", zona: "Zona 2", zona_corta: "Zona 2",
      empresa: "LK", origen: "isis", m3: 1, estado: est, estado_orden: 1, barrio: "Flores",
      fecha_pedido: "2026-09-11" });
    // Un día con 5 NP en una tanda: 4 salieron (cada una por un camino distinto) y 1 no.
    _pgaRows = [
      mk("2026-09-22", "E41A", "98001", "facturado"),   // CCN → cargada
      mk("2026-09-22", "E41A", "98002", "facturado"),   // la dio por salida un supervisor
      mk("2026-09-22", "E41A", "98003", "armado"),      // salida presunta (armada +36 h sin papel)
      mk("2026-09-22", "E41A", "98004", "facturado"),   // facturada SIN cargar → no salió
      mk("2026-09-22", "E41A", "98005", "facturado")    // ya volvió con el remito → salió
    ];
    _pgaTs = Date.now();
    _pppTab = "plan"; _pppPlanTabla = true; _pppPlanClasica = false; _pppPlanDay = null;
    document.getElementById("pppOverlay").classList.add("show");

    // (5) primero, SIN ninguna de las dos fuentes
    _pppEnSalida = null; _pppLoadMs = null;
    pppRenderProg(); await new Promise((s) => setTimeout(s, 200));
    const prev = document.getElementById("pppPreview");
    out.sinDatos = (prev.querySelector("tr.pga-d .pga-pct.sal") || {}).textContent;

    // y ahora con las dos
    _pppEnSalida = new Map([
      ["98001", { np: "98001", cargada: true,  estado: "cargada" }],
      ["98002", { np: "98002", cargada: false, estado: "salida_manual" }],
      ["98003", { np: "98003", cargada: false, estado: "armada_sin_carga" }],
      ["98004", { np: "98004", cargada: false, estado: "facturada_sin_cargar" }]
    ]);
    _pppLoadMs = new Map([["98005", Date.now()]]);   // ya entregada: salió de En Salida, pero salió
    pppRenderProg(); await new Promise((s) => setTimeout(s, 200));

    const dia = [...prev.querySelectorAll("tr.pga-d")].find((tr) => /22\/09/.test(tr.textContent));
    out.thClases = [...prev.querySelectorAll("table.pga thead th")].map((e) => e.className);
    out.thSalio = (prev.querySelectorAll("table.pga thead th")[4] || {}).textContent;
    out.color = (function () {
      const e = dia.querySelector(".pga-pct.sal");
      return e ? getComputedStyle(e).color : "";
    })();
    out.pctDia = (dia.querySelector(".pga-pct.sal") || {}).textContent;
    out.salioUno = _pgaSalio({ np: "98001" }) + "," + _pgaSalio({ np: "98002" }) + "," +
                   _pgaSalio({ np: "98003" }) + "," + _pgaSalio({ np: "98004" }) + "," +
                   _pgaSalio({ np: "98005" });

    pgaAbrirDia("20260922"); await new Promise((s) => setTimeout(s, 120));
    const tanda = [...prev.querySelectorAll("tr.pga-t")][0];
    out.pctTanda = (tanda.querySelector(".pga-pct.sal") || {}).textContent;
    pgaAbrirTanda("20260922|E41A"); await new Promise((s) => setTimeout(s, 120));
    out.chips = [...prev.querySelectorAll("tr.pga-n")].map((tr) =>
      (tr.querySelector(".pga-np") || {}).textContent + ":" + (tr.querySelector(".pga-salio") ? "🚚" : "—"));
    out.total = ([...prev.querySelectorAll("table.pga tfoot .pga-pct.sal")][0] || {}).textContent;
    return out;
  });
  await b.close();

  let ok = true;
  const t = (c, m) => { console.log((c ? "  ✅ " : "  ❌ ") + m); if (!c) ok = false; };
  t(r.thClases.length === 9 && /sal/.test(r.thClases[4]) && /fac/.test(r.thClases[5]),
    "(1) SALIÓ es la 5ª columna, justo a la izquierda de Facturado — " + JSON.stringify(r.thClases));
  t(/Salió/.test(r.thSalio || ""), "(1) y se llama «Salió» — «" + r.thSalio + "»");
  t(/109|violeta|124/.test(r.color) || /rgb\(109, 40, 217\)/.test(r.color),
    "(1) con su color propio, distinto de los 4 estados — " + r.color);
  t(r.salioUno === "true,true,true,false,true",
    "(2)(3) cargada, salida a mano, salida presunta y entregada SALIERON; la facturada sin cargar NO — " + r.salioUno);
  t(r.pctDia === "80 %4", "(4) el día dice 80 % (4 de 5) — «" + r.pctDia + "»");
  t(r.pctTanda === "80 %4", "(4) y la tanda lo mismo — «" + r.pctTanda + "»");
  t(r.total === "80 %4", "(4) igual que el total de abajo — «" + r.total + "»");
  const espera = ["98001:🚚", "98002:🚚", "98003:🚚", "98004:—", "98005:🚚"];
  t(JSON.stringify(r.chips) === JSON.stringify(espera),
    "(4) y cada NP lleva su chip 🚚 salvo la que no salió — " + JSON.stringify(r.chips));
  t(r.sinDatos === "—", "(5) sin las dos fuentes cargadas dice «—», no 0 % — «" + r.sinDatos + "»");
  t(errs.length === 0, "sin errores de JS" + (errs.length ? ": " + errs[0] : ""));
  console.log(ok ? "\nOK ppp-tabla-salio" : "\nFALLÓ ppp-tabla-salio");
  process.exit(ok ? 0 : 1);
})();
