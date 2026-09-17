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

    // (3) v18.100 — CLIENTE NUEVO: submódulo DENTRO de "A Programar" (no una pestaña), debajo de
    // Cuarentena, y las dos colapsables. Un pedido cuyo ÚNICO motivo es cliente_nuevo va al
    // submódulo "Clientes nuevos"; uno que además tiene deuda (u otro motivo) sigue en Cuarentena.
    try { localStorage.removeItem("vir_cuar_colapsado"); localStorage.removeItem("vir_cli_colapsado"); } catch (_e) {}
    _apr.cuarContacto = {}; _apr.cliValor = {}; _apr.cliDemo = false;   // evitan los fetch (ruta REST abortada)
    _apr.pedidos = [
      mk({ order_id: 200, empresa: "chef", cod: "2533", razon_social: "Cliente Nuevo SA",
           cuarentena_motivos: ["cliente_nuevo"], cuarentena_detalle: { nuevo_pedidos: 1 } }),
      mk({ order_id: 202, cod: "4263", razon_social: "Cliente Nuevo Deudor",
           cuarentena_motivos: ["deuda", "cliente_nuevo"], cuarentena_detalle: { deuda: 50000, nuevo_pedidos: 1 } }),
      mk({ order_id: 201, razon_social: "Cliente Dos" })
    ];
    _pppTab = "prog"; aprRender(); await new Promise((res) => setTimeout(res, 50));
    html = document.getElementById("pppPreview").innerHTML;
    // Los dos submódulos conviven en el mismo render; se parte el HTML por sus títulos.
    const iCuar = html.indexOf("🚧 Cuarentena"), iCli = html.indexOf("🆕 Clientes nuevos");
    const cuarSec = html.slice(iCuar, iCli), cliSec = html.slice(iCli);
    // (3a) Cuarentena: sólo el mixto (deuda+nuevo), con badge; el puro NO.
    out.nuevoFueraDeCuar = /🚧 Cuarentena <b>\(1\)<\/b>/.test(cuarSec);
    out.nuevoBadge = /cuar-badge b-nuevo[^>]*>🆕 Cliente nuevo</.test(cuarSec);
    out.nuevoMotivo = /Cliente nuevo \(1 pedido facturado en toda su historia\)\./.test(cuarSec);
    // (3b) Clientes nuevos: el puro está (chip CH 2533); el mixto NO.
    out.cliNuevosCuenta = /🆕 Clientes nuevos <b>\(1\)<\/b>/.test(cliSec);
    out.nuevoCodChip = /cuar-card-cod[^>]*>CH 2533</.test(cliSec);
    out.cliNuevosSinMixto = !/Cliente Nuevo Deudor/.test(cliSec);
    // (3b-2) v19.05 — columnas nuevas: 1er contacto, Speech 1/2, Acción (Aprobar / Eliminar).
    out.cliCols = /1er contacto/.test(cliSec) && /Acci[oó]n/.test(cliSec);
    out.cliSpeech = /Speech 1/.test(cliSec) && /Speech 2/.test(cliSec);
    out.cliAccion = /Aprobar pedido/.test(cliSec) && /Eliminar pedido/.test(cliSec);
    // (3b-3) v19.36 (Luis) — NO hay seña del 30%: el Speech 1 pide el TOTAL con IVA, por
    // adelantado, y la columna Monto muestra ese mismo número debajo del neto.
    _apr.cliValor = { "chef:200": { valor: 100000, valorIva: 121000 } };
    aprRender(); await new Promise((res) => setTimeout(res, 50));
    const cliSecIva = document.getElementById("pppPreview").innerHTML.slice(
      document.getElementById("pppPreview").innerHTML.indexOf("🆕 Clientes nuevos"));
    out.cliMontoIva = /clin-iva[^>]*>c\/IVA \$121\.000/.test(cliSecIva);
    const msg1 = clinSpeechMsg1({ order_id: 200, empresa: "chef", np: null });
    out.cliMsgTotal = /\$121\.000/.test(msg1) && /IVA incluido/.test(msg1);
    out.cliMsgSinSena = !/30\s*%/.test(msg1) && !/se\u00f1a/i.test(msg1);
    out.cliMsgAdelantado = /por adelantado/.test(msg1) && /antes de armar y entregar/.test(msg1);
    _apr.cliValor = {}; aprRender(); await new Promise((res) => setTimeout(res, 50));
    html = document.getElementById("pppPreview").innerHTML;
    // (3c) el botón "👁 Ver ejemplo" agrega una fila EJEMPLO con su monto, sin sumar al badge.
    _apr.cliDemo = true; aprRender(); await new Promise((res) => setTimeout(res, 50));
    html = document.getElementById("pppPreview").innerHTML;
    const cliSec2 = html.slice(html.indexOf("🆕 Clientes nuevos"));
    out.cliDemoFila = /cuar-demo-tag">EJEMPLO</.test(cliSec2) && /\$120\.480/.test(cliSec2);
    out.cliDemoNoCuenta = /🆕 Clientes nuevos <b>\(1\)<\/b>/.test(cliSec2);
    _apr.cliDemo = false;
    // (3d) v18.100 — colapsar: el título queda, la tabla se esconde.
    try { localStorage.setItem("vir_cli_colapsado", "1"); } catch (_e) {}
    aprRender(); await new Promise((res) => setTimeout(res, 50));
    html = document.getElementById("pppPreview").innerHTML;
    const cliSec3 = html.slice(html.indexOf("🆕 Clientes nuevos"), html.indexOf("🆕 Clientes nuevos") + 400);
    out.cliColapsaTitulo = /🆕 Clientes nuevos <b>\(1\)<\/b>/.test(cliSec3);   // el título con contador sigue
    out.cliColapsaSinTabla = !/CH 2533/.test(html);   // la tabla (chip del cliente) desaparece
    try { localStorage.removeItem("vir_cli_colapsado"); } catch (_e) {}
    _pppTab = "prog";
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
    out.ypTabla = /cuar-yaprog-tbl/.test(html) && /<th>NP<\/th>/.test(html) && /<th>Enviar a<\/th>/.test(html);
    // v17.23: el aprobado sale de la lista (lo filtra el backend), así que la columna no va más
    out.ypSinColAprob = !/<th>Aprobación<\/th>/.test(html) && !/sin aprobar/.test(html);
    out.ypCuenta = /Ya programados y el cliente está en cuarentena <b>\(2\)<\/b>/.test(html);
    out.ypCod = /cuar-yaprog-cod[^>]*>LK 4263</.test(html) && /cuar-yaprog-cod[^>]*>CH 2715</.test(html);
    out.ypBadges = /cuar-badge b-deuda/.test(html) && /cuar-badge b-nuevo/.test(html);
    out.ypLibrito = /cuarComAbrirIdx\(0\)/.test(html) && /cuarComAbrirIdx\(1\)/.test(html) && /📖<b>2<\/b>/.test(html);

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
    // v17.38: un comentario sin identidad no se guarda
    out.comPideQuien = /¿Quién comenta\?/.test(mh);
    document.getElementById("cuarComTexto").value = "Probando";
    await cuarComAgregar(); await new Promise((res) => setTimeout(res, 100));
    out.comSinQuien = !llamadas.some(function (c) { return c.fn === "gv_cuarentena_comentar"; }) &&
                      /Decinos quién deja el comentario/.test((document.getElementById("cuarComModal") || {}).innerHTML || "");
    cuarQuienSet("Vivi");
    document.getElementById("cuarComTexto").value = "Probando";
    await cuarComAgregar(); await new Promise((res) => setTimeout(res, 100));
    const com = llamadas.find(function (c) { return c.fn === "gv_cuarentena_comentar"; });
    out.comConQuien = !!com && com.args.p_persona === "Vivi" && com.args.p_texto === "Probando";
    // la PRIMERA llamada es la del log (después vienen las de comentar, que agrega el bloque de arriba)
    out.comRpc = llamadas.length >= 1 && llamadas[0].fn === "gv_cuarentena_comentarios" &&
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
    // v17.23: el cuadro pide QUIÉN aprueba, y sin eso no libera
    out.aprPideQuien = /¿Quién aprueba\?/.test(ah) && /cuarQuienSet\('Vivi'\)/.test(ah) && /cuarQuienSet\('__otro'\)/.test(ah);
    document.getElementById("cuarComTexto").value = "Lo autorizó cobranzas";
    await cuarLiberarConfirmar(); await new Promise((res) => setTimeout(res, 120));
    out.aprSinQuien = !llamadas.some(function (c) { return c.fn === "gv_cuarentena_liberar"; }) &&
                      /Decinos quién aprueba/.test((document.getElementById("cuarComModal") || {}).innerHTML || "");
    // se elige la persona y ahí sí
    cuarQuienSet("Vivi");
    document.getElementById("cuarComTexto").value = "Lo autorizó cobranzas";
    await cuarLiberarConfirmar(); await new Promise((res) => setTimeout(res, 120));
    const lib = llamadas.find(function (c) { return c.fn === "gv_cuarentena_liberar"; });
    out.aprLibera = !!lib && lib.args.p_order_id === "900" && lib.args.p_comentario === "Lo autorizó cobranzas" &&
                    lib.args.p_persona === "Vivi";

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
    out.marcarCol = /<th>Enviar a<\/th>/.test(html);
    const filas = html.split("<tr").filter(function (t) { return /cuarYpCuarentena/.test(t); });
    out.marcarSinAprobar = /cuarYpAprobar\(0\)/.test(html) && /cuarYpCuarentena\(0\)/.test(html);
    out.marcarAprobada = /cuarYpAprobar\(1\)/.test(html) && /cuarYpCuarentena\(1\)/.test(html);
    out.marcarFilas = filas.length === 2;   // las dos filas ofrecen volver a cuarentena

    cuarYpCuarentena(0); await new Promise((res) => setTimeout(res, 120));
    const dh = (document.getElementById("cuarComModal") || {}).innerHTML || "";
    out.devModal = /Volver a Cuarentena/.test(dh) && /saca de la programación/.test(dh) && /D71A/.test(dh);
    out.devPideQuien = /¿Quién lo devuelve\?/.test(dh);
    document.getElementById("cuarComTexto").value = "No lo autorizó cobranzas";
    await cuarDevolverConfirmar(); await new Promise((res) => setTimeout(res, 120));
    out.devSinQuien = !llamadas.some(function (c) { return c.fn === "gv_cuarentena_devolver"; });
    cuarQuienSet("Marian");
    document.getElementById("cuarComTexto").value = "No lo autorizó cobranzas";
    await cuarDevolverConfirmar(); await new Promise((res) => setTimeout(res, 120));
    const dev = llamadas.find(function (c) { return c.fn === "gv_cuarentena_devolver"; });
    out.devRpc = !!dev && dev.args.p_np === "97889" && dev.args.p_clave === "97889" &&
                 dev.args.p_empresa === "lk" && dev.args.p_comentario === "No lo autorizó cobranzas" &&
                 dev.args.p_persona === "Marian";

    // (7) v17.23 — submódulo LOG en Config. Cuarentena (visual y campos de la v17.40)
    _apr.cuarLog = [
      { empresa: "lk", clave: "1368", np: "web LK 1368", cod: "4281", razon_social: "Biaggio Valentin",
        motivos: ["cliente_nuevo"], deuda: null, entro_at: "2026-09-14T09:10:00-03:00",
        estado: "aprobado", cerrado_at: "2026-09-14T11:05:00-03:00", persona: "Vivi",
        por: "thomasloke1@gmail.com", comentario: "Pagó la seña", com_persona: "Vivi",
        com_por: "thomasloke1@gmail.com", com_at: "2026-09-14T11:05:00-03:00",
        comentarios: 2, eventos: 3 },
      // v17.40: RETENIDO pero con un comentario suelto — el caso que antes no se veía
      { empresa: "chef", clave: "55", np: "CH 0003", cod: "2715", razon_social: "Gifel S.R.L.",
        motivos: ["deuda"], deuda: 1955318, entro_at: "2026-09-13T18:00:00-03:00",
        estado: "retenido", cerrado_at: null, persona: null, por: null,
        comentario: "Llamar a cobranzas antes de soltarlo", com_persona: "Marian",
        com_por: "marian@loekemeyer.com", com_at: "2026-09-14T12:40:00-03:00",
        comentarios: 1, eventos: 1 }
    ];
    _pppTab = "cuarcfg"; pppRenderProg(); await new Promise((res) => setTimeout(res, 150));
    const ch = document.getElementById("pppPreview").innerHTML;
    out.logTitulo = /📋 Log de Cuarentena/.test(ch) && /Todos <b>2<\/b>/.test(ch);
    out.logFilas = /web LK 1368/.test(ch) && /Gifel S\.R\.L\./.test(ch) && /LK 4281/.test(ch);
    out.logEstado = /e-aprobado">aprobado</.test(ch) && /e-retenido">retenido</.test(ch);
    // v17.46: quién cerró va en dos líneas (persona arriba, fecha abajo) para que un
    // "Otro: <nombre largo>" no parta la fecha al medio.
    out.logQuien = /cuar-log-quien">Vivi<\/div>/.test(ch) &&
                   /cuar-log-cuando">14\/09 11:05<\/div>/.test(ch) &&
                   /thomasloke1@gmail\.com/.test(ch);
    out.logEntro = /14\/09 09:10/.test(ch);
    out.logComent = /cuarLogComentarios\(0\)/.test(ch) && /📖<b>2<\/b>/.test(ch);
    // v17.40: el comentario de un pedido RETENIDO se ve en la fila, con quién lo dejó y cuándo
    out.logComRet = /Llamar a cobranzas antes de soltarlo/.test(ch) &&
                    /<b>Marian<\/b> · 14\/09 12:40/.test(ch);
    // los chips cuentan por estado y filtran
    out.logChips = /c-retenido[^>]*>🚧 Retenidos <b>1<\/b>/.test(ch) &&
                   /c-aprobado[^>]*>✅ Aprobados <b>1<\/b>/.test(ch);
    cuarLogFiltro("aprobado"); await new Promise((res) => setTimeout(res, 120));
    const chF = document.getElementById("pppPreview").innerHTML;
    out.logFiltra = /web LK 1368/.test(chF) && !/Gifel S\.R\.L\./.test(chF) &&
                    /cuarLogComentarios\(0\)/.test(chF);
    cuarLogFiltro("aprobado"); await new Promise((res) => setTimeout(res, 120));
    const chT = document.getElementById("pppPreview").innerHTML;
    out.logFiltraOff = /Gifel S\.R\.L\./.test(chT);
    _pppTab = "prog";

    // (8) v18.01 (Luis) — los retenidos se ven como LISTA/TABLA, con la fecha del pedido y el
    // 📖 de comentarios. Y "Ya pagó" tiene que hacer algo visible.
    _apr.cuarCom = null; _apr.cuarYaProg = [];
    llamadas.length = 0;
    const retenido = mk({ order_id: 900, empresa: "lk", cod: "4275", razon_social: "Zhang Qikuan",
                          fecha_recep: "2026-09-04", zona: "Zona 1 - CABA Sur", m3: 0.172,
                          cuarentena_motivos: ["deuda", "cliente_nuevo"],
                          cuarentena_detalle: { deuda: 2734562, nuevo_pedidos: 0 } });
    _apr.pedidos = [retenido, mk({ order_id: 901, razon_social: "Cliente Dos" })];
    _apr.pedidosTodos = _apr.pedidos.slice();
    _apr.cuarContacto = {};                       // sin teléfono cargado → botón "Sin tel."
    _apr.cuarComN = { "lk:900": 3 };              // el contador que trae el lote
    aprRender(); await new Promise((res) => setTimeout(res, 200));
    html = document.getElementById("pppPreview").innerHTML;
    out.tblEs = /cuar-tbl"/.test(html) && /<th>NP<\/th>/.test(html) && /<th>Pedido<\/th>/.test(html) &&
                /<th>Motivos<\/th>/.test(html) && /<th class="cuar-td-com">Coment\.<\/th>/.test(html);
    out.tblSinFichas = !/apr-card apr-card-cuar/.test(html);
    out.tblFecha = /cuar-tbl-fecha[^>]*>04\/09</.test(html);
    out.tblEspera = /apr-chip-esp/.test(html);
    out.tblM3 = /cuar-card-m3">0,172 m³</.test(html);
    out.tblCod = /cuar-card-cod[^>]*>LK 4275</.test(html);
    out.tblZona = /Zona 1 - CABA Sur/.test(html);
    out.tblBadges = /cuar-badge b-deuda/.test(html) && /cuar-badge b-nuevo/.test(html);
    out.tblBotones = /cuar-wpp-cob/.test(html) && /apr-anular/.test(html) &&
                     /Enviar a Pedidos a programar/.test(html);
    out.tblLibrito = /cuarComAbrirPed\('lk','900'\)/.test(html) && /📖<b>3<\/b>/.test(html);
    // la flechita abre el contenido del pedido en una fila aparte, a lo ancho de la tabla
    aprToggle("clk900"); await new Promise((res) => setTimeout(res, 120));
    html = document.getElementById("pppPreview").innerHTML;
    out.tblDetalle = /cuar-tbl-det/.test(html) && /colspan="9"/.test(html);
    aprToggle("clk900"); await new Promise((res) => setTimeout(res, 100));

    // el 📖 de un retenido abre el MISMO log, con la clave del pedido
    window.aprRpc = async function (fn, args) {
      llamadas.push({ fn: fn, args: args });
      if (fn === "gv_cuarentena_comentarios")
        return [{ id: 9, creado_at: "2026-09-15T08:00:00-03:00", persona: "Vivi", por: "vivi@x", texto: "Quedó de pagar hoy" }];
      if (fn === "gv_cuarentena_comentarios_lote") return [{ empresa: "lk", clave: "900", n: 3 }];
      if (fn === "gv_cuarentena_pago") return [{ cod: "4275", empresa: "lk", deuda_al_pagar: 2734562, pedidos_liberados: 1 }];
      return null;
    };
    cuarComAbrirPed("lk", "900"); await new Promise((res) => setTimeout(res, 150));
    const rh = (document.getElementById("cuarComModal") || {}).innerHTML || "";
    out.retComModal = /📖 Comentarios/.test(rh) && /Quedó de pagar hoy/.test(rh) && /Zhang Qikuan/.test(rh);
    const rcom = llamadas.find(function (c) { return c.fn === "gv_cuarentena_comentarios"; });
    out.retComClave = !!rcom && rcom.args.p_empresa === "lk" && rcom.args.p_order_id === "900";
    cuarComCerrar();

    // el contador sale de la RPC de lote, en UNA sola llamada para toda la lista
    llamadas.length = 0; _apr.cuarComN = null; _apr.cuarComNLoading = false;
    await cuarComLoteCargar(); await new Promise((res) => setTimeout(res, 80));
    const lote = llamadas.filter(function (c) { return c.fn === "gv_cuarentena_comentarios_lote"; });
    out.loteUna = lote.length === 1 && Array.isArray(lote[0].args.p_pedidos) &&
                  lote[0].args.p_pedidos.length === 1 && lote[0].args.p_pedidos[0].clave === "900";
    out.loteN = cuarComN(retenido) === 3;

    // (9) v18.04 — "Ya pagó" se fue; en su lugar está ANULAR, con confirmación y comentario.
    out.sinYaPago = !/cuar-pago/.test(html) && !/Ya pag/.test(html) &&
                    typeof window.cuarYaPago === "undefined";
    out.anularEnCuar = /apr-anular apr-anular-chico/.test(html) &&
                       /aprAnularAbrir\('lk','900'\)/.test(html);

    llamadas.length = 0;
    const confirmOrig = window.confirm;
    let confirmado = null;
    window.confirm = function (t) { confirmado = String(t || ""); return true; };
    aprAnularAbrir("lk", "900"); await new Promise((res) => setTimeout(res, 150));
    let anh = (document.getElementById("cuarComModal") || {}).innerHTML || "";
    out.anuModal = /✕ Anular pedido/.test(anh) && /Zhang Qikuan/.test(anh) &&
                   /no lo toma m[aá]s/.test(anh) && /¿Quién lo anula\?/.test(anh);
    // sin persona no anula
    document.getElementById("cuarComTexto").value = "lo cargó mal el cliente";
    await aprAnularConfirmar(); await new Promise((res) => setTimeout(res, 100));
    out.anuSinQuien = !llamadas.some(function (c) { return c.fn === "gv_pedido_anular"; }) &&
                      /Decinos quién anula/.test((document.getElementById("cuarComModal") || {}).innerHTML || "");
    // con persona pero sin motivo tampoco
    cuarQuienSet("Vivi");
    document.getElementById("cuarComTexto").value = "";
    await aprAnularConfirmar(); await new Promise((res) => setTimeout(res, 100));
    out.anuSinMotivo = !llamadas.some(function (c) { return c.fn === "gv_pedido_anular"; }) &&
                       /por qué se anula/.test((document.getElementById("cuarComModal") || {}).innerHTML || "");
    // con las dos cosas: confirma y llama a la RPC con el snapshot del pedido
    document.getElementById("cuarComTexto").value = "pedido duplicado, lo cargó dos veces";
    await aprAnularConfirmar(); await new Promise((res) => setTimeout(res, 150));
    window.confirm = confirmOrig;
    const anu = llamadas.find(function (c) { return c.fn === "gv_pedido_anular"; });
    out.anuPideConfirmar = /¿Anular/.test(String(confirmado || "")) &&
                           /pedido duplicado/.test(String(confirmado || "")) && /Vivi/.test(String(confirmado || ""));
    out.anuRpc = !!anu && anu.args.p_empresa === "lk" && anu.args.p_clave === "900" &&
                 anu.args.p_motivo === "pedido duplicado, lo cargó dos veces" &&
                 anu.args.p_persona === "Vivi" && anu.args.p_es_isis === false;
    out.anuSnapshot = !!anu && !!anu.args.p_datos && anu.args.p_datos.cod === "4275" &&
                      anu.args.p_datos.razon_social === "Zhang Qikuan" && anu.args.p_datos.m3 === "0.172";
    out.anuCierra = !!(document.getElementById("cuarComModal") || {}).hidden;

    // una NP de ISIS viaja con p_es_isis = true
    llamadas.length = 0;
    const isisPed = mk({ order_id: "np98617", empresa: "lk", cod: "2381", razon_social: "Riondini Lucas",
                         _isis: true, np: "98617", cuarentena_motivos: ["deuda"], cuarentena_detalle: { deuda: 1000 } });
    _apr.pedidos = [isisPed]; _apr.pedidosTodos = [isisPed];
    window.confirm = function () { return true; };
    aprAnularAbrir("lk", "np98617"); await new Promise((res) => setTimeout(res, 150));
    cuarQuienSet("Marian");
    document.getElementById("cuarComTexto").value = "la NP se tipeó mal en ISIS";
    await aprAnularConfirmar(); await new Promise((res) => setTimeout(res, 150));
    window.confirm = confirmOrig;
    const anuI = llamadas.find(function (c) { return c.fn === "gv_pedido_anular"; });
    out.anuIsis = !!anuI && anuI.args.p_clave === "np98617" && anuI.args.p_es_isis === true &&
                  anuI.args.p_persona === "Marian" && anuI.args.p_datos.np_label === "NP 98617";

    // (10) v18.04 — en "Pedidos a programar" el botón va DEBAJO del detalle, al expandir
    _apr.cuarCom = null; _apr.exp = {};
    const normal = mk({ order_id: 950, razon_social: "Cliente Normal SA",
                        bloques: [{ np_idx: 1, m3: 0.4, lineas: 1, cajas: 2, items: [{ art: "505", uni: 24, uxb: 12, cajas: 2 }] }] });
    _apr.pedidos = [normal]; _apr.pedidosTodos = [normal];
    aprRender(); await new Promise((res) => setTimeout(res, 150));
    html = document.getElementById("pppPreview").innerHTML;
    out.anuCerradoNo = !/apr-anular/.test(html);          // cerrado: el botón NO está
    aprToggle("p950"); await new Promise((res) => setTimeout(res, 150));
    html = document.getElementById("pppPreview").innerHTML;
    out.anuAbiertoSi = /apr-anular-row/.test(html) && /aprAnularAbrir\('lk','950'\)/.test(html) &&
                       html.indexOf("apr-anular-row") > html.indexOf("apr-tab");   // debajo del detalle

    // (11) v18.04 — el log de anulados
    _apr.anulados = [
      { id: 1, empresa: "lk", clave: "1416", es_isis: false, np_label: "web LK 1416", np: null,
        cod: "3969", razon_social: "Rodriguez Jonatan", m3: 0.024, motivo: "lo cargó mal el cliente",
        persona: "Vivi", por: "vivi@loekemeyer.com", anulado_at: "2026-09-15T10:20:00-03:00" },
      // v18.05: uno que YA tenía NP asignada — la NP se muestra y no se reutiliza
      { id: 2, empresa: "lk", clave: "1375", es_isis: false, np_label: "web LK 1375", np: "LK 0052",
        cod: "3905", razon_social: "Andser Quimica SRL", m3: 0.025, motivo: "cancelado por el cliente",
        persona: "Marian", por: "marian@loekemeyer.com", anulado_at: "2026-09-15T11:00:00-03:00" }
    ];
    aprRender(); await new Promise((res) => setTimeout(res, 120));
    html = document.getElementById("pppPreview").innerHTML;
    out.anuChip = /apr-anu-chip[^>]*>✕ 2 anulados</.test(html);
    aprAnuAbrir(); await new Promise((res) => setTimeout(res, 120));
    const lh = (document.getElementById("aprAnuModal") || {}).innerHTML || "";
    out.anuLog = /Pedidos anulados/.test(lh) && /web LK 1416/.test(lh) &&
                 /lo cargó mal el cliente/.test(lh) && /<b>Vivi<\/b>/.test(lh) &&
                 /15\/09 10:20/.test(lh) && /LK 3969/.test(lh);
    // v18.05 — la columna NP: el que tenía NP la muestra; el que no, dice "sin NP"
    out.anuLogNp = /<th>NP<\/th>/.test(lh) &&
                   /apr-anu-np[^>]*><span class="cuar-card-np">LK 0052<\/span>/.test(lh) &&
                   /sin NP/.test(lh) && /no se reutiliza/.test(lh);
    aprAnuCerrar();
    out.anuLogCerrado = !!(document.getElementById("aprAnuModal") || {}).hidden;

    // (12) v18.06 (Luis) — Config. Cuarentena: el log NO tiene scroll propio; scrollea la pestaña
    _pppTab = "cuarcfg";
    _apr.cuarLog = [];
    for (let i = 0; i < 18; i++) _apr.cuarLog.push({
      empresa: "lk", clave: String(1400 + i), np: "web LK " + (1400 + i), cod: String(3900 + i),
      razon_social: "Cliente Numero " + i + " S.R.L.", motivos: ["deuda"], deuda: 1234567,
      entro_at: "2026-09-14T12:00:00-03:00", estado: "retenido", cerrado_at: null,
      persona: null, por: null, comentario: null, comentarios: 0, eventos: 1 });
    pppRenderProg(); await new Promise((res) => setTimeout(res, 250));
    pppFitPantalla(); await new Promise((res) => setTimeout(res, 200));
    const cfgBody = document.querySelector("#pppOverlay .planim-body");
    const cfgWrap = document.querySelector(".cuar-log-tblwrap");
    out.cfgFilas = document.querySelectorAll(".cuar-log-tbl tbody tr").length;
    // el zoom automático no achica esta pestaña (es una tabla larga, como A Programar)
    out.cfgSinZoom = !!cfgBody && (cfgBody.style.zoom === "1" || cfgBody.style.zoom === "");
    out.cfgPaginaScrollea = !!cfgBody && cfgBody.style.overflowY === "auto";
    // y el submódulo NO tiene su propia barra vertical: la tabla se dibuja entera
    out.cfgSinScrollPropio = !!cfgWrap && cfgWrap.scrollHeight <= cfgWrap.clientHeight + 1;
    _pppTab = "prog";

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
  chk(r.nuevoFueraDeCuar, "cliente nuevo puro: NO cae en Cuarentena; sólo el mixto (deuda+nuevo) queda (1)");
  chk(r.nuevoBadge, "cliente nuevo mixto: badge '🆕 Cliente nuevo' en Cuarentena");
  chk(r.nuevoMotivo, "cliente nuevo: el motivo dice cuántos pedidos facturó");
  chk(r.cliNuevosCuenta, "pestaña 'Clientes nuevos': muestra el pedido puro (1)");
  chk(r.nuevoCodChip, "cliente nuevo de Chef: el chip dice CH 2533 (en Clientes nuevos)");
  chk(r.cliNuevosSinMixto, "el pedido mixto (deuda+nuevo) NO aparece en Clientes nuevos");
  chk(r.cliCols, "Clientes nuevos tiene columnas '1er contacto' y 'Acción'");
  chk(r.cliSpeech, "Contacto tiene los botones 'Speech 1' y 'Speech 2'");
  chk(r.cliAccion, "Acción tiene 'Aprobar pedido' y 'Eliminar pedido'");
  chk(r.cliMontoIva, "Monto muestra el total con IVA debajo del neto (c/IVA $121.000)");
  chk(r.cliMsgTotal, "Speech 1 manda el TOTAL con IVA del pedido");
  chk(r.cliMsgSinSena, "Speech 1 ya NO pide seña del 30%");
  chk(r.cliMsgAdelantado, "Speech 1 dice que el pago va por adelantado, antes de armar y entregar");
  chk(r.cliDemoFila, "'Ver ejemplo' muestra una fila EJEMPLO con su monto ($120.480)");
  chk(r.cliDemoNoCuenta, "el ejemplo NO suma al badge (sigue en 1 real)");
  chk(r.cliColapsaTitulo, "colapsar Clientes nuevos: el título con el contador (1) queda");
  chk(r.cliColapsaSinTabla, "colapsar Clientes nuevos: la tabla se esconde");
  chk(r.nuevoEtq === "Cliente nuevo", "etiqueta de cliente_nuevo = 'Cliente nuevo'");
  chk(r.ypTabla, "ya programados: es una tabla con columnas NP / … / Enviar a");
  chk(r.ypSinColAprob, "ya programados: sin columna Aprobación (el aprobado sale de la lista)");
  chk(r.ypCuenta, "ya programados: el contador cuenta las 2 filas");
  chk(r.ypCod, "ya programados: el número de cliente por empresa (LK 4263 / CH 2715)");
  chk(r.ypBadges, "ya programados: los motivos salen como badges");
  chk(r.ypLibrito, "ya programados: el librito 📖 con la cantidad de comentarios");
  chk(r.comModal, "el librito abre el log con fecha, hora y autor");
  chk(r.comPideTexto, "el log deja agregar un comentario nuevo");
  chk(r.comPideQuien, "comentar pide quién (identidad obligatoria)");
  chk(r.comSinQuien, "sin identidad NO guarda el comentario y avisa");
  chk(r.comConQuien, "con identidad guarda el comentario con la persona");
  chk(r.comRpc, "el log pide los comentarios de ESE pedido (empresa + clave)");
  chk(r.comCerrado, "el modal se cierra");
  chk(r.aprModal, "aprobar abre el cuadro de comentario (no libera de una)");
  chk(r.aprSinLiberar, "aprobar NO llamó a gv_cuarentena_liberar antes de confirmar");
  chk(r.aprPideQuien, "aprobar pide quién (Vivi / Marian / Otro)");
  chk(r.aprSinQuien, "sin elegir quién NO libera y avisa");
  chk(r.aprLibera, "al confirmar libera y manda el comentario y la persona");
  chk(r.marcarCol, "la tabla tiene la columna 'Enviar a'");
  chk(r.marcarSinAprobar, "sin aprobar: ofrece Aprobar y Cuarentena");
  chk(r.marcarAprobada, "todas las filas ofrecen Aprobar y Cuarentena");
  chk(r.marcarFilas, "las dos filas ofrecen volver a cuarentena");
  chk(r.devModal, "volver a cuarentena avisa que lo saca de la programación y de qué tanda");
  chk(r.devPideQuien, "volver a cuarentena pide quién");
  chk(r.devSinQuien, "sin elegir quién NO devuelve");
  chk(r.devRpc, "al confirmar llama gv_cuarentena_devolver con NP, clave, comentario y persona");
  chk(r.logTitulo, "Config. Cuarentena tiene el log con la cantidad de pedidos");
  chk(r.logFilas, "el log lista NP, cliente y su número");
  chk(r.logEstado, "el log muestra el estado (aprobado / retenido)");
  chk(r.logQuien, "el log dice quién aprobó, cuándo y con qué usuario");
  chk(r.logEntro, "el log dice cuándo entró a cuarentena");
  chk(r.logComent, "el log abre los comentarios del pedido");
  chk(r.logComRet, "el log muestra el comentario de un pedido retenido, con quién y cuándo");
  chk(r.logChips, "el log tiene chips por estado con su cantidad");
  chk(r.logFiltra, "tocar un chip filtra la tabla y el 📖 sigue apuntando al pedido correcto");
  chk(r.logFiltraOff, "tocarlo de nuevo vuelve a mostrar todos");
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
  // v18.01 — los retenidos como lista/tabla
  chk(r.tblEs, "los retenidos son una TABLA con NP / Pedido / Motivos / Coment.");
  chk(r.tblSinFichas, "ya no se dibujan las fichas de 340px");
  chk(r.tblFecha, "la tabla muestra la fecha del pedido (04/09)");
  chk(r.tblEspera, "al lado de la fecha va el chip de hace cuánto llegó");
  chk(r.tblM3, "la tabla conserva el m³ del pedido");
  chk(r.tblCod, "la tabla conserva el chip del número de cliente (LK 4275)");
  chk(r.tblZona, "la tabla conserva la zona");
  chk(r.tblBadges, "la tabla conserva los badges de motivo");
  chk(r.tblBotones, "la tabla conserva los botones (cobranzas, Enviar a programar, Anular)");
  chk(r.tblLibrito, "cada fila tiene el 📖 con su cantidad de comentarios");
  chk(r.tblDetalle, "la flechita abre el contenido del pedido en una fila a todo el ancho");
  chk(r.retComModal, "el 📖 de un retenido abre el log de comentarios");
  chk(r.retComClave, "el log pide los comentarios de ESE pedido (empresa + order_id)");
  chk(r.loteUna, "el contador de comentarios se pide UNA vez para toda la lista");
  chk(r.loteN, "el contador que devuelve el lote llega a la fila");
  // v18.04 — se fue "Ya pagó" y entró "Anular pedido"
  chk(r.sinYaPago, "el botón 'Ya pagó' ya no está (ni su función)");
  chk(r.anularEnCuar, "Cuarentena tiene el botón '✕ Anular pedido'");
  chk(r.anuModal, "anular abre un cuadro que explica qué hace y pide quién lo anula");
  chk(r.anuSinQuien, "sin persona NO anula y avisa");
  chk(r.anuSinMotivo, "sin motivo NO anula y avisa (el motivo es obligatorio)");
  chk(r.anuPideConfirmar, "pide confirmación con el pedido, el motivo y quién lo anula");
  chk(r.anuRpc, "llama a gv_pedido_anular con empresa, clave, motivo y persona");
  chk(r.anuSnapshot, "manda el snapshot del pedido (cliente, código y m³) para el log");
  chk(r.anuCierra, "al anular se cierra el cuadro");
  chk(r.anuIsis, "una NP de ISIS viaja con p_es_isis = true y su etiqueta");
  chk(r.anuCerradoNo, "en 'Pedidos a programar' el botón NO está con la ficha cerrada");
  chk(r.anuAbiertoSi, "al expandir la NP aparece debajo del detalle");
  chk(r.anuChip, "la cabecera muestra el chip '✕ N anulados'");
  chk(r.anuLog, "el log lista cuándo, qué pedido, cliente, quién y por qué");
  chk(r.anuLogNp, "el log muestra la NP que se quemó (y dice que no se reutiliza)");
  chk(r.anuLogCerrado, "el log se cierra");
  // v18.06 — Config. Cuarentena sin scroll adentro del submódulo
  chk(r.cfgFilas === 18, "Config. Cuarentena dibuja las 18 filas del log (dio " + r.cfgFilas + ")");
  chk(r.cfgSinZoom, "el zoom automático NO achica la pestaña Config. Cuarentena");
  chk(r.cfgPaginaScrollea, "la que scrollea es la pestaña, no el submódulo");
  chk(r.cfgSinScrollPropio, "el log NO tiene barra de scroll vertical propia");
  chk(errs.length === 0, "sin errores de página" + (errs.length ? " (" + errs.join(" | ") + ")" : ""));

  await b.close();
  if (fallos.length) { console.log("\nFALLARON " + fallos.length + ":\n· " + fallos.join("\n· ")); process.exit(1); }
  console.log("\napr-cuarentena OK");
})();
