/* Regresión (v12.86): una NP web llega a Facturación y se factura con su etiqueta.

   El agujero que tapa: `facFetchArmadosEventos` descartaba cualquier NP que no fuera
   numérica (/^\d+$/), así que el TAP de una NP web ("LK 1344") nunca contaba como
   "armada", `facEstaArmada` daba false y la fila no se dibujaba. El circuito web
   moría en Facturación, en silencio.

   Verifica que:
   (a) con un TAP de "LK 1344" en los eventos, facEstaArmada("LK 1344") sea true, y
       que un texto de tanda suelto ("C03B") se siga descartando como antes,
   (b) facTick() dibuje la fila de la NP web al lado de la de ISIS,
   (c) el tilde escriba en Facturacion_NP con np = "LK 1344" (la etiqueta, no un número),
   (d) el drenaje de stock de esa NP mande empresa = "LK" explícita (ref "GV-02A|LK 1344"
       tiene dígitos 01344 y el trigger, sin la empresa, la leería como Chef),
   (e) el drenaje de una NP de ISIS NO mande empresa (no cambia nada de lo de siempre),
   (f) pkNpEsLoeke y _facXlsEmpresa entiendan la etiqueta y sigan iguales para ISIS. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const posts = [];
    const stockRows = [];
    window.alert = function () {};
    window.confirm = function () { return true; };

    function J(data) {
      const n = Array.isArray(data) ? data.length : 0;
      return Promise.resolve({
        ok: true, status: 200,
        headers: { get: function (h) { return String(h).toLowerCase() === "content-range" ? ("0-" + Math.max(0, n - 1) + "/" + n) : null; } },
        json: function () { return Promise.resolve(data); },
        text: function () { return Promise.resolve(JSON.stringify(data)); }
      });
    }

    window.fetch = function (url, opts) {
      url = String(url);
      const method = (opts && opts.method) || "GET";
      if (method === "POST" && url.indexOf("Facturacion_NP") >= 0) { posts.push(JSON.parse(opts.body)); return J([]); }
      // la tanda web programada desde la PPP Web
      if (url.indexOf("PPP_Web_Programacion") >= 0) return J([
        { empresa: "lk", np: 1344, tanda: "GV-02A", zona: "Zona 1", fecha_entrega: "2026-09-11",
          cod_cliente: "4188", razon_social: "Orfali", direccion: "Juncal 2869", barrio: "Martinez", m3: 1.184 }
      ]);
      // las dos tandas tienen picking + armado terminados
      if (url.indexOf("vista_tanda_status") >= 0) return J([{ tanda: "GV-02A" }, { tanda: "C03B" }]);
      // eventos de armado: uno web, uno ISIS, y un texto de tanda suelto (basura de siempre)
      if (url.indexOf("opcion=in.(TAL,TAP)") >= 0) return J([
        { opcion: "TAP", texto: "LK 1344|55|GV-02A|A=586X1|NADA" },
        { opcion: "TAL", texto: "98574|3|C03B|A=100X2|LIO" },
        { opcion: "TAP", texto: "C03B" }
      ]);
      // composición TAL de cada NP (para el drenaje de a_facturar)
      if (url.indexOf("opcion=eq.TAL") >= 0) {
        if (url.indexOf("LK%201344") >= 0 || url.indexOf("LK 1344") >= 0) return J([{ texto: "LK 1344|0|GV-02A|A=586X1|NADA", ts_cliente: "2026-09-11T12:00:00Z" }]);
        if (url.indexOf("98574") >= 0) return J([{ texto: "98574|0|C03B|A=100X2|LIO", ts_cliente: "2026-09-11T12:00:00Z" }]);
        return J([]);
      }
      return J([]);
    };

    // El mapa de ISIS trae su propia tanda; la web se le suma por mergeMonitorPppWeb.
    window.fetchMonitorFromSupabase = async () => new Map([
      ["C03B", { tanda: "C03B", _key: "C03B", m3: 0.5, fechaEntrega: "11/09", fechaEntregaRaw: "2026-09-11",
                 opIsSi: false, pedidos: [{ np: "98574", m3: 0.5, razonSocial: "Osa", cod: "2533", direccion: "", barrio: "", zona: "" }] }]
    ]);
    window.facAuthWriteHeaders = async () => ({ apikey: "x", Authorization: "Bearer x", "Content-Type": "application/json" });
    window._stockAfacturarRestanteTanda = async () => ({ "586": { sum: 5, desc: "Colador" }, "100": { sum: 9, desc: "Cuchillo" } });
    window.stockMove = async (rows) => { stockRows.push.apply(stockRows, rows || []); };
    window.facMaybePrintFacturado = function () {};

    // (a) el fallback de "está armada" acepta la etiqueta
    await facFetchArmadosEventos();
    out.armadaWeb   = facEstaArmada("LK 1344");
    out.armadaIsis  = facEstaArmada("98574");
    out.basuraFuera = !facEstaArmada("C03B");

    // (b) la fila aparece
    await facTick();
    const html = (document.getElementById("facContainer") || {}).innerHTML || "";
    out.filaWeb  = html.indexOf('data-fac-np="LK 1344"') >= 0;
    out.filaIsis = html.indexOf('data-fac-np="98574"') >= 0;
    out.tandasFC = (_facLastTandas || []).map(t => t.tanda).sort().join(",");

    // v12.93 — regla del dueño: la NP web NO se tilda (se factura bajando el Excel ISIS)
    // y la de ISIS NO va al Excel (se tilda). La fila lo refleja:
    const filaWeb = html.slice(html.indexOf('data-fac-np="LK 1344"'), html.indexOf('</tr>', html.indexOf('data-fac-np="LK 1344"')));
    out.webSinTilde   = filaWeb.length > 0 && filaWeb.indexOf("fac-btn-tick") < 0 && filaWeb.indexOf("fac-tick-web") >= 0;
    out.webConCasilla = /class="fac-xls-chk" data-np="LK 1344"/.test(filaWeb);
    const filaIsis = html.slice(html.indexOf('data-fac-np="98574"'), html.indexOf('</tr>', html.indexOf('data-fac-np="98574"')));
    out.isisConTilde  = filaIsis.indexOf("fac-btn-tick") >= 0;
    out.isisSinCasilla = filaIsis.indexOf("fac-xls-chk") < 0;

    // (c) el tilde sobre una NP web se niega: no escribe nada
    const btn = document.createElement("button");
    btn.dataset.args = JSON.stringify({ np: "LK 1344", tanda: "GV-02A", m3: 1.184, rs: "Orfali", cod: "4188", feRaw: "2026-09-11" });
    await window.facTickNP(btn);
    out.tildeWebNoEscribe = posts.length === 0;

    // (d) bajar el Excel con la NP web marcada = facturada (Facturacion_NP + drenaje)
    window.requireSupervisor = () => true;
    window._facXlsArmar = async (nps) => nps.map(np => ({ np: np, cod_art: "586", cajas: 1 }));
    window._facXlsDescargarXlsx = () => {};
    window._facXlsDescargar = () => {};
    _facXlsSel = new Set(["LK 1344", "98574"]);   // la de ISIS se tiene que caer sola
    await facXlsBajar();
    out.isisSacadaDelExcel = !_facXlsSel.has("98574");
    out.postNp    = posts.length ? posts[0].np : null;
    out.postTanda = posts.length ? posts[0].tanda : null;
    out.postsN    = posts.length;
    const drenWeb = stockRows.filter(x => x.ref === "GV-02A|LK 1344");
    out.drenWebN       = drenWeb.length;
    out.drenWebEmpresa = drenWeb.length ? drenWeb[0].empresa : null;
    out.drenWebDelta   = drenWeb.length ? drenWeb[0].delta : null;

    // (e) tilde de la de ISIS: sin empresa, como siempre
    const btn2 = document.createElement("button");
    btn2.dataset.args = JSON.stringify({ np: "98574", tanda: "C03B", m3: 0.5, rs: "Osa", cod: "2533", feRaw: "2026-09-11" });
    await window.facTickNP(btn2);
    const drenIsis = stockRows.filter(x => x.ref === "C03B|98574");
    out.drenIsisN         = drenIsis.length;
    out.drenIsisSinEmpresa = drenIsis.length ? !("empresa" in drenIsis[0]) : null;

    // (f) las dos funciones auxiliares
    out.loekeWeb  = pkNpEsLoeke("LK 1344");
    out.loekeChW  = pkNpEsLoeke("CH 0007");
    out.loekeIsis = pkNpEsLoeke("98574") && !pkNpEsLoeke("44603");
    out.xlsWebCh  = _facXlsEmpresa("CH 0007");
    out.xlsWebLk  = _facXlsEmpresa("LK 1344");
    out.xlsIsis   = _facXlsEmpresa("44603") + "/" + _facXlsEmpresa("98574");
    return out;
  });

  const checks = [
    ["facEstaArmada acepta la NP web con TAP",                 r.armadaWeb === true],
    ["y la de ISIS sigue igual",                                r.armadaIsis === true],
    ["un texto de tanda suelto se sigue descartando",           r.basuraFuera === true],
    ["la fila de la NP web se dibuja en Facturación",           r.filaWeb === true],
    ["al lado de la de ISIS",                                   r.filaIsis === true],
    ["las dos tandas quedan como FC",                           r.tandasFC === "C03B,GV-02A"],
    ["la fila web NO tiene tilde",                              r.webSinTilde === true],
    ["y SÍ tiene la casilla del Excel",                         r.webConCasilla === true],
    ["la fila de ISIS SÍ tiene tilde",                          r.isisConTilde === true],
    ["y NO tiene casilla del Excel",                            r.isisSinCasilla === true],
    ["tildar una NP web no escribe nada",                       r.tildeWebNoEscribe === true],
    ["al bajar el Excel, la de ISIS marcada se cae sola",       r.isisSacadaDelExcel === true],
    ["bajar el Excel escribe la etiqueta, no un número",        r.postNp === "LK 1344"],
    ["con su tanda",                                            r.postTanda === "GV-02A"],
    ["y una sola NP (la de ISIS no)",                           r.postsN === 1],
    ["el drenaje de la NP web genera movimiento",               r.drenWebN === 1],
    ["y manda empresa = LK explícita",                          r.drenWebEmpresa === "LK"],
    ["por la cantidad armada (1 caja)",                         r.drenWebDelta === -1],
    ["el drenaje de la NP de ISIS genera movimiento",           r.drenIsisN === 1],
    ["y NO manda empresa (no cambia lo de siempre)",            r.drenIsisSinEmpresa === true],
    ["pkNpEsLoeke: LK web → Loeke",                             r.loekeWeb === true],
    ["pkNpEsLoeke: CH web → no Loeke",                          r.loekeChW === false],
    ["pkNpEsLoeke: ISIS igual que siempre",                     r.loekeIsis === true],
    ["_facXlsEmpresa: CH web → chef (tope 15)",                 r.xlsWebCh === "chef"],
    ["_facXlsEmpresa: LK web → lk (tope 18)",                   r.xlsWebLk === "lk"],
    ["_facXlsEmpresa: ISIS igual que siempre",                  r.xlsIsis === "chef/lk"],
    ["sin errores de página",                                   errs.length === 0]
  ];

  let bad = 0;
  for (const [name, ok] of checks) { console.log((ok ? "  ok   " : "  FALLA") + " · " + name); if (!ok) bad++; }
  if (bad) console.log("  detalle:", JSON.stringify(r));
  if (errs.length) console.log("  pageerror: " + errs.join(" | "));
  console.log(bad ? "pweb-facturacion: " + bad + " FALLA(S)" : "pweb-facturacion: OK (" + checks.length + " chequeos)");
  await b.close();
  process.exit(bad ? 1 : 0);
})();
