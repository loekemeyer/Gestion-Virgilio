/* v14.81 — SUBMÓDULO CUARENTENA (idea usuario 8877). El sector aparece SIEMPRE en A Programar
   (paso 1). Un pedido marcado (deuda / suspendido / supera crédito) sale de "Pedidos a
   programar", cae en Cuarentena con badge y NO se puede tildar. Estado inyectado. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  // v15.40: sin este fallback el test muere en CI (el runner instala playwright con npm,
  // no tiene /opt/node22) y, como run.sh corta en el primero que falla, todo lo que venía
  // después NUNCA se corrió en GitHub. Mismo patrón que ya tenían los demás tests.
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
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
    // v17.11 (Luis): el número de cliente tiene que verse en la ficha (LK 1000 / CH 2533)
    out.codChip = /cuar-card-cod[^>]*>LK 1000</.test(html);

    // (3) v17.11 — CLIENTE NUEVO: badge propio y el número de cliente de Chef con prefijo CH
    _apr.pedidos = [
      mk({ order_id: 200, empresa: "chef", cod: "2533", razon_social: "Cliente Nuevo SA",
           cuarentena_motivos: ["cliente_nuevo"], cuarentena_detalle: { nuevo_pedidos: 1 } }),
      mk({ order_id: 201, razon_social: "Cliente Dos" })
    ];
    aprRender(); await new Promise((res) => setTimeout(res, 200));
    html = document.getElementById("pppPreview").innerHTML;
    out.nuevoBadge = /cuar-badge b-nuevo[^>]*>🆕 Cliente nuevo</.test(html);
    out.nuevoCuenta = /🚧 Cuarentena <b>\(1\)<\/b>/.test(html);
    out.nuevoCodChip = /cuar-card-cod[^>]*>CH 2533</.test(html);
    out.nuevoMotivo = /Cliente nuevo \(1 pedido facturado en toda su historia\)\./.test(html);
    out.nuevoEtq = aprCuarentenaEtiqueta({ cuarentena_motivos: ["cliente_nuevo"] });

    // (4) v17.13 — "Ya programados" es una TABLA, con aprobación y librito de comentarios
    _apr.cuarYaProg = [
      { origen: "isis", empresa: "lk", np: "97889", order_id: null, clave: "97889", tanda: "D71A",
        fecha_entrega: "2026-09-16", cod: "4263", razon_social: "Matiz SA",
        motivos: ["deuda", "cliente_nuevo"], deuda: 12039500, estado: null, picking_empezado: false,
        nuevo_pedidos: 1, aprobado_at: null, aprobado_por: null, comentarios: 0 },
      { origen: "web", empresa: "chef", np: "CH 0003", order_id: 55, clave: "55", tanda: "D69E",
        fecha_entrega: "2026-09-16", cod: "2715", razon_social: "Gifel S.R.L.",
        motivos: ["deuda"], deuda: 1955318, estado: null, picking_empezado: true,
        nuevo_pedidos: null, aprobado_at: "2026-09-14T10:35:00-03:00", aprobado_por: "vivi@loekemeyer.com",
        comentarios: 2 }
    ];
    _apr.pedidos = [mk({ order_id: 101, razon_social: "Cliente Dos" })];
    aprRender(); await new Promise((res) => setTimeout(res, 200));
    html = document.getElementById("pppPreview").innerHTML;
    out.ypTabla = /cuar-yaprog-tbl/.test(html) && /<th>NP<\/th>/.test(html) && /<th>Aprobación<\/th>/.test(html);
    out.ypCuenta = /Ya programados y el cliente está en cuarentena <b>\(2\)<\/b>/.test(html);
    out.ypCod = /cuar-yaprog-cod[^>]*>LK 4263</.test(html) && /cuar-yaprog-cod[^>]*>CH 2715</.test(html);
    out.ypBadges = /cuar-badge b-deuda/.test(html) && /cuar-badge b-nuevo/.test(html);
    out.ypAprob = /✅ 14\/09 10:35/.test(html) && /vivi@loekemeyer\.com/.test(html) && /cuar-yp-ok/.test(html);
    out.ypSinAprob = /sin aprobar/.test(html);
    out.ypLibrito = /cuarComAbrirIdx\(0\)/.test(html) && /cuarComAbrirIdx\(1\)/.test(html) && /📖<b>2<\/b>/.test(html);
    out.ypAprobN = /1 aprobado</.test(html);

    // el librito abre el modal con el log (RPC stubeada)
    const llamadas = [];
    window.aprRpc = async function (fn, args) {
      llamadas.push({ fn: fn, args: args });
      if (fn === "gv_cuarentena_comentarios")
        return [{ id: 1, creado_at: "2026-09-14T09:00:00-03:00", por: "luis@loekemeyer.com", texto: "Habló Vivi, lo autoriza" }];
      return null;
    };
    cuarComAbrirIdx(1); await new Promise((res) => setTimeout(res, 120));
    const mh = (document.getElementById("cuarComModal") || {}).innerHTML || "";
    out.comModal = /📖 Comentarios/.test(mh) && /Habló Vivi, lo autoriza/.test(mh) && /14\/09 09:00/.test(mh);
    out.comPideTexto = /id="cuarComTexto"/.test(mh) && /Agregar comentario/.test(mh);
    out.comRpc = llamadas.length === 1 && llamadas[0].fn === "gv_cuarentena_comentarios" &&
                 llamadas[0].args.p_empresa === "chef" && llamadas[0].args.p_order_id === "55";
    cuarComCerrar();
    out.comCerrado = !!(document.getElementById("cuarComModal") || {}).hidden;

    // (5) aprobar NO dispara la RPC de una: primero pide el comentario
    llamadas.length = 0;
    _apr.pedidosTodos = [mk({ order_id: 900, empresa: "lk", cod: "4275", razon_social: "Zhang Qikuan",
                              cuarentena_motivos: ["deuda"], cuarentena_detalle: { deuda: 2734562 } })];
    await cuarLiberar("lk", 900); await new Promise((res) => setTimeout(res, 120));
    const ah = (document.getElementById("cuarComModal") || {}).innerHTML || "";
    out.aprModal = /Enviar a Pedidos a programar/.test(ah) && /Zhang Qikuan/.test(ah) && /Aprobar y enviar/.test(ah);
    out.aprSinLiberar = !llamadas.some(function (c) { return c.fn === "gv_cuarentena_liberar"; });
    // y al confirmar sí libera, con el comentario adentro
    document.getElementById("cuarComTexto").value = "Lo autorizó cobranzas";
    await cuarLiberarConfirmar(); await new Promise((res) => setTimeout(res, 120));
    const lib = llamadas.find(function (c) { return c.fn === "gv_cuarentena_liberar"; });
    out.aprLibera = !!lib && lib.args.p_order_id === "900" && lib.args.p_comentario === "Lo autorizó cobranzas";

    // (6) v17.16 — columna "Marcar": aprobar / volver a cuarentena
    // (el bloque anterior dejó la lista recargada contra la RPC stubeada: se repone)
    _apr.cuarCom = null;
    llamadas.length = 0;
    _apr.cuarYaProg = [
      { empresa: "lk", np: "97889", order_id: null, clave: "97889", tanda: "D71A",
        fecha_entrega: "2026-09-16", cod: "4263", razon_social: "Matiz SA", motivos: ["deuda"],
        deuda: 12039500, picking_empezado: false, aprobado_at: null, comentarios: 0 },
      { empresa: "chef", np: "CH 0003", order_id: 55, clave: "55", tanda: "D69E",
        fecha_entrega: "2026-09-16", cod: "2715", razon_social: "Gifel S.R.L.", motivos: ["deuda"],
        deuda: 1955318, picking_empezado: false, aprobado_at: "2026-09-14T10:35:00-03:00",
        aprobado_por: "vivi@loekemeyer.com", comentarios: 1 }
    ];
    aprRender(); await new Promise((res) => setTimeout(res, 150));
    html = document.getElementById("pppPreview").innerHTML;
    out.marcarCol = /<th>Marcar<\/th>/.test(html);
    const filas = html.split("<tr").filter(function (t) { return /cuarYpCuarentena/.test(t); });
    out.marcarSinAprobar = /cuarYpAprobar\(0\)/.test(html) && /cuarYpCuarentena\(0\)/.test(html);
    out.marcarAprobada = !/cuarYpAprobar\(1\)/.test(html) && /cuarYpCuarentena\(1\)/.test(html);
    out.marcarFilas = filas.length === 2;   // las dos filas ofrecen volver a cuarentena

    cuarYpCuarentena(0); await new Promise((res) => setTimeout(res, 120));
    const dh = (document.getElementById("cuarComModal") || {}).innerHTML || "";
    out.devModal = /Volver a Cuarentena/.test(dh) && /saca de la programación/.test(dh) && /D71A/.test(dh);
    document.getElementById("cuarComTexto").value = "No lo autorizó cobranzas";
    await cuarDevolverConfirmar(); await new Promise((res) => setTimeout(res, 120));
    const dev = llamadas.find(function (c) { return c.fn === "gv_cuarentena_devolver"; });
    out.devRpc = !!dev && dev.args.p_np === "97889" && dev.args.p_clave === "97889" &&
                 dev.args.p_empresa === "lk" && dev.args.p_comentario === "No lo autorizó cobranzas";

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
  chk(r.codChip, "la ficha muestra el número de cliente (LK 1000)");
  chk(r.nuevoBadge, "cliente nuevo: badge '🆕 Cliente nuevo'");
  chk(r.nuevoCuenta, "cliente nuevo: el pedido cae en Cuarentena (1)");
  chk(r.nuevoCodChip, "cliente nuevo de Chef: el chip dice CH 2533");
  chk(r.nuevoMotivo, "cliente nuevo: el motivo dice cuántos pedidos facturó");
  chk(r.nuevoEtq === "Cliente nuevo", "etiqueta de cliente_nuevo = 'Cliente nuevo'");
  chk(r.ypTabla, "ya programados: es una tabla con columnas NP / … / Aprobación");
  chk(r.ypCuenta, "ya programados: el contador cuenta las 2 filas");
  chk(r.ypCod, "ya programados: el número de cliente por empresa (LK 4263 / CH 2715)");
  chk(r.ypBadges, "ya programados: los motivos salen como badges");
  chk(r.ypAprob, "ya programados: la fila aprobada muestra fecha y quién, y queda en verde");
  chk(r.ypSinAprob, "ya programados: la fila sin aprobar dice 'sin aprobar'");
  chk(r.ypLibrito, "ya programados: el librito 📖 con la cantidad de comentarios");
  chk(r.ypAprobN, "ya programados: el título dice cuántos están aprobados");
  chk(r.comModal, "el librito abre el log con fecha, hora y autor");
  chk(r.comPideTexto, "el log deja agregar un comentario nuevo");
  chk(r.comRpc, "el log pide los comentarios de ESE pedido (empresa + clave)");
  chk(r.comCerrado, "el modal se cierra");
  chk(r.aprModal, "aprobar abre el cuadro de comentario (no libera de una)");
  chk(r.aprSinLiberar, "aprobar NO llamó a gv_cuarentena_liberar antes de confirmar");
  chk(r.aprLibera, "al confirmar libera y manda el comentario");
  chk(r.marcarCol, "la tabla tiene la columna 'Marcar'");
  chk(r.marcarSinAprobar, "sin aprobar: ofrece Aprobar y Cuarentena");
  chk(r.marcarAprobada, "ya aprobada: ofrece SOLO Cuarentena");
  chk(r.marcarFilas, "las dos filas ofrecen volver a cuarentena");
  chk(r.devModal, "volver a cuarentena avisa que lo saca de la programación y de qué tanda");
  chk(r.devRpc, "al confirmar llama gv_cuarentena_devolver con NP, clave y comentario");
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
