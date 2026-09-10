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
    // v14.88: los 4 botones de importación se movieron a la pestaña "Config. Cuarentena";
    // el sector Cuarentena ya NO los muestra (sólo el botón "Ver ejemplo").
    out.sectorSinBotones = (html.match(/cuar-btn/g) || []).length === 0;

    // v14.88: la pestaña Config. Cuarentena tiene los 4 botones + el timer de última carga
    _pppTab = "cuarcfg"; pppRenderProg(); await new Promise((res) => setTimeout(res, 50));
    let cfg = document.getElementById("pppPreview").innerHTML;
    out.cfgTab = /Config\. Cuarentena/.test(cfg);
    out.btnBusqLk = /Importar Búsqueda CL LK/.test(cfg);
    out.btnBusqCh = /Importar Búsqueda CL CH/.test(cfg);
    out.btnDeudaLk = /Importar Deuda LK/.test(cfg);
    out.btnDeudaCh = /Importar Deuda CH/.test(cfg);
    out.cuatroBotones = (cfg.match(/cuar-btn/g) || []).length === 4;
    out.statSinCargar = (cfg.match(/sin cargar/g) || []).length === 4;

    // resumen cargado → stat con conteos (en el title) y "última vez cargada"
    _apr.cuarResumen = [{ empresa: "lk", tipo: "busqueda", filas: 764, con_cuit: 700, suspendidos: 12, con_deuda: 0, con_limite: 700, lote: "L1", cargado_por: "sup@x", cargado_at: "2026-09-10T12:00:00" }];
    pppRenderProg(); await new Promise((res) => setTimeout(res, 50));
    cfg = document.getElementById("pppPreview").innerHTML;
    out.statConteo = /764 cli · 700 c\/límite · 12 susp/.test(cfg);
    out.statTimer = /última vez cargada/.test(cfg);
    _pppTab = "prog"; aprRender(); await new Promise((res) => setTimeout(res, 50));

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

    // parser Deuda (Crystal agrupado): cabecera(A=cod texto,B=razón) + detalle(E=FCA,L=idx11) + subtotal(sólo L)
    const daoa = [
      ["Vto.","Emisión","Días","Div.","Comprobante","","","","","","","Pendiente","Acumulado"],
      ["","","","","","Division Unica"],
      ["1104","Ramirez Miguel","","","","","dir","tel"],
      [46231,46231,44,"Div","FCA",400,"x","Admin",1,"$",0,516747.92,516747.92],
      ["","","","","","","","","","","",516747.92],
      ["1361","Santone","","","",""],
      [46230,46230,45,"Div","FCA",401,"y","Admin",1,"$",0,1000,1000],
      [46231,46231,44,"Div","FCA",402,"y","Admin",1,"$",0,725822.09,726822.09],
      ["","","","","","","","","","","",726822.09],
      ["1274","Credito SA","","","",""],
      [46000,46000,10,"Div","FCA",403,"z","Admin",1,"$",0,-16023,-16023]
    ];
    out.deuda = cuarParseDeudaCrystal(daoa);
    // flatten de items para el límite (todos los bloques del pedido juntos)
    out.itemsFlat = cuarItemsDe({ bloques: [{ items: [{ art: "027", cajas: 2 }] }, { items: [{ art: "505", cajas: 3 }] }] });

    // etiqueta del motivo sin_cta_cte
    out.etqSinCta = aprCuarentenaEtiqueta({ cuarentena_motivos: ["sin_cta_cte"] });
    out.etqCombo = aprCuarentenaEtiqueta({ cuarentena_motivos: ["deuda", "limite_credito"] });
    // pedido de EJEMPLO (demo)
    _apr.cuarDemo = true; _apr.pedidos = [mk({ order_id: 100 })];
    aprRender(); await new Promise((res) => setTimeout(res, 80));
    html = document.getElementById("pppPreview").innerHTML;
    out.demoTag = /EJEMPLO/.test(html);
    out.demoCli = /CLIENTE DE EJEMPLO S\.A\./.test(html);
    // v14.88: la ficha muestra 3 badges separados, no el texto unido
    out.demoMotivo = /cuar-badge b-deuda/.test(html) && /cuar-badge b-limite/.test(html);
    out.demoCuenta = /🚧 Cuarentena <b>\(1\)<\/b>/.test(html);
    out.demoBtnQuitar = /Quitar ejemplo/.test(html);
    _apr.cuarDemo = false;
    aprRender(); await new Promise((res) => setTimeout(res, 40));
    html = document.getElementById("pppPreview").innerHTML;
    out.demoOff = !/EJEMPLO/.test(html) && /👁 Ver ejemplo/.test(html);

    // (2) un pedido marcado por deuda + supera crédito: sale de la lista y cae en cuarentena
    _apr.pedidos = [
      mk({ order_id: 100, razon_social: "Cliente Deudor", cuarentena_motivos: ["deuda", "limite_credito"] }),
      mk({ order_id: 101, razon_social: "Cliente Dos" })
    ];
    aprRender(); await new Promise((res) => setTimeout(res, 200));
    html = document.getElementById("pppPreview").innerHTML;
    out.cuentaCuar1 = /🚧 Cuarentena <b>\(1\)<\/b>/.test(html);
    out.listaNormal1 = /📋 Pedidos a programar <b>\(1\)<\/b>/.test(html);
    // v14.88: badges separados (b-deuda + b-limite) + botón "Enviar a Pedidos a programar"
    out.badge = /cuar-badge b-deuda/.test(html) && /cuar-badge b-limite/.test(html);
    out.enviarBtn = /cuar-enviar/.test(html) && /Enviar a Pedidos a programar/.test(html);
    out.cobranzasBtn = /cuar-wpp-cob/.test(html) && /A cobranzas/.test(html);  // v14.89
    out.contactoBtn = /cuar-wpp-(cli|off)/.test(html);  // v14.90: botón WhatsApp vendedor/cliente
    out.motivo = /El cliente tiene deuda mayor a \$1\.000\. El pedido supera el límite de crédito del cliente\./.test(html);
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
  chk(r.badge, "el retenido lleva 3 badges separados (deuda + límite)");
  chk(r.enviarBtn, "la ficha tiene el botón 'Enviar a Pedidos a programar'");
  chk(r.cobranzasBtn, "la ficha tiene el botón '💬 A cobranzas' (WhatsApp fijo)");
  chk(r.contactoBtn, "la ficha tiene el botón WhatsApp al vendedor/cliente");
  chk(r.motivo, "el retenido muestra el texto del motivo");
  chk(r.deudorCliente, "el cliente deudor se ve en el sector");
  chk(r.soloUnCheckbox, "el retenido NO es tildable (solo el normal tiene checkbox)");
  // v14.88: los botones se movieron a la pestaña Config. Cuarentena
  chk(r.sectorSinBotones, "el sector Cuarentena ya NO muestra los 4 botones");
  chk(r.cfgTab, "existe la pestaña 'Config. Cuarentena'");
  chk(r.btnBusqLk && r.btnBusqCh && r.btnDeudaLk && r.btnDeudaCh, "Config: los 4 botones con sus etiquetas exactas");
  chk(r.cuatroBotones, "Config: exactamente 4 botones cuar-btn");
  chk(r.statSinCargar, "Config: cada botón dice 'sin cargar' cuando no hay resumen");
  chk(r.statConteo, "Config: con resumen, el title trae '764 cli · 700 c/límite · 12 susp'");
  chk(r.statTimer, "Config: muestra 'última vez cargada …'");
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
  // parser Deuda
  chk(r.deuda.length === 3, "Deuda: 3 clientes (la fila 'Vto.' NO cuenta) — dio " + r.deuda.length);
  const d1104 = r.deuda.find(function (c) { return c.cod === "1104"; });
  const d1361 = r.deuda.find(function (c) { return c.cod === "1361"; });
  const d1274 = r.deuda.find(function (c) { return c.cod === "1274"; });
  chk(d1104 && Math.abs(d1104.deuda - 516747.92) < 0.01 && d1104.docs === 1, "Deuda 1104 Ramirez = 516747.92 (1 doc)");
  chk(d1361 && Math.abs(d1361.deuda - 726822.09) < 0.01 && d1361.docs === 2, "Deuda 1361 multi-doc suma = 726822.09 (2 docs)");
  chk(d1274 && Math.abs(d1274.deuda - (-16023)) < 0.01, "Deuda 1274 negativa = -16023 (no cae en cuarentena)");
  chk(!r.deuda.some(function (c) { return c.cod === "Vto."; }), "la fila de encabezado 'Vto.' no se toma como cliente");
  // etiquetas de motivo
  chk(r.etqSinCta === "Sin Cta.Cte.", "motivo sin_cta_cte → 'Sin Cta.Cte.'");
  chk(r.etqCombo === "Deuda · Excede crédito", "combo deuda+límite → 'Deuda · Excede crédito'");
  // pedido de ejemplo
  chk(r.demoTag && r.demoCli && r.demoMotivo, "el ejemplo muestra tag EJEMPLO + cliente + motivo");
  chk(r.demoCuenta, "el ejemplo cuenta en Cuarentena (1)");
  chk(r.demoBtnQuitar, "con ejemplo activo el botón dice 'Quitar ejemplo'");
  chk(r.demoOff, "al quitar el ejemplo desaparece y el botón vuelve a 'Ver ejemplo'");
  chk(r.itemsFlat.length === 2 && r.itemsFlat[0].art === "027" && r.itemsFlat[1].art === "505", "cuarItemsDe aplana los items de todos los bloques del pedido");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? " (" + errs.join(" | ") + ")" : ""));

  await b.close();
  if (fallos.length) { console.log("\nFALLARON " + fallos.length + ":\n· " + fallos.join("\n· ")); process.exit(1); }
  console.log("\napr-cuarentena OK");
})();
