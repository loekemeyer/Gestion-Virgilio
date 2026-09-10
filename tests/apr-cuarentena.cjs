/* v14.81 — SUBMÓDULO CUARENTENA (idea usuario 8877). El sector aparece SIEMPRE en A Programar
   (paso 1). Un pedido marcado (deuda / suspendido / supera crédito) sale de "Pedidos a
   programar", cae en Cuarentena con badge y NO se puede tildar. Estado inyectado. */
const path = require("path");
const { chromium } = require("/opt/node22/lib/node_modules/playwright");
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 800 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    _apr.listo = true; _apr.tandas = []; _apr.items = {}; _apr.salida = {};
    _apr.cal = [{ dia: "2026-09-14", habil: true, m3: 1, tandas: 1, np: 2, cupo: 6, resta: 5, pasado: false }];
    const mk = (o) => Object.assign({ order_id: 100, empresa: "lk", cod: "1000", razon_social: "Cliente Normal", zona: "Zona 1 - CABA Sur", fecha_recep: "2026-09-04", localidad: "Barracas", direccion: "Montes de Oca 1", m3: 0.4, m3_parcial: false, lineas: 5, cajas: 6, np_total: 1, bloques: [] }, o);
    _pppTab = "prog";
    document.getElementById("pppOverlay").classList.add("show");

    // (1) sin pedidos en cuarentena: el sector existe igual, vacío
    _apr.cuarResumen = [];  // evita el fetch de resumen; muestra "sin cargar"
    _apr.pedidos = [mk({ order_id: 100 }), mk({ order_id: 101, razon_social: "Cliente Dos" })];
    aprRender(); await new Promise((res) => setTimeout(res, 200));
    let html = document.getElementById("pppPreview").innerHTML;
    out.sectorSiempre = /apr-col-cuar/.test(html) && /🚧 Cuarentena/.test(html);
    out.vacioCuenta = /🚧 Cuarentena <b>\(0\)<\/b>/.test(html);
    out.listaNormal2 = /📋 Pedidos a programar <b>\(2\)<\/b>/.test(html);
    out.textoVacio = /Sin pedidos retenidos/.test(html);
    // los 4 botones de importación, con las etiquetas pedidas
    out.btnBusqLk = /Importar Búsqueda CL LK/.test(html);
    out.btnBusqCh = /Importar Búsqueda CL CH/.test(html);
    out.btnDeudaLk = /Importar Deuda LK/.test(html);
    out.btnDeudaCh = /Importar Deuda CH/.test(html);
    out.cuatroBotones = (html.match(/cuar-btn/g) || []).length === 4;
    out.statSinCargar = (html.match(/sin cargar/g) || []).length === 4;

    // resumen cargado → stat con conteos
    _apr.cuarResumen = [{ empresa: "lk", tipo: "busqueda", filas: 764, con_cuit: 700, suspendidos: 12, con_deuda: 0, con_limite: 700, lote: "L1", cargado_por: "sup@x", cargado_at: "2026-09-10T12:00:00" }];
    aprRender(); await new Promise((res) => setTimeout(res, 50));
    html = document.getElementById("pppPreview").innerHTML;
    out.statConteo = /764 cli · 700 c\/límite · 12 susp/.test(html);

    // parser: auto-map contra los encabezados REALES del reporte Búsqueda CL + números AR + estado
    out.pMap = cuarAutoMap(["Código", "Razón Social de Búsqueda", "Razón Social", "Estado", "CUIT", "Límite de Crédito"], "busqueda");
    out.pMapDeuda = cuarAutoMap(["Cod", "Cuit", "Nombre", "Saldo"], "deuda");
    out.pNum1 = cuarParseNum("1.234.567,89");
    out.pNum2 = cuarParseNum("$ 50000");
    out.pNum3 = cuarParseNum("");
    out.pEstSusp = cuarEstadoSuspende("Suspendido");
    out.pEstSinCta = cuarEstadoSuspende("Sin Cta.Cte.");
    out.pEstActivo = cuarEstadoSuspende("Activo");
    out.pEstVacio = cuarEstadoSuspende("");

    // (2) un pedido marcado por deuda + supera crédito: sale de la lista y cae en cuarentena
    _apr.pedidos = [
      mk({ order_id: 100, razon_social: "Cliente Deudor", cuarentena_motivos: ["deuda", "limite_credito"] }),
      mk({ order_id: 101, razon_social: "Cliente Dos" })
    ];
    aprRender(); await new Promise((res) => setTimeout(res, 200));
    html = document.getElementById("pppPreview").innerHTML;
    out.cuentaCuar1 = /🚧 Cuarentena <b>\(1\)<\/b>/.test(html);
    out.listaNormal1 = /📋 Pedidos a programar <b>\(1\)<\/b>/.test(html);
    out.badge = /apr-chip-cuar/.test(html) && /Deuda · Excede crédito/.test(html);
    out.motivo = /El cliente tiene deuda\. El pedido supera el límite de crédito del cliente\./.test(html);
    // el deudor no aparece como tarjeta tildable (sin checkbox de selección en su tarjeta)
    out.deudorCliente = /Cliente Deudor/.test(html);
    const chks = [...document.querySelectorAll(".apr-sel-chk")].length;
    out.soloUnCheckbox = chks === 1;  // solo el pedido normal es tildable

    out.errs = null;
    return out;
  });

  const fallos = [];
  const chk = (cond, msg) => { console.log((cond ? "ok   " : "MAL  ") + msg); if (!cond) fallos.push(msg); };

  chk(r.sectorSiempre, "el sector 🚧 Cuarentena aparece siempre");
  chk(r.vacioCuenta, "sin retenidos: contador (0)");
  chk(r.textoVacio, "sin retenidos: explica deuda/suspendido/crédito");
  chk(r.listaNormal2, "sin retenidos: los 2 pedidos van a la lista normal");
  chk(r.cuentaCuar1, "con 1 retenido: Cuarentena (1)");
  chk(r.listaNormal1, "el retenido sale de la lista normal (queda 1)");
  chk(r.badge, "el retenido lleva badge con la etiqueta del motivo");
  chk(r.motivo, "el retenido muestra el texto del motivo");
  chk(r.deudorCliente, "el cliente deudor se ve en el sector");
  chk(r.soloUnCheckbox, "el retenido NO es tildable (solo el normal tiene checkbox)");
  // botones de importación
  chk(r.btnBusqLk && r.btnBusqCh && r.btnDeudaLk && r.btnDeudaCh, "los 4 botones con sus etiquetas exactas");
  chk(r.cuatroBotones, "exactamente 4 botones cuar-btn");
  chk(r.statSinCargar, "cada botón dice 'sin cargar' cuando no hay resumen");
  chk(r.statConteo, "con resumen: '764 cli · 700 c/límite · 12 susp'");
  // parser
  chk(r.pMap.cod === 0 && r.pMap.cuit === 4 && r.pMap.razon_social === 2 && r.pMap.estado === 3 && r.pMap.limite_credito === 5, "auto-map búsqueda contra encabezados reales (Código/CUIT/Razón Social/Estado/Límite de Crédito)");
  chk(r.pMapDeuda.cod === 0 && r.pMapDeuda.cuit === 1 && r.pMapDeuda.deuda === 3, "auto-map deuda (cod/cuit/saldo)");
  chk(r.pNum1 === 1234567.89, "número AR 1.234.567,89 → 1234567.89 (dio " + r.pNum1 + ")");
  chk(r.pNum2 === 50000, "número '$ 50000' → 50000");
  chk(r.pNum3 === null, "vacío → null");
  chk(r.pEstSusp === true, "Estado 'Suspendido' → cuarentena (true)");
  chk(r.pEstSinCta === true, "Estado 'Sin Cta.Cte.' → cuarentena (true)");
  chk(r.pEstActivo === false, "Estado 'Activo' → false");
  chk(r.pEstVacio === null, "Estado vacío → null");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? " (" + errs.join(" | ") + ")" : ""));

  await b.close();
  if (fallos.length) { console.log("\nFALLARON " + fallos.length + ":\n· " + fallos.join("\n· ")); process.exit(1); }
  console.log("\napr-cuarentena OK");
})();
