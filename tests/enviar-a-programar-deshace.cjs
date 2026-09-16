/* Regresión v18.77 — «Enviar a programar» DESHACE lo armado, y el botón de desarmar ya no está.

   Pedido de Luis (16/09), textual: *"Que cuando se apriete «Enviar a programar» a una NP, mande
   todas las NPs correspondientes a ese pedido … si tenían algo armado, se «deshace» = la
   mercadería vuelve a las bodegas de donde salió y las NPs vuelven «a programar» marcadas para
   que el cron no las programe automáticamente"* y *"el botón de desarmar pedido sacalo"*.

   Lo que había:
     · «Enviar a programar» sacaba la tanda y retenía, pero NO tocaba el stock — el cartel decía
       textualmente "Las cajas ya pickeadas no se mueven de dónde están", así que la mercadería
       de un pedido a medio armar quedaba parada en a_facturar / separar_pedidos sin dueño;
     · y al lado vivía el 🗑 «Desarmar pedido», que sí devolvía el stock pero además mataba el
       pedido. Dos botones para dos mitades de la misma acción.
   Ahora hay UNO: enviar a programar deshace y devuelve.

   Lo de «todas las NP del pedido» NO es nuevo (el backend resuelve el `order_id` desde la v18.40);
   lo que se chequea acá es que el camino nuevo no lo pierda.

   Chequea:
     1) que el botón 🗑 y todo su modal hayan desaparecido del front;
     2) que los dos caminos (web e ISIS) llamen a `gv_ppp_pedido_a_programar`, y ninguno a las
        RPC viejas que no devolvían stock;
     3) que el pop-up ya no prometa que las cajas no se mueven, y diga que vuelven a A guardar
        (v18.91: NO a gondola/excedente — eso fue la v18.80, que duro un dia);
     4) en vivo: que el botón ↩ siga estando y dispare el camino nuevo con la NP tocada.
   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");

const fallas = [];

// ---- 1) el desarme se fue entero ----
for (const resto of ["dsmAbrir", "dsmConfirmar", "dsmModal", "Desarmar pedido"]) {
  if (src.includes(resto)) fallas.push("quedó `" + resto + "` en el front: el botón de desarmar tenía que salir entero");
}
if (/pga-acc-b del/.test(src)) fallas.push("quedó el botón 🗑 (.pga-acc-b.del) en la fila de la NP");

// ---- 2) las RPC ----
if (!src.includes("gv_ppp_pedido_a_programar")) {
  fallas.push("no se llama a gv_ppp_pedido_a_programar");
}
for (const vieja of ["gv_ppp_web_desprogramar\"", "gv_ppp_isis_desprogramar\""]) {
  if (src.includes('aprRpc("' + vieja)) {
    fallas.push("todavía se llama a " + vieja.replace('"', "") + " — ésa saca la tanda pero NO devuelve el stock");
  }
}
// el "previo" del pop-up SÍ tiene que seguir: es el que dice qué NP se lleva
if (!src.includes("gv_ppp_web_desprogramar_previo")) {
  fallas.push("se perdió gv_ppp_web_desprogramar_previo: es el que arma la lista de NP del pop-up");
}

// ---- 2 bis) el chip de A Programar no puede mentir sobre el automático ----
/* v18.77 (Luis): "sigue saliendo el badge de «se arma solo» a los pedidos que deberían tener la
   excepción". Un pedido RETENIDO no lo toca `gv_ppp_web_armar_pendientes`, pero el chip decía
   "🤖 se arma solo → mar 22/9 · en minutos", con fecha y todo. Quien lo decide es el backend
   (`gv_ppp_web_dia_salida`, motivo 'retenido'), y para eso necesita saber DE QUÉ PEDIDO se trata:
   el front le mandaba sólo zona y m³. */
/* ⚠ Se mira DENTRO de `aprCargarSalida`, no en todo el archivo: `empresa: p.empresa` aparece
   otras 5 veces en index.html (otras RPC que también mandan el pedido), así que buscarlo suelto
   daba verde aunque esta llamada no lo mandara — o sea, no chequeaba nada. */
/* Sin esto el chequeo matchea el COMENTARIO que explica el cambio y da verde con el código
   roto — pasó al escribir este test. Se mira el código, no lo que dice el código. */
const sinComentarios = (t) => String(t).replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
const iSal = src.indexOf("async function aprCargarSalida");
const cuerpoSal = iSal >= 0 ? src.slice(iSal, iSal + 900) : "";
if (!cuerpoSal.includes("gv_ppp_web_dia_salida")) {
  fallas.push("no encuentro la llamada a gv_ppp_web_dia_salida dentro de aprCargarSalida");
} else if (!/empresa\s*:/.test(sinComentarios(cuerpoSal)) ||
           !/order_id\s*:/.test(sinComentarios(cuerpoSal))) {
  fallas.push("aprCargarSalida no le manda empresa/order_id a gv_ppp_web_dia_salida: sin eso el " +
    "backend no puede saber si el pedido está retenido");
}
if (!/s\.motivo === "retenido"/.test(src)) {
  fallas.push("el chip de A Programar no contempla el motivo 'retenido'");
}

// ---- 3) el cartel ----
if (/Las cajas ya pickeadas <b>no se mueven<\/b>/.test(src)) {
  fallas.push("el pop-up sigue prometiendo que las cajas no se mueven");
}
/* v18.91 (Luis, 16/09) — VUELVE A «A GUARDAR», no a la góndola. Textual: "si hay un pedido
   programado que se pickeo y se manda de vuelta a programar, hace que los items que se pickearon
   vayan a A guardar". Deshace la v18.80 ("vuelve de donde salió: góndola o excedente"), tomada el
   mismo día: las cajas están en el piso de armado, nadie las llevó al estante, y escribirlas en
   `terminado` decía que estaban en una góndola donde no están. */
/* ⚠ `src` se lee en LATIN1, así que un "ó" del archivo llega como dos caracteres y una regex
   con acento NO matchea nunca (daría un falso rojo, o peor, un falso verde si se invirtiera).
   Por eso los patrones evitan las vocales acentuadas. */
if (!/se deshace<\/b>/.test(src) || !/vuelve a <b>A guardar<\/b>/.test(src)) {
  fallas.push("el pop-up no explica que lo pickeado/armado se deshace y cada caja vuelve a " +
    "«A guardar»");
}
if (/cada caja vuelve al lugar de donde sali/.test(src)) {
  fallas.push("el pop-up sigue prometiendo que las cajas vuelven a góndola o excedente: desde " +
    "la v18.91 van todas a «A guardar»");
}

if (fallas.length) {
  console.log("enviar-a-programar-deshace: ✗ FAIL\n  - " + fallas.join("\n  - "));
  process.exit(1);
}

let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.log("enviar-a-programar-deshace: estático ✓ OK (sin Playwright para la parte en vivo)"); process.exit(0); }
}

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {}, rpc = [];
    window.__isSupervisor = true;
    window.alert = function () {};
    window.aprQuien = async function () { return "luis@x"; };
    window.aprRpc = async function (fn, args) {
      rpc.push({ fn: fn, args: args });
      if (fn === "gv_ppp_web_desprogramar_previo") {
        return { cliente: "Mitre Hugo Alberto", cod: "4181", empresa: "lk", es_isis: false,
                 nps: [{ np_label: "LK 0034", tanda: "E01G", estado: "en_armado", tocada: true },
                       { np_label: "LK 0035", tanda: "E01G", estado: "en_armado" }] };
      }
      return [{ np_sacadas: 2, order_id: 1364, arts: 8, cajas: 46, detalle: "2 NP del pedido volvieron a A Programar" }];
    };
    window.pppSetStatus = function () {};
    window.pppLoadProgFromSupabase = async function () {};
    window.pgaRecargar = async function () {};
    window.pppCuarDeNpSacada = async function () { return null; };

    // ---- 4) el pop-up: dice las DOS NP y lo que pasa con las cajas ----
    const pr = epaConfirmar("LK 0034");
    await new Promise((res) => setTimeout(res, 120));
    const mh = (document.getElementById("epaModal") || {}).innerHTML || "";
    out.popupLasDos   = /LK 0034/.test(mh) && /LK 0035/.test(mh);
    out.popupDiceDeshace = /se deshace/.test(mh) && /A guardar/.test(mh) &&
                           !/vuelve al lugar de donde sali/.test(mh);
    out.popupNoMiente = !/no se mueven/.test(mh);
    epaCerrar(true);
    await pr;

    // ---- el camino web va por la RPC nueva, con la NP tocada ----
    rpc.length = 0;
    await pppVencVolver("LK 0034", { sinConfirm: true });
    const g = rpc.find(function (x) { return x.fn === "gv_ppp_pedido_a_programar"; });
    out.webUsaLaNueva = !!g && g.args.p_np === "LK 0034";
    out.webNoUsaVieja = !rpc.some(function (x) { return x.fn === "gv_ppp_web_desprogramar"; });

    // ---- y el de ISIS también ----
    rpc.length = 0;
    window.prompt = function () { return "se cargo mal"; };
    await pppVencSinProgramar("98700", { sinConfirm: true });
    const gi = rpc.find(function (x) { return x.fn === "gv_ppp_pedido_a_programar"; });
    out.isisUsaLaNueva = !!gi && gi.args.p_np === "98700";
    out.isisNoUsaVieja = !rpc.some(function (x) { return x.fn === "gv_ppp_isis_desprogramar"; });
    return out;
  });
  const malas = Object.keys(r).filter((k) => !r[k]);
  const pass = malas.length === 0 && errs.length === 0;
  console.log("enviar-a-programar-deshace:", JSON.stringify(r),
    malas.length ? "· fallan: " + malas.join(", ") : "",
    "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
