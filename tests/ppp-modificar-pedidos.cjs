/* v18.14 (Luis, 2026-09-15) — PPP · «Modificar Pedidos»: buscador, filtros y tabla POR PEDIDO.

   Pedido: *"debería poder buscar pedidos (que estén en A programar y en Programación) — y ojo acá
   digo PEDIDOS, no NPs, ya que un pedido puede estar dividido en múltiples NPs. De momento hacé
   que tenga filtros, barra de búsqueda y muestre una tabla con los pedidos actuales a programar y
   programados (pedidos y que todavía no hayan salido)"*. Y: *"poné la pestaña entre Ocupación y
   Config. Cuarentena"*.

   ⚠ Lo que de verdad hay que fijar es que la unidad sea EL PEDIDO. Medido en la base el 15/09:
   26 de los 74 pedidos web programados están partidos en varias NP (hasta 4) — listando NP, el
   mismo pedido saldría tres veces. El fixture reproduce ese caso a propósito.

   Lo que fija este test:
     · la solapa quedó entre Ocupación y Config. Cuarentena;
     · un pedido de 3 NP es UN renglón, con sus 3 NP y la suma de sus m³;
     · una NP de ISIS es su propio pedido (su `clave` es la NP y no se repite);
     · entran los de A Programar y los programados, y NO los que ya salieron;
     · si SOLO ALGUNAS NP del pedido salieron, el pedido sigue con las que quedan;
     · la búsqueda encuentra por número de pedido, por CUALQUIERA de sus NP, por cliente y por tanda;
     · los filtros (dónde, empresa, estado) recortan, y «Limpiar» los devuelve;
     · el contador dice pedidos y NP por separado.
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
  const p = await b.newPage({ viewport: { width: 1400, height: 950 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    window.getTodayKey = () => "2026-09-15";
    _pppParsed = { prog: [] };
    window._pppPlanAgrupar = function () { return { venc: [], byDay: new Map() }; };
    window.pgaNeed = function () {};
    window.aprCargar = function () { return Promise.resolve(); };

    const np = (o) => Object.assign({
      fecha: "2026-09-17", tanda: "E12L", np: "LK 0004", np_num: 4, cod: "3843",
      razon_social: "Chen Li Yu", localidad: "Flores", zona: "Zona 3 - CABA Oeste",
      zona_corta: "Zona 3", empresa: "LK", origen: "web", m3: 0.5, estado: "pendiente",
      estado_orden: 1, clave: "1343", barrio: "Flores", fecha_pedido: "2026-09-11"
    }, o || {});

    /* El pedido 1343 está partido en TRES NP — el caso que motivó todo. Más: un pedido de dos NP
       del que una ya salió, dos NP de ISIS (cada una su propio pedido, `clave` = NP) y un pedido
       entero ya salido, que no tiene que aparecer. */
    _pgaRows = [
      np({ np: "LK 0004", m3: 0.5 }),
      np({ np: "LK 0005", m3: 0.3 }),
      np({ np: "LK 0006", m3: 0.2 }),
      np({ np: "LK 0007", clave: "1344", cod: "288", razon_social: "Torres Y Liva S.A Cif",
           tanda: "E01A", fecha: "2026-09-15", m3: 0.8, estado: "armado" }),
      np({ np: "LK 0008", clave: "1344", cod: "288", razon_social: "Torres Y Liva S.A Cif",
           tanda: "E01A", fecha: "2026-09-15", m3: 0.2, estado: "armado" }),
      np({ np: "98701", clave: "98701", origen: "isis", cod: "1974",
           razon_social: "Pettish Lacroze 2481", tanda: "D67E", m3: 0.9, estado: "facturado" }),
      np({ np: "98702", clave: "98702", origen: "isis", cod: "1974",
           razon_social: "Pettish Lacroze 2481", tanda: "D67E", m3: 0.4, estado: "facturado" }),
      np({ np: "CH 0020", clave: "1001430", empresa: "CH", cod: "2643",
           razon_social: "El Martillo Srl", tanda: "E12H", fecha: "2026-09-21", m3: 1.1 }),
      // este pedido entero YA SALIÓ: no tiene que aparecer
      np({ np: "LK 0099", clave: "1399", cod: "9999", razon_social: "Ya Salio SA",
           tanda: "E09Z", m3: 2.0 })
    ];
    _pgaTs = Date.now();
    // lo que ya salió: la LK 0099 entera, y UNA sola NP del pedido 1344
    _pppEnSalida = new Map([["LK 0099", {}], ["LK 0008", {}]]);
    window.pppLoadEntregados = function () { return new Set(); };

    // A Programar: dos pedidos, uno de ellos con 2 bloques
    _apr.listo = true; _apr.cargando = false;
    _apr.pedidos = [
      { order_id: 1360, empresa: "lk", cod: "4321", razon_social: "Web Nueva SRL",
        fecha_recep: "2026-09-14", zona: "Zona 1 - CABA Sur", localidad: "Barracas",
        m3: 0.3, lineas: 3, cajas: 5, bloques: [{ np_idx: 1 }, { np_idx: 2 }] },
      { order_id: 217, empresa: "chef", cod: "2533", razon_social: "Osa Hermanos",
        fecha_recep: "2026-09-13", zona: "Zona 2 - CABA Centro", localidad: "Almagro",
        m3: 0.9, lineas: 2, cajas: 4, bloques: [{ np_idx: 1 }] },
      /* v18.29 (Luis) — el que un supervisor sacó de su tanda YA ARMADO: en A Programar tiene que
         seguir diciendo que está armado y a qué tanda vuelve, no volver a "pendiente". Los tres
         campos los pega `aprTraerPedidos` desde `GV_PPP_Web_Retenido`. */
      { order_id: 1372, empresa: "lk", cod: "5555", razon_social: "Volvio Armado SA",
        fecha_recep: "2026-09-12", zona: "Zona 1 - CABA Sur", localidad: "Soldati",
        m3: 0.4, lineas: 1, cajas: 2, bloques: [{ np_idx: 1 }],
        tanda_previa: "E12L", ya_pickeada: true, ya_armada: true }
    ];

    document.getElementById("pppOverlay").classList.add("show");

    // ── (1) la solapa, entre Ocupación y Config. Cuarentena ────────────────
    pppPaintTabs();
    const tabs = [...document.querySelectorAll("#pppTabsBar .ppp-tab")].map((e) => e.textContent.trim());
    out.tabs = tabs;
    const iM = tabs.findIndex((t) => /Modificar Pedidos/.test(t));
    // v19.01 — se mide el ORDEN, no que sean vecinas pegadas. Lo que pidió Luis es que la solapa
    // vaya "entre Ocupación y Config. Cuarentena", y eso sigue siendo cierto aunque después se
    // agregue otra en el medio (pasó con «🆕 Clientes nuevos», que dejó este test en rojo en main
    // sin que nadie tocara Modificar Pedidos).
    const iO = tabs.findIndex((t) => /Ocupación/.test(t));
    const iC = tabs.findIndex((t) => /Cuarentena/.test(t));
    out.entreOcupYCuar = iO >= 0 && iM > iO && iC > iM;

    pppTab("modif");
    await new Promise((res) => setTimeout(res, 150));
    const box = document.getElementById("pppPreview");
    /* v18.15 — el orden lo fijó Luis: Cliente · NP · Zona/Barrio · fecha de PEDIDO · fecha en
       PROGRAMACIÓN · Tanda · Estado · Modificar. La columna del número de pedido se fue ("no
       significa nada"), igual que los m³; el número igual se sigue pudiendo buscar. */
    const filas = () => [...box.querySelectorAll("tr.pmod-row")].map((tr) => ({
      rs: tr.children[0].textContent.trim(), nps: tr.children[1].textContent.trim(),
      zona: tr.children[2].textContent.trim(), fPed: tr.children[3].textContent.trim(),
      fProg: tr.children[4].textContent.trim(), tanda: tr.children[5].textContent.trim(),
      est: tr.children[6].textContent.trim(), btn: tr.children[7].textContent.trim(),
      cod: (tr.querySelector(".pmod-cod") || {}).textContent || ""
    }));

    // ── (2) UN renglón por pedido, no por NP ───────────────────────────────
    const f = filas();
    out.nFilas = f.length;                       // 7 pedidos (9 NP - 1 salida... ver abajo)
    out.peds = f.map((x) => x.rs + " [" + x.cod + "]");
    const p1343 = f.find((x) => /Chen Li Yu/.test(x.rs));
    out.partidoUnaFila = f.filter((x) => /Chen Li Yu/.test(x.rs)).length === 1;
    out.partidoTraeSusNps = !!p1343 && /LK 0004/.test(p1343.nps) && /LK 0005/.test(p1343.nps) &&
                            /LK 0006/.test(p1343.nps);
    out.partidoDice3 = !!p1343 && /3 NP/.test(p1343.nps);
    // ISIS: cada NP es su propio pedido
    out.isisSeparadas = f.filter((x) => /98701|98702/.test(x.nps)).length === 2;

    // ── (3) lo que ya salió ────────────────────────────────────────────────
    out.salidaFuera = !f.some((x) => /Ya Salio/.test(x.rs) || /LK 0099/.test(x.nps));
    // del 1344 salió UNA sola NP: el pedido queda, con la que falta
    const p1344 = f.find((x) => /Torres/.test(x.rs));
    out.parcialQueda = !!p1344 && /LK 0007/.test(p1344.nps) && !/LK 0008/.test(p1344.nps);

    // ── (4) los de A Programar están ───────────────────────────────────────
    out.aprEstan = f.some((x) => /Web Nueva/.test(x.rs)) && f.some((x) => /Osa Hermanos/.test(x.rs));
    const p1360 = f.find((x) => /Web Nueva/.test(x.rs));
    out.aprSinNpTodavia = !!p1360 && /bloques|sin NP/.test(p1360.nps);
    // "si corresponde": sin día ni tanda todavía, y la fecha del PEDIDO sí está
    out.aprSinDiaNiTanda = !!p1360 && p1360.fProg === "—" && p1360.tanda === "—";
    out.aprConFechaPedido = !!p1360 && /14\/09/.test(p1360.fPed);

    // ── (4b) las columnas y el botón ──────────────────────────────────────
    out.columnas = [...box.querySelectorAll("table.pmod-tab thead th")]
      .map((e) => e.textContent.trim()).filter(function (x) { return x; });
    out.codConEmpresa = f.some((x) => /LK 3843/.test(x.cod)) && f.some((x) => /CH 2643/.test(x.cod));
    out.botonEnCadaFila = f.every((x) => x.btn === "Modificar");
    /* v18.23 — el botón ABRE EL MODAL. Se le pone delante un fetch de mentira para el
       proyecto de LK (que es donde vive el pedido) y se chequea: (a) lo que NO se puede
       modificar avisa y no abre nada; (b) lo que sí, abre con el contenido del pedido;
       (c) tocar cajas y agregar un código llega al backend con los números correctos. */
    let aviso = ""; window.alert = function (m) { aviso = String(m); };
    window.confirm = function () { return true; };
    window.pwebLkToken = async function () { return "tok"; };
    window.aprQuien = async function () { return "luis@lk"; };
    // aprRpc pide las cabeceras de escritura (sesión de supervisor): sin esto la RPC ni sale
    window.facAuthWriteHeaders = async function () {
      return { apikey: "k", Authorization: "Bearer t", "Content-Type": "application/json" }; };
    window.pppLoadProgFromSupabase = async function () {};
    const lk = []; const personas = [{ id: 1, nombre: "Mariana" }];
    const J = (d) => Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(d),
      text: () => Promise.resolve(JSON.stringify(d)), headers: { get: () => null } });
    const CTX = {
      empresa: "lk", order_id: 1343, cod_cliente: "3843", razon_social: "Chen Li Yu",
      sucursal_entrega: "Rivadavia 100 - Flores", enviado_a_compras: false,
      items: [{ i: 0, cod_art: "027", cod: "027", cajas: 2, uxb: 24, descripcion: "Aceite", catalogo: true },
              { i: 1, cod_art: "544", cod: "544", cajas: 1, uxb: 12, descripcion: "Fideos", catalogo: true }],
      items_raw: [{ cod_art: "027", cajas: 2, uxb: 24, cod_original: null },
                  { cod_art: "544", cajas: 1, uxb: 12, cod_original: null }],
      direcciones: [{ slot: 1, label: "Rivadavia 100 - Flores", direccion: "Rivadavia 100",
                      localidad: "Flores", provincia: "CABA", barrio: "Flores", actual: true },
                    { slot: 2, label: "Depósito Lanús", direccion: "Falsa 123",
                      localidad: "Lanús", provincia: "Buenos Aires", barrio: "Lanus", actual: false }],
      sin_stock: ["544"], estado: { estado: "programado", facturado: false, entregado: false }, log: []
    };
    window.fetch = function (url, opt) {
      const u = String(url), b = (opt && opt.body) ? JSON.parse(opt.body) : null;
      if (/rpc\/gv_pedido_mod_ctx/.test(u)) {
        lk.push(["ctx", b]);
        if (b && b.p_empresa === "chef") return J(Object.assign({}, CTX, {
          empresa: "chef", order_id: 1001430, razon_social: "El Martillo Srl",
          sucursal_entrega: "Passaponti 6501 - Moreno",
          items: [{ i: 0, cod_art: "769L", cod: "769L", cajas: 8, uxb: 24, descripcion: "Loeke por Chef", catalogo: true }],
          items_raw: [{ cod_art: "769L", cajas: 8, uxb: 24 }],
          direcciones: [{ slot: 1, label: "Passaponti 6501 - Moreno", direccion: "Passaponti 6501",
                          localidad: "Moreno", barrio: "Moreno", actual: true }],
          catalogo: [{ cod: "043", desc: "Algo de Chef", uxb: 12 }, { cod: "769L", desc: "Loeke por Chef", uxb: 24 }]
        }));
        return J(CTX);
      }
      if (/rpc\/gv_pedido_mod_guardar/.test(u)) { lk.push(["guardar", b]); return J({ ok: true, log_id: 7, detalle: {} }); }
      if (/GV_Modif_Personas/.test(u)) return J(personas.slice());
      if (/gv_ppp_np_items/.test(u)) return J([{ art: "034", cajas: 2, uxb: 12, renglones: 1 },
                                               { art: "960E", cajas: 1, uxb: 6, renglones: 1 }]);
      if (/gv_ppp_programacion_diaria/.test(u)) return J([{ np: "98701", direccion: "Lacroze 2481",
                                                            barrio: "Colegiales", zona: "Zona 1", tanda: "D67E" }]);
      if (/gv_uxb_resuelto/.test(u)) return J([{ cod: "034", uxb: 12 }, { cod: "960E", uxb: 6 }, { cod: "777", uxb: 24 }]);
      if (/rpc\/gv_pedido_mod_isis/.test(u)) { lk.push(["isis", b]);
        return J({ ok: true, np: "98701", detalle: { m3_de: 0.437, m3_a: 0.488, m3_sin_dato: null } }); }
      if (/rpc\/gv_modif_persona_agregar/.test(u)) {
        lk.push(["persona", b]); personas.push({ id: personas.length + 1, nombre: b.p_nombre });
        return J([{ id: personas.length, nombre: b.p_nombre }]); }
      if (/\/rest\/v1\/(products|loke_products)/.test(u))
        return J([{ cod: "027", description: "Aceite", uxb: 24 }, { cod: "544", description: "Fideos", uxb: 12 },
                  { cod: "601", description: "Arroz", uxb: 6 }]);
      return J([]);
    };
    const btnDe = (rs) => [...box.querySelectorAll("tr.pmod-row")]
      .filter((tr) => new RegExp(rs).test(tr.children[0].textContent))[0].querySelector(".pmod-btn");
    const esperar = () => new Promise((res) => setTimeout(res, 80));
    const abierto = () => !!document.querySelector("#pmodOverlay.show");

    /* (a) v18.35 (Luis: *"para los pedidos de isis no hay problema con que se cambien en la PPP"*):
       una NP de ISIS AHORA se modifica. Abre el mismo modal, pero con los renglones que trae
       Gestión y con la dirección como dos campos libres (ISIS no tiene libreta de direcciones). */
    aviso = ""; btnDe("Pettish").click(); await esperar();
    const ovI = document.getElementById("pmodOverlay");
    out.isisAbre = abierto();
    out.isisItems = [...ovI.querySelectorAll(".pme-tab tbody tr")].map((tr) => tr.children[0].textContent.trim());
    out.isisDirLibre = /Dirección de entrega/.test(ovI.innerHTML) &&
      !ovI.querySelector("#pmeQuien ~ select") && ovI.innerHTML.indexOf("Barrio / localidad") > 0;
    out.isisAvisaPisa = /pisa/.test(ovI.innerHTML) && /MOD/.test(ovI.innerHTML);
    // se modifica y se guarda: tiene que ir por la RPC de ISIS, no por la de LK
    pmodCajas(0, "9");
    await pmodQuien("Mariana"); pmodMotivo("el cliente cambió el pedido por teléfono");
    pmodDirIsis("direccion", "Av. Siempreviva 742");
    await pmodGuardar(); await esperar();
    const gi = (lk.filter((x) => x[0] === "isis")[0] || [])[1] || {};
    out.isisGuardo = JSON.stringify(gi);
    out.isisDiceM3 = /m³/.test((document.getElementById("pppStatus") || {}).textContent || "");
    out.isisStatus = ((document.getElementById("pppStatus") || {}).textContent || "").slice(0, 120);
    out.isisNoFueALk = !lk.some((x) => x[0] === "guardar");
    pmodCerrar();

    /* (a2) v18.45 — Chef TAMBIÉN se modifica: Thomas dio los grants del lado de Chef, así que
       el backend despacha a su gemela `_chef`. Acá se chequea que el front mande la empresa
       correcta y que use el catálogo que viene DENTRO del contexto (el de Chef no se puede
       pedir por REST). */
    aviso = ""; lk.length = 0; btnDe("El Martillo").click(); await esperar();
    const ovC = document.getElementById("pmodOverlay");
    out.chefAbre = abierto();
    out.chefPidio = JSON.stringify((lk.filter((x) => x[0] === "ctx")[0] || [])[1] || {});
    out.chefItems = [...ovC.querySelectorAll(".pme-tab tbody tr")].map((tr) => tr.children[0].textContent.trim());
    out.chefCatalogo = /2 códigos en el catálogo/.test(ovC.innerHTML);
    pmodCajas(0, "12");
    await pmodQuien("Mariana"); pmodMotivo("el cliente de Chef pidió más cajas");
    await pmodGuardar(); await esperar();
    const gc = (lk.filter((x) => x[0] === "guardar")[0] || [])[1] || {};
    out.chefGuardo = JSON.stringify(gc);
    pmodCerrar();

    // (b) un pedido web de LK abre el modal con su contenido
    // (se vacía el registro de llamadas: si no, los chequeos de abajo leerían las de Chef)
    aviso = ""; lk.length = 0; btnDe("Chen Li Yu").click(); await esperar();
    out.abre = abierto();
    out.ctxPidio = JSON.stringify((lk.filter((x) => x[0] === "ctx")[0] || [])[1] || {});
    const ov = document.getElementById("pmodOverlay");
    out.modalTitulo = (ov.querySelector(".pme-title") || {}).textContent || "";
    out.modalItems = [...ov.querySelectorAll(".pme-tab tbody tr")].map((tr) => tr.children[0].textContent.trim());
    out.modalDirs = [...ov.querySelectorAll(".pme-sel option")].map((o) => o.textContent.trim());
    out.modalSinStock = /🕒/.test(ov.innerHTML);
    out.guardarApagado = !!(ov.querySelector(".pme-ok") || {}).disabled;   // sin cambios no se guarda

    out.personas = [...ov.querySelectorAll(".pme-sel")].map((s) => s.textContent).join(" | ");

    // (c) 2 -> 5 cajas del 027 y se agrega el 601
    pmodCajas(0, "5");
    ov.querySelector("#pmeNuevoCod").value = "601";
    ov.querySelector("#pmeNuevoCj").value = "4";
    pmodAgregar();
    out.filasDespues = [...document.querySelectorAll("#pmodOverlay .pme-tab tbody tr")].length;
    /* v18.29 (Luis) — con cambios pero SIN quién ni justificativo NO se guarda. Los dos chequeos
       de abajo son la parte que importa: que el botón siga apagado y que diga qué falta. */
    const btnOk = () => document.querySelector("#pmodOverlay .pme-ok");
    // el modal se acuerda del último que modificó (localStorage): para probar el guard hay que
    // vaciarlo a propósito, si no llega ya elegido de la vuelta anterior
    await pmodQuien("");
    out.sinQuien = !!btnOk().disabled && /quién/i.test(btnOk().title);
    await pmodQuien("Mariana");
    out.sinMotivo = !!btnOk().disabled && /justificativo/i.test(btnOk().title);
    pmodMotivo("el cliente llamó para sumar cajas");
    out.guardarPrendido = !btnOk().disabled;
    // y agregar un nombre nuevo va a la tabla de Gestión
    window.prompt = function () { return "Luis"; };
    await pmodQuien("__nueva"); await esperar();
    out.personaNueva = JSON.stringify((lk.filter((x) => x[0] === "persona")[0] || [])[1] || {});
    out.quedoElegido = /Luis/.test((document.getElementById("pmeQuien") || {}).value || "");
    await pmodQuien("Mariana");
    await pmodGuardar(); await esperar();
    const g = (lk.filter((x) => x[0] === "guardar")[0] || [])[1] || {};
    out.guardo = JSON.stringify(g.p_items || []);
    out.guardoEspera = JSON.stringify(g.p_espera || []);
    out.guardoQuien = g.p_quien;
    out.guardoMotivo = g.p_motivo;
    out.guardoNps = JSON.stringify(g.p_nps || []);
    out.cerroAlGuardar = !abierto();

    /* v18.19 (Luis) — dos cosas de esta tanda:
       (a) «Pedido del» SIN el día de la semana; «En programación» lo conserva (ahí sí sirve).
       (b) EL BOTÓN NO SE PUEDE ESCAPAR. Medido a 1180 px: con 2 pedidos la tabla entraba (1154) y
           con 120 medía 1242 → `.pmod-wrap` scrolleaba y el botón, última columna, quedaba fuera.
           Acá se fuerza el desborde achicando el wrap y se exige que el botón siga adentro con el
           scroll a la izquierda del todo. `stickyDesborda` es el control de no-trivialidad: sin
           desborde el chequeo pasaría solo. */
    /* v18.29 (Luis) — (1) *"que figure el estado"*: con la tabla desbordada, la columna anclada
       del botón se quedaba ENCIMA de Estado y lo tapaba. Se mide con elementFromPoint, que es lo
       único que prueba "no está tapado": mirar el rect no alcanza, porque el rect está igual
       aunque tenga otra celda encima. (2) el que volvió a A Programar ya armado. */
    const pArm = f.find((x) => /Volvio Armado/.test(x.rs));
    out.armadoDice = !!pArm && /Armado/.test(pArm.est);
    out.armadoTanda = !!pArm && /E12L/.test(pArm.tanda) && /vuelve/.test(pArm.tanda);
    const pNuevo = f.find((x) => /Web Nueva/.test(x.rs));
    out.nuevoSigueApr = !!pNuevo && /A programar/i.test(pNuevo.est) && pNuevo.tanda === "—";

    /* v18.35 (Luis: *"se sigue deformando la tabla"*) — el ancho de cada columna NO puede
       depender de lo que haya adentro. Se mide con todos los pedidos y con un filtro puesto
       (menos filas, textos más cortos): tienen que dar lo mismo. El control de no-trivialidad
       está abajo: con `table-layout:auto`, que era lo que había, los anchos SÍ cambian. */
    const anchos = () => [...box.querySelectorAll("table.pmod-tab thead th")]
      .map((e) => Math.round(e.getBoundingClientRect().width));
    const aTodos = anchos();
    pmodBuscar("Chen"); const aFiltrado = anchos(); pmodBuscar("");
    out.noSeDeforma = JSON.stringify(aTodos) === JSON.stringify(aFiltrado);
    out.anchos = JSON.stringify(aTodos);
    const tb = box.querySelector("table.pmod-tab");
    out.layoutFijo = getComputedStyle(tb).tableLayout === "fixed";
    tb.style.tableLayout = "auto";
    const aAuto1 = anchos();
    pmodBuscar("Chen"); const aAuto2 = anchos(); pmodBuscar("");
    box.querySelector("table.pmod-tab").style.tableLayout = "";
    out.controlAutoSeDeforma = JSON.stringify(aAuto1) !== JSON.stringify(aAuto2);

    const DOW = /(lun|mar|mié|jue|vie|sáb|dom)/i;
    const pProg = f.find((x) => x.tanda !== "—" && x.fProg !== "—");
    out.fPedSinDia = !!p1360 && /\d{1,2}\/\d{2}/.test(p1360.fPed) && !DOW.test(p1360.fPed);
    out.fProgConDia = !!pProg && DOW.test(pProg.fProg);
    const wrap = box.querySelector(".pmod-wrap");
    wrap.style.maxWidth = "420px";
    wrap.scrollLeft = 0;
    out.stickyDesborda = wrap.scrollWidth > wrap.clientWidth + 2;
    const bt = box.querySelector("tr.pmod-row .pmod-btn");
    const rb = bt.getBoundingClientRect(), rw = wrap.getBoundingClientRect();
    out.stickyVisible = rb.right <= rw.right + 1 && rb.left >= rw.left - 1 && rb.width > 10;
    out.stickyPos = getComputedStyle(bt.closest("td")).position;
    // el estado tiene que seguir VISIBLE y sin nada encima (elementFromPoint)
    const ch = box.querySelector("tr.pmod-row td.est .pmod-est");
    const rc = ch.getBoundingClientRect();
    out.estDentro = rc.right <= rw.right + 1 && rc.left >= rw.left - 1 && rc.width > 10;
    const enc = document.elementFromPoint(Math.round(rc.left + rc.width / 2), Math.round(rc.top + rc.height / 2));
    out.estDestapado = !!enc && (enc === ch || ch.contains(enc) || enc.closest("td.est") !== null);
    out.estTapadoPor = enc ? (enc.className || enc.tagName) : "(nada)";
    wrap.style.maxWidth = "";

    // ── (5) el contador: pedidos y NP por separado ─────────────────────────
    out.resumen = box.querySelector(".pmod-res").textContent.replace(/\s+/g, " ").trim();

    // ── (6) la búsqueda ────────────────────────────────────────────────────
    const buscar = function (q) { pmodBuscar(q); return filas(); };
    out.porPedido = buscar("1343").length === 1;   // el número ya no se muestra, pero se busca
    // ⚠ lo importante: buscar por una NP del MEDIO encuentra el pedido entero
    const porNp = buscar("LK 0005");
    out.porNpDelMedio = porNp.length === 1 && /Chen Li Yu/.test(porNp[0].rs) &&
                        /LK 0004/.test(porNp[0].nps) && /LK 0006/.test(porNp[0].nps);
    out.porCliente = buscar("torres").length === 1;
    out.porTanda = buscar("D67E").length === 2;
    out.porCod = buscar("2643").length === 1;
    out.sinCoincidencias = buscar("zzzz").length === 0 &&
      /Sin coincidencias/.test(box.textContent);
    pmodBuscar("");

    // ── (7) los filtros ────────────────────────────────────────────────────
    pmodFiltro("donde", "apr");   out.soloApr = filas().length === 3;
    pmodFiltro("donde", "plan");  out.soloPlan = filas().length === 5;
    pmodFiltro("donde", "todos");
    pmodFiltro("emp", "CH");      out.soloCh = filas().every((x) => /^CH /.test(x.cod));
    out.nCh = filas().length;
    pmodFiltro("emp", "todas");
    pmodFiltro("estado", "armado"); out.soloArmado = filas().length === 2 &&
      filas().some((x) => /Torres/.test(x.rs)) && filas().some((x) => /Volvio Armado/.test(x.rs));
    // se combinan: estado armado + empresa Chef no da nada
    pmodFiltro("emp", "CH");      out.combinados = filas().length === 0;
    pmodLimpiar();
    out.limpiarVuelve = filas().length === out.nFilas &&
      box.querySelector(".pmod-q").value === "";
    return out;
  });

  await b.close();
  const ok = [];
  const chk = (c, d) => ok.push([!!c, d]);
  chk(r.entreOcupYCuar, "la solapa quedó entre Ocupación y Config. Cuarentena: " + JSON.stringify(r.tabs));
  chk(r.partidoUnaFila, "un pedido partido en 3 NP es UN renglón, no tres ← el punto de Luis");
  chk(r.partidoTraeSusNps, "y trae sus tres NP: " + JSON.stringify(r.peds));
  chk(r.partidoDice3, "con el contador «3 NP» al lado");
  chk(r.columnas, "las columnas están en el orden que pidió Luis: " + JSON.stringify(r.columnas));
  chk(r.codConEmpresa, "el código del cliente aclara la empresa (LK 3843 / CH 2643)");
  chk(r.isisSeparadas, "dos NP de ISIS son dos pedidos distintos (su clave es la NP)");

  chk(r.salidaFuera, "un pedido que ya salió no aparece");
  chk(r.parcialQueda, "si salió UNA sola NP del pedido, el pedido queda con la que falta");
  chk(r.aprSinDiaNiTanda, "un pedido de A Programar no inventa día ni tanda: van en —");
  chk(r.aprConFechaPedido, "pero sí muestra la fecha del PEDIDO");
  chk(r.aprEstan, "los de A Programar también están");
  chk(r.aprSinNpTodavia, "y se ve que todavía no tienen NP asignada");
  /* NP REALES, no bloques: los dos pedidos de A Programar todavía no tienen NP (se asigna al
     programarlos), así que van aparte. Contar sus bloques como NP decía 10 cuando existen 7. */
  chk(/8 pedidos/.test(r.resumen) && /7 NP/.test(r.resumen) && /4 bloques sin NP/.test(r.resumen),
      "el contador separa pedidos, NP reales y bloques sin NP: " + JSON.stringify(r.resumen));
  chk(r.porPedido, "la búsqueda encuentra por número de pedido");
  chk(r.porNpDelMedio, "y por CUALQUIERA de sus NP — buscando la del medio sale el pedido entero");
  chk(r.porCliente, "por cliente");
  chk(r.porTanda, "por tanda");
  chk(r.porCod, "y por código de cliente");
  chk(r.sinCoincidencias, "sin coincidencias lo dice, no deja la tabla vacía y muda");
  chk(r.soloApr, "el filtro «Sólo A Programar» deja 3");
  chk(r.soloPlan, "«Sólo programados» deja 5");
  chk(r.soloCh && r.nCh === 2, "el filtro por empresa deja sólo los de Chef (" + r.nCh + ")");
  chk(r.soloArmado, "el filtro por estado deja los dos armados (el programado y el que volvió a A Programar)");
  chk(r.combinados, "los filtros se combinan (armado + Chef = ninguno)");
  chk(r.limpiarVuelve, "«Limpiar» devuelve todo y vacía la búsqueda");
  chk(r.botonEnCadaFila, "cada fila tiene su botón «Modificar» a la derecha de todo");
  chk(r.isisAbre, "una NP de ISIS abre el modal ← lo que pidió Luis");
  chk(r.isisItems.length === 2 && /034/.test(r.isisItems[0]),
      "con los renglones que trae Gestión, no LK: " + JSON.stringify(r.isisItems));
  chk(r.isisDirLibre, "y la dirección como campos libres (ISIS no tiene libreta de direcciones)");
  chk(r.isisAvisaPisa, "avisando que se PISA lo que muestra la PPP y que va a salir con ✏ MOD en Facturación");
  chk(/"p_np":"98701"/.test(r.isisGuardo) && /"cajas":9/.test(r.isisGuardo) &&
      /Siempreviva/.test(r.isisGuardo) && /Mariana/.test(r.isisGuardo),
      "y guarda por la RPC de ISIS con NP, cajas, dirección y quién: " + r.isisGuardo);
  chk(r.isisNoFueALk, "sin tocar la RPC de LK ← son dos caminos distintos");
  chk(r.isisDiceM3, "y la pantalla cuenta cómo quedó el m³ recalculado: " + JSON.stringify(r.isisStatus));
  chk(r.chefAbre, "un pedido de Chef también abre el modal (v18.45)");
  chk(/"p_empresa":"chef"/.test(r.chefPidio), "y pide el contexto con empresa=chef: " + r.chefPidio);
  chk(r.chefItems.length === 1 && /769L/.test(r.chefItems[0]),
      "con sus renglones, incluido el artículo de Loeke con L al final: " + JSON.stringify(r.chefItems));
  chk(r.chefCatalogo, "usa el catálogo que viene DENTRO del contexto, no el de LK");
  chk(/"p_empresa":"chef"/.test(r.chefGuardo) && /"cajas":12/.test(r.chefGuardo) && /Mariana/.test(r.chefGuardo),
      "y guarda con empresa=chef, las cajas nuevas y quién: " + r.chefGuardo);
  chk(r.abre, "un pedido web de LK abre el modal");
  chk(/"p_order_id":1343/.test(r.ctxPidio), "y pide el contexto del pedido correcto: " + r.ctxPidio);
  chk(/Chen Li Yu/.test(r.modalTitulo) && /LK 0004/.test(r.modalTitulo),
      "el modal dice de quién es y qué NP toca: " + JSON.stringify(r.modalTitulo));
  chk(r.modalItems.length === 2 && /027/.test(r.modalItems[0]), "muestra el contenido del pedido: " + JSON.stringify(r.modalItems));
  chk(r.modalDirs.some((x) => /Depósito Lanús/.test(x)) && r.modalDirs.some((x) => /Dirección nueva/.test(x)),
      "y las direcciones que el cliente ya tiene, más la opción de crear una: " + JSON.stringify(r.modalDirs));
  chk(r.modalSinStock, "marca el código que hoy está sin stock (agregarlo deja el pedido diferido)");
  chk(r.guardarApagado, "sin ningún cambio, «Guardar» está apagado");
  chk(r.filasDespues === 3, "agregar un código suma su renglón (" + r.filasDespues + ")");
  chk(r.guardarPrendido, "con cambios, «Guardar» se prende");
  chk(/\{"cod_art":"027","cajas":5,"uxb":24\}/.test(r.guardo) && /\{"cod_art":"601","cajas":4,"uxb":6\}/.test(r.guardo),
      "y lo que se manda al backend son las cajas nuevas y el código agregado: " + r.guardo);
  chk(/"cod_art":"027","cajas":2/.test(r.guardoEspera),
      "va también la foto de cómo estaba el pedido, para que el backend corte si cambió por otro lado");
  chk(/Mariana/.test(r.personas) && /Agregar nombre/.test(r.personas),
      "el desplegable trae los nombres de la tabla y la opción de agregar uno");
  chk(r.sinQuien, "con cambios pero sin elegir quién, «Guardar» sigue apagado y dice qué falta");
  chk(r.sinMotivo, "y sin justificativo tampoco deja guardar ← lo que pidió Luis");
  chk(/"p_nombre":"Luis"/.test(r.personaNueva), "«Agregar nombre…» lo manda a la tabla de Gestión: " + r.personaNueva);
  chk(r.quedoElegido, "y el nombre recién agregado queda elegido");
  chk(r.guardoQuien === "Mariana", "lo que se guarda es el NOMBRE de quien modificó (" + r.guardoQuien + ")");
  chk(/sumar cajas/.test(r.guardoMotivo || ""), "con su justificativo: " + JSON.stringify(r.guardoMotivo));
  chk(/LK 0004/.test(r.guardoNps) && /LK 0006/.test(r.guardoNps),
      "y las NP del pedido, que son las que Facturación va a marcar como modificadas: " + r.guardoNps);
  chk(r.cerroAlGuardar, "al guardar bien, el modal se cierra");
  chk(r.fPedSinDia, "«Pedido del» va sin el día de la semana (Luis)");
  chk(r.fProgConDia, "pero «En programación» lo conserva: ahí sirve para saber cuándo sale");
  chk(r.stickyDesborda, "control: con el wrap angosto la tabla DESBORDA (si no, lo de abajo pasa solo)");
  chk(r.armadoDice, "un pedido que volvió a A Programar YA ARMADO lo dice en Estado ← lo que pidió Luis");
  chk(r.armadoTanda, "y la columna Tanda muestra a cuál vuelve (no se pickea de nuevo)");
  chk(r.nuevoSigueApr, "control: el que nunca se programó sigue en «A programar», sin tanda");
  chk(r.layoutFijo, "la tabla tiene el ancho de columnas FIJO, no por contenido");
  chk(r.noSeDeforma, "y no se deforma al filtrar: mismas columnas con todos y con uno solo (" + r.anchos + ")");
  chk(r.controlAutoSeDeforma, "control: con el `table-layout:auto` de antes, las columnas SÍ se movían");
  chk(r.estDentro, "con la tabla desbordada, la columna Estado sigue a la vista");
  chk(r.estDestapado, "y NADA se le pone encima — lo que tapaba era la columna anclada del botón (encima: " + r.estTapadoPor + ")");
  chk(r.stickyVisible && r.stickyPos === "sticky",
      "y aun desbordada el botón «Modificar» sigue a la vista, anclado a la derecha (" + r.stickyPos + ")");
  chk(errs.length === 0, "sin errores de JS: " + JSON.stringify(errs));

  let malas = 0;
  for (const [bien, d] of ok) { console.log((bien ? "  ok   " : "  FALLA") + " " + d); if (!bien) malas++; }
  console.log(malas ? "\n✗ " + malas + " de " + ok.length + " fallaron" : "\n✓ " + ok.length + " chequeos ok");
  process.exit(malas ? 1 : 0);
})();
