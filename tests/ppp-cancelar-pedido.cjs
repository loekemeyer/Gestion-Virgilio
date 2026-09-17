/* v19.34 (Luis, 2026-09-17) — «✕ CANCELAR PEDIDO» EN LA FILA DE LA NP.

   Pedido textual: *"Quiero agregar un boton junto al de cambiar fecha para NPs que sea «Cancelar
   pedido». Se puede hacer con cualquier pedido en cualquier estado. Se borra el pedido de la
   programacion y la mercadería que tenía (si es que tenía) vuelve a A guardar (que pida
   confirmacion y que ahi avise si tiene mercadería que va a volver a «A guardar» y que diga el
   detalle). Si se «Cancela pedido» a una NP que es parte de un pedido distribuido en muchas NPs,
   tiene que preguntar si se quieren cancelar todas las NPs de ese pedido o solo esa."*

   Lo que se cuida acá:
     · El botón está en la fila de la NP, al lado del 📅 y del ↩, y no se los come.
     · Antes de tocar nada le pregunta al backend QUÉ se lleva puesto
       (`gv_ppp_np_cancelar_previo`): nunca se cancela a ciegas.
     · Con un pedido de varias NP, lo PRIMERO que pregunta es el alcance. Y si se elige «sólo
       ésta», el confirm lo dice y la RPC va con `p_todas: false`.
     · La confirmación muestra el DETALLE de lo que vuelve a «A guardar», artículo por artículo.
     · Un pedido que YA SALIÓ no se bloquea (Luis: "en cualquier estado") pero avisa fuerte y
       manda `p_forzar: true` — el backend lo deja escrito en el log.
     · Una NP sin mercadería movida lo dice, en vez de mostrar una lista vacía.
   Estado inyectado; no pega contra la red. Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");

const fallas = [];
if (!src.includes("function pgaCanRender")) fallas.push("falta el módulo del pop-up (pgaCanRender)");
if (!src.includes("gv_ppp_pedido_cancelar")) fallas.push("el front no llama a la RPC gv_ppp_pedido_cancelar");
if (!src.includes("gv_ppp_np_cancelar_previo")) fallas.push("el front no pide el previo antes de cancelar");
if (!src.includes(".pga-acc-b.cancel")) fallas.push("falta el CSS del botón ✕");
if (!fs.existsSync(path.join(__dirname, "..", "sql", "gv_ppp_cancelar_pedido_v1934.sql"))) {
  fallas.push("falta sql/gv_ppp_cancelar_pedido_v1934.sql (la definición va en el repo)");
}
if (fallas.length) {
  console.log("ppp-cancelar-pedido: ✗ FAIL\n  - " + fallas.join("\n  - "));
  process.exit(1);
}

let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.log("ppp-cancelar-pedido: estático ✓ OK (sin Playwright)"); process.exit(0); }
}

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 1000 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {}, rpc = [];
    window.__isSupervisor = true;
    window.alert = function () {};
    window.confirm = function () { return true; };
    window.getTodayKey = () => "2026-09-16";
    let estado = "";
    window.pppSetStatus = function (t) { estado = String(t || ""); };
    window.pppLoadProgFromSupabase = async function () {};
    window._faltMiLegajo = () => "52";
    window.aprQuien = async function () { return "luis@x"; };
    let recargas = 0;
    window.pgaNeed = function () {}; window.patrNeed = function () {};
    window.pgaRecargar = function () { recargas++; };
    window._pppPlanAgrupar = function () { return { venc: [], byDay: new Map() }; };
    window.pppPaintTabs = function () {};
    _pppParsed = { prog: [{ np: "98630", tanda: "D99Z", fecha_entrega: "2026-09-20", m3: 1.8,
                            cod: "1", razon_social: "Otra", zona: "Zona 2", programmed: true }] };

    // El pedido de prueba: 2 NP web del mismo pedido, las dos armadas. La primera tiene
    // mercadería (2 artículos, 60 cajas) y YA SALIÓ; la segunda no movió nada.
    const PREV = {
      existe: true, es_isis: false, empresa: "lk", order_id: 1345, np: "LK 0009",
      tanda: "E01B", cod: "2118", razon_social: "Emilio Martinez", fecha: "2026-09-17",
      estado: "armado", salio: true, entregado: false, volvio: false, n_nps: 2,
      dev_np: { arts: 2, cajas: 60, items: [{ art: "501", cajas: 40 }, { art: "509", cajas: 20 }] },
      dev_todas: { arts: 2, cajas: 60 },
      nps: [
        { np: "LK 0009", tanda: "E01B", fecha: "2026-09-17", m3: 0.1, estado: "armado",
          salio: true, entregado: false, volvio: false, arts: 2, cajas: 60,
          items: [{ art: "501", cajas: 40 }, { art: "509", cajas: 20 }] },
        { np: "LK 0010", tanda: "E01B", fecha: "2026-09-17", m3: 0.108, estado: "armado",
          salio: false, entregado: false, volvio: false, arts: 0, cajas: 0, items: [] }
      ]
    };
    window.aprRpc = async function (fn, args) {
      rpc.push({ fn: fn, args: args });
      if (fn === "gv_ppp_np_cancelar_previo") return PREV;
      if (fn === "gv_ppp_pedido_cancelar") {
        return [{ np: args.p_np, tanda: "E01B", arts: 2, cajas: 60, detalle: "60 cajas a A guardar" }];
      }
      return [];
    };

    const mk = (np, est, m3) => ({ fecha: "2026-09-17", tanda: "E01B", np: np, np_num: 9,
      cod: "2118", razon_social: "Emilio Martinez", localidad: "CABA", zona: "Zona 2",
      zona_corta: "Zona 2", empresa: "LK", origen: "web", m3: m3, estado: est, estado_orden: 3,
      barrio: "Villa Crespo", fecha_pedido: "2026-09-11", clave: "1345" });
    _pgaRows = [mk("LK 0009", "armado", 0.1), mk("LK 0010", "armado", 0.108)];
    _pgaTs = Date.now(); _patrRows = []; _patrTs = Date.now();

    const esperar = async function (fn, ms) {
      const t0 = Date.now();
      while (Date.now() - t0 < (ms || 4000)) { if (fn()) return true; await new Promise((res) => setTimeout(res, 40)); }
      return false;
    };
    const cuerpo = () => (document.getElementById("pgaCanBody") || {}).innerHTML || "";

    _pppTab = "plan"; _pppPlanTabla = true; _pppPlanClasica = false; _pppPlanDay = null;
    document.getElementById("pppOverlay").classList.add("show");
    pppRenderProg();
    await esperar(() => !!document.querySelector("#pppPreview table.pga"));
    pgaAbrirDia("20260917"); pgaAbrirTanda("20260917|E01B");
    out.hayNp = await esperar(() => [...document.querySelectorAll("#pppPreview tr.pga-n")]
      .some((x) => x.textContent.indexOf("LK 0009") >= 0));

    // (a) el botón está en la fila, junto a los otros dos
    const fila = [...document.querySelectorAll("#pppPreview tr.pga-n")].find((x) => x.textContent.indexOf("LK 0009") >= 0);
    const bt = fila && fila.querySelector(".pga-acc-b.cancel");
    out.hayBoton = !!bt;
    out.texto = bt ? bt.textContent.trim() : "";
    out.tooltip = bt ? (bt.getAttribute("title") || "") : "";
    out.tooltipDiceAGuardar = /A guardar/.test(out.tooltip);
    out.siguenLosOtros = !!(fila && fila.querySelector(".pga-acc-b.dia") &&
                            fila.querySelector(".pga-acc-b:not(.dia):not(.cancel)"));
    if (!bt) return out;

    // (b) abrirlo pide el previo y arranca preguntando EL ALCANCE (son 2 NP)
    bt.click();
    out.abrio = await esperar(() => document.getElementById("pgaCanOv") &&
                                    document.getElementById("pgaCanOv").classList.contains("show"));
    out.pidioPrevio = rpc.some((x) => x.fn === "gv_ppp_np_cancelar_previo");
    out.noCancelóTodavia = !rpc.some((x) => x.fn === "gv_ppp_pedido_cancelar");
    await esperar(() => /notas de pedido/.test(cuerpo()));
    out.preguntaAlcance = /notas de pedido/.test(cuerpo()) &&
                          /Sólo la NP LK 0009/.test(cuerpo()) && /Las 2 NP del pedido/.test(cuerpo());

    // (c) «sólo ésta» → motivo (obligatorio) → confirmación
    [...document.querySelectorAll("#pgaCanBody .can-op")].find((x) => /Sólo la NP/.test(x.textContent)).click();
    await esperar(() => /Por qué se cancela/.test(cuerpo()));
    out.preguntaMotivo = /Falta stock/.test(cuerpo()) && /Otro/.test(cuerpo());
    // sin motivo elegido no deja seguir
    out.seguirApagado = !!document.querySelector("#pgaCanBody .can-b.go[disabled]");
    [...document.querySelectorAll("#pgaCanBody .can-op")].find((x) => /Falta stock/.test(x.textContent)).click();
    await esperar(() => !document.querySelector("#pgaCanBody .can-b.go[disabled]"));
    document.querySelector("#pgaCanBody .can-b.go").click();
    await esperar(() => /A guardar/.test(cuerpo()));

    // (d) la confirmación dice QUÉ vuelve, artículo por artículo
    out.diceCajas = /60 caja/.test(cuerpo());
    out.diceDetalle = /501 × 40/.test(cuerpo()) && /509 × 20/.test(cuerpo());
    out.diceQueLasOtrasNo = /NO<\/b> se tocan/.test(cuerpo()) || /no se tocan/i.test(cuerpo());
    // (e) y avisa fuerte porque ya salió
    out.alertaSalio = !!document.querySelector("#pgaCanBody .can-alerta") && /YA SALIÓ/.test(cuerpo());
    out.botonDiceIgual = /cancelar IGUAL/i.test((document.getElementById("pgaCanGo") || {}).textContent || "");

    // (f) confirmar: la RPC va con el alcance y el forzado que corresponden
    document.getElementById("pgaCanGo").click();
    await esperar(() => rpc.some((x) => x.fn === "gv_ppp_pedido_cancelar"));
    const a = (rpc.find((x) => x.fn === "gv_ppp_pedido_cancelar") || {}).args || {};
    out.arg = JSON.stringify({ np: a.p_np, m: a.p_motivo, todas: a.p_todas, forzar: a.p_forzar });
    out.recargo = await esperar(() => recargas > 0);
    out.cerro = !document.getElementById("pgaCanOv").classList.contains("show");
    out.aviso = estado;

    // (g) la NP SIN mercadería lo dice, en vez de una lista vacía
    PREV.np = "LK 0010"; PREV.salio = false; PREV.n_nps = 1;
    PREV.dev_np = { arts: 0, cajas: 0, items: [] };
    PREV.nps = [PREV.nps[1]];
    await pgaCanAbrir("LK 0010");
    await esperar(() => /Por qué se cancela/.test(cuerpo()));
    out.unaSolaNpSaltaAlcance = /Por qué se cancela/.test(cuerpo());   // 1 NP → no pregunta alcance
    [...document.querySelectorAll("#pgaCanBody .can-op")].find((x) => /Falta stock/.test(x.textContent)).click();
    await esperar(() => !document.querySelector("#pgaCanBody .can-b.go[disabled]"));
    document.querySelector("#pgaCanBody .can-b.go").click();
    await esperar(() => /mercader/.test(cuerpo()));
    out.sinMercaderia = /No hay mercadería movida/.test(cuerpo());
    out.sinAlerta = !document.querySelector("#pgaCanBody .can-alerta");
    pgaCanCerrar();
    return out;
  });

  const mal = [];
  const t = (c, m) => { if (!c) mal.push(m); };
  t(errs.length === 0, "errores de página: " + errs.join(" | "));
  t(r.hayNp, "no se dibujó la fila de la NP");
  t(r.hayBoton, "la fila de la NP no tiene el botón ✕ de cancelar");
  t(r.texto === "✕", "el botón no es sólo el ícono — «" + r.texto + "»");
  t(r.tooltipDiceAGuardar, "el tooltip no dice que la mercadería vuelve a «A guardar»");
  t(r.siguenLosOtros, "se comió el 📅 o el ↩ de la fila");
  t(r.abrio, "no abre el pop-up");
  t(r.pidioPrevio, "no le pregunta al backend qué se lleva puesto (gv_ppp_np_cancelar_previo)");
  t(r.noCancelóTodavia, "canceló con sólo tocar el botón, sin confirmar");
  t(r.preguntaAlcance, "con 2 NP no pregunta si se cancelan todas o sólo ésta");
  t(r.preguntaMotivo, "no pide el motivo (falta stock / otro)");
  t(r.seguirApagado, "deja seguir sin elegir motivo");
  t(r.diceCajas, "la confirmación no dice cuántas cajas vuelven");
  t(r.diceDetalle, "la confirmación no muestra el detalle artículo por artículo");
  t(r.diceQueLasOtrasNo, "no aclara que las otras NP del pedido no se tocan");
  t(r.alertaSalio, "no avisa fuerte que el pedido YA SALIÓ");
  t(r.botonDiceIgual, "el botón no avisa que se cancela IGUAL algo que salió");
  t(r.arg === JSON.stringify({ np: "LK 0009", m: "falta stock", todas: false, forzar: true }),
    "no llamó a gv_ppp_pedido_cancelar con el alcance y el forzado que corresponden — " + r.arg);
  t(r.recargo, "no recarga el árbol después de cancelar");
  t(r.cerro, "no cierra el pop-up");
  t(/A guardar/.test(r.aviso || ""), "el aviso final no dice cuánto volvió a «A guardar» — «" + r.aviso + "»");
  t(r.unaSolaNpSaltaAlcance, "con una sola NP igual pregunta el alcance");
  t(r.sinMercaderia, "una NP sin mercadería no lo dice");
  t(r.sinAlerta, "muestra la alerta de «ya salió» en una NP que no salió");

  await b.close();
  if (mal.length) { console.log("ppp-cancelar-pedido: ✗ FAIL\n  - " + mal.join("\n  - ")); process.exit(1); }
  console.log("ppp-cancelar-pedido: ✓ OK (cancela con detalle, alcance y aviso de lo que ya salió)");
})();
