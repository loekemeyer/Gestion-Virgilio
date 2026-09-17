/* v19.32 (Luis, 2026-09-17) — «📅 CAMBIAR DE DÍA» POR PEDIDO, Y ELEGIR LA TANDA DESTINO.

   Pedido textual: *"quiero que cada nota de pedido tenga el botón cambiar de día. Quiero que
   cuando se cambia de día una nota de pedido, si hay más notas de pedido que se corresponden a un
   mismo pedido de ese cliente, que se muevan todas en conjunto… y que cuando se mueven a un día,
   se dé la opción de crear una tanda nueva para esos pedidos o agregarlos a una tanda que ya
   existe ese día"*.

   Lo que se cuida acá:
     · La unidad es el PEDIDO, no la NP. Un pedido web se parte en bloques (18/15 renglones) y cada
       bloque es una NP: mover una sola dejaría al mismo cliente en dos días, que es justo lo que
       prohíbe la regla de Thomas. Quién es el pedido lo resuelve el BACKEND
       (`gv_ppp_web_desprogramar_previo`), igual que en «↩ Enviar a programar».
     · El día ya no mueve nada: abre el paso 2. La tanda destino se elige, y las que no se pueden
       se ven apagadas CON el motivo (regla de estados de Luis: armado con armado, facturado con
       facturado; lo que se está pickeando ahora, sólo tanda nueva).
     · Los avisos de súper mezclado y de camión distinto se muestran y NO bloquean (Luis:
       *"de momento advertir sin bloquear"*).
   Estado inyectado; no pega contra la red. Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");

const fallas = [];
if (!src.includes("function pgaNpMoverAbrir")) fallas.push("falta pgaNpMoverAbrir (el botón de la fila de la NP)");
if (!src.includes("gv_ppp_pedido_mover")) fallas.push("el front no llama a la RPC gv_ppp_pedido_mover");
if (!src.includes("gv_ppp_tandas_del_dia")) fallas.push("el front no pide las tandas del día destino");
if (!src.includes("function pppMovPaso2")) fallas.push("falta el paso 2 del pop-up");
if (!fs.existsSync(path.join(__dirname, "..", "sql", "gv_ppp_mover_pedido_v1932.sql"))) {
  fallas.push("falta sql/gv_ppp_mover_pedido_v1932.sql (la definición va en el repo)");
}
if (fallas.length) {
  console.log("ppp-pedido-cambiar-dia: ✗ FAIL\n  - " + fallas.join("\n  - "));
  process.exit(1);
}

let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.log("ppp-pedido-cambiar-dia: estático ✓ OK (sin Playwright)"); process.exit(0); }
}

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 1000 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {}, rpc = [], confirms = [];
    window.__isSupervisor = true;
    window.confirm = function (t) { confirms.push(String(t || "")); return true; };
    window.alert = function () {};
    window.getTodayKey = () => "2026-09-16";
    window.pppSetStatus = function () {};
    window.pppLoadProgFromSupabase = async function () {};
    window._faltMiLegajo = () => "52";
    let recargas = 0;
    window.pgaNeed = function () {}; window.patrNeed = function () {};
    window.pgaRecargar = function () { recargas++; };
    window._pppPlanAgrupar = function () { return { venc: [], byDay: new Map() }; };
    window.pppPaintTabs = function () {};
    _pppParsed = { prog: [{ np: "98630", tanda: "D99Z", fecha_entrega: "2026-09-20", m3: 1.8,
                            cod: "1", razon_social: "Otra", zona: "Zona 2", programmed: true }] };

    window.aprRpc = async function (fn, args) {
      rpc.push({ fn: fn, args: args });
      if (fn === "gv_ppp_web_desprogramar_previo") {
        return { es_isis: false, empresa: "lk", order_id: 1345, cod: "2118", cliente: "Emilio Martinez",
                 n: 2, nps: [{ np_label: "LK 0009", tanda: "E01B", m3: 0.1, estado: "armado" },
                              { np_label: "LK 0010", tanda: "E01B", m3: 0.108, estado: "armado" }] };
      }
      if (fn === "gv_ppp_web_calendario") {
        return [{ dia: "2026-09-17", m3: 1, cupo: 6, habil: true, tandas: 1 },
                { dia: "2026-09-18", m3: 0, cupo: 6, habil: true, tandas: 0 }];
      }
      if (fn === "gv_ppp_tandas_del_dia") {
        return [{ tanda: "E20A", m3: 1.1, nps: 3, clientes: 2, estado: "armado", orden: 3,
                  zonas: "Zona 2", camiones: "Capital", es_super: false, compatible: true, motivo: null,
                  aviso: "Esa tanda va en el camion GBA Oeste y lo que moves es de Capital: no viajan juntos." },
                { tanda: "E20B", m3: 0.2, nps: 1, clientes: 1, estado: "pendiente", orden: 1,
                  zonas: "Zona 1", camiones: "Capital", es_super: false, compatible: false,
                  motivo: "Esa tanda esta pendiente y lo que moves esta armado. Solo se juntan tandas en el mismo estado.",
                  aviso: null }];
      }
      if (fn === "gv_ppp_pedido_mover") {
        return [{ movidas: 2, nps: ["LK 0009", "LK 0010"], tanda: args.p_tanda || "E12D",
                  fecha: args.p_fecha, estado: "armado", nueva: !args.p_tanda, aviso: null }];
      }
      return [];
    };

    const mk = (fecha, tanda, np, est, m3) => ({ fecha: fecha, tanda: tanda, np: np, np_num: 9,
      cod: "2118", razon_social: "Emilio Martinez", localidad: "CABA", zona: "Zona 2",
      zona_corta: "Zona 2", empresa: "LK", origen: "web", m3: m3, estado: est, estado_orden: 3,
      barrio: "Villa Crespo", fecha_pedido: "2026-09-11", clave: "1345" });
    _pgaRows = [mk("2026-09-17", "E01B", "LK 0009", "armado", 0.1),
                mk("2026-09-17", "E01B", "LK 0010", "armado", 0.108),
                mk("2026-09-17", "E01B", "LK 0012", "armado", 0.13)];
    _pgaTs = Date.now(); _patrRows = []; _patrTs = Date.now();

    const esperar = async function (fn, ms) {
      const t0 = Date.now();
      while (Date.now() - t0 < (ms || 4000)) { if (fn()) return true; await new Promise((res) => setTimeout(res, 40)); }
      return false;
    };

    _pppTab = "plan"; _pppPlanTabla = true; _pppPlanClasica = false; _pppPlanDay = null;
    document.getElementById("pppOverlay").classList.add("show");
    pppRenderProg();
    await esperar(() => !!document.querySelector("#pppPreview table.pga"));
    pgaAbrirDia("20260917"); pgaAbrirTanda("20260917|E01B");
    out.hayNp = await esperar(() => [...document.querySelectorAll("#pppPreview tr.pga-n")]
      .some((x) => x.textContent.indexOf("LK 0009") >= 0));

    // (a) la fila de la NP trae el botón 📅, aparte del ↩
    const fila = [...document.querySelectorAll("#pppPreview tr.pga-n")].find((x) => x.textContent.indexOf("LK 0009") >= 0);
    const bt = fila && fila.querySelector(".pga-acc-b.dia");
    out.hayBoton = !!bt;
    out.texto = bt ? bt.textContent.trim() : "";
    out.tooltip = bt ? (bt.getAttribute("title") || "") : "";
    out.tooltipDicePedido = /ESTE PEDIDO/.test(out.tooltip);
    out.tambienElRetorno = !!(fila && fila.querySelector(".pga-acc-b:not(.dia)"));
    if (!bt) return out;

    // (b) abre el pop-up del PEDIDO: pregunta cuáles son sus NP y lo dice
    bt.click();
    await esperar(() => document.getElementById("pppMovOverlay") &&
                        document.getElementById("pppMovOverlay").classList.contains("show"));
    out.pidioPrevio = rpc.some((x) => x.fn === "gv_ppp_web_desprogramar_previo");
    out.titulo = (document.getElementById("pppMovTitle") || {}).textContent || "";
    await esperar(() => (document.querySelectorAll("#pppMovBody .mv-d") || []).length > 0);

    // (c) elegir el día abre el paso 2 y NO mueve nada
    rpc.length = 0; confirms.length = 0;
    const d18 = [...document.querySelectorAll("#pppMovBody .mv-d")].find((x) => x.textContent.indexOf("18") >= 0);
    d18.click();
    await esperar(() => !!document.querySelector("#pppMovBody .mv-esp-b.nueva"));
    out.paso2 = !!document.querySelector("#pppMovBody .mv-esp-b.nueva");
    out.noMovioTodavia = !rpc.some((x) => x.fn === "gv_ppp_pedido_mover");
    out.sub = (document.querySelector("#pppMovBody .mv-sub") || {}).textContent || "";
    out.diceLasDosNps = /LK 0009/.test(out.sub) && /LK 0010/.test(out.sub);
    const dests = [...document.querySelectorAll("#pppMovBody .mv-dest")];
    out.destOk = dests.some((x) => /E20A/.test(x.textContent) && !x.disabled);
    out.destNo = dests.some((x) => /E20B/.test(x.textContent) && x.disabled);
    out.avisoRojo = !!document.querySelector("#pppMovBody .mv-dest-av");

    // (d) elegir una tanda EXISTENTE mueve el pedido entero a esa tanda
    dests.find((x) => /E20A/.test(x.textContent)).click();
    await esperar(() => rpc.some((x) => x.fn === "gv_ppp_pedido_mover"));
    const arg = (rpc.find((x) => x.fn === "gv_ppp_pedido_mover") || {}).args || {};
    out.arg = JSON.stringify({ np: arg.p_np, f: arg.p_fecha, t: arg.p_tanda });
    out.confirmDiceJuntas = confirms.join(" ").indexOf("NP del pedido juntas") >= 0;
    out.confirmAvisaFuerte = confirms.join(" ").indexOf("OJO") >= 0;
    out.recargo = await esperar(() => recargas > 0);
    out.cerro = !document.getElementById("pppMovOverlay").classList.contains("show");
    return out;
  });

  const mal = [];
  const t = (c, m) => { if (!c) mal.push(m); };
  t(errs.length === 0, "errores de página: " + errs.join(" | "));
  t(r.hayNp, "no se dibujó la fila de la NP");
  t(r.hayBoton, "la fila de la NP no tiene el botón 📅");
  t(r.texto === "📅", "el botón no es sólo el ícono — «" + r.texto + "»");
  t(r.tooltipDicePedido, "el tooltip no aclara que mueve el PEDIDO entero");
  t(r.tambienElRetorno, "se perdió el botón ↩ Enviar a programar de la fila");
  t(r.pidioPrevio, "no le pregunta al backend cuáles son las NP del pedido");
  t(/Emilio Martinez/.test(r.titulo), "el pop-up no dice de quién es el pedido — «" + r.titulo + "»");
  t(r.paso2, "elegir el día no abre el paso 2 («¿en qué tanda?»)");
  t(r.noMovioTodavia, "movió el pedido con sólo tocar el día, sin preguntar la tanda");
  t(r.diceLasDosNps, "el paso 2 no dice qué NP se llevan juntas — «" + r.sub + "»");
  t(r.destOk, "la tanda compatible no se puede elegir");
  t(r.destNo, "la tanda incompatible se puede elegir igual (la regla de estados no se ve)");
  t(r.avisoRojo, "no se ve el aviso de súper / camión distinto");
  t(r.arg === JSON.stringify({ np: "LK 0009", f: "2026-09-18", t: "E20A" }),
    "no llamó a gv_ppp_pedido_mover con el pedido, el día y la tanda — " + r.arg);
  t(r.confirmDiceJuntas, "el confirm no avisa que se mueven todas las NP del pedido juntas");
  t(r.confirmAvisaFuerte, "el aviso de mezcla no aparece en el confirm");
  t(r.recargo, "no recarga el árbol después de mover");
  t(r.cerro, "no cierra el pop-up");

  await b.close();
  if (mal.length) { console.log("ppp-pedido-cambiar-dia: ✗ FAIL\n  - " + mal.join("\n  - ")); process.exit(1); }
  console.log("ppp-pedido-cambiar-dia: ✓ OK (mueve el PEDIDO entero y pregunta a qué tanda)");
})();
