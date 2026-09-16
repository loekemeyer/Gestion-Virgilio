/* Regresión v18.74 — desarmar NO es siempre anular. Problema 325.

   `gv_ppp_np_desarmar`, con un pedido web, hacía dos cosas que se contradicen: escribía en
   `GV_Web_Cancelados` (que `gv_pedidos_web_excluidos` lee como 'anulado' = no vuelve NUNCA) y
   a la vez ponía `tanda = null` (que significa: vuelve a A Programar). El pedido quedaba en el
   limbo — sin tanda y excluido para siempre —, o sea **invisible en todas las pantallas**: ni
   en «Pedidos a programar», ni en Cuarentena, ni para el armado automático.

   Caso real: LK 1364 (Mitre Hugo Alberto, 19 renglones / 46 cajas). Su tanda E01G se desarmó
   el 15/09 porque el picking mostraba la lista recortada por el corte de 1000 filas — un error
   NUESTRO, con el pedido del cliente vivo. La propia fila de `GV_Web_Cancelados` dice en su
   motivo "Se deshace y vuelve a A Programar". Nadie lo vio hasta que Luis lo buscó en pantalla
   al día siguiente.

   La causa de fondo: desarmar servía para dos intenciones («se canceló» y «me equivoqué») y
   nadie las había separado, así que las dos hacían lo mismo. Ahora el modal las pregunta y el
   backend recibe `p_vuelve`.

   Chequea:
     1) que el modal PREGUNTE y no traiga default — elegir mal esconde el pedido de un cliente;
     2) que el botón siga deshabilitado con el justificativo puesto pero sin elegir;
     3) que al elegir, el botón diga cuál de las dos cosas va a hacer (no un genérico);
     4) que la elección VIAJE al backend como `p_vuelve`;
     5) que el modal ya no afirme "no vuelve a entrar" como si fuera siempre así.
   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");

const fallas = [];
if (!/p_vuelve/.test(src)) fallas.push("el front no manda p_vuelve a gv_ppp_np_desarmar");
if (/sale de la PPP<\/b> y no vuelve a entrar/.test(src)) {
  fallas.push("el modal sigue afirmando «no vuelve a entrar» como si fuera siempre así");
}
if (fallas.length) {
  console.log("desarmar-vuelve: ✗ FAIL\n  - " + fallas.join("\n  - "));
  process.exit(1);
}

let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.log("desarmar-vuelve: estático ✓ OK (sin Playwright para la parte en vivo)"); process.exit(0); }
}

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/*.supabase.co/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    // una fila de PPP cualquiera, para que el modal tenga qué mostrar
    window._pgaRows = [{ np: "LK 0034", tanda: "E01G", razon_social: "Mitre Hugo Alberto",
                         cod: "4181", empresa: "LK", m3: 0.299, fecha: "2026-09-16" }];
    window.aprQuien = async function () { return "test"; };
    let enviado = null;
    window.aprRpc = async function (fn, args) {
      if (fn === "gv_ppp_np_desarmar") { enviado = args; return [{ detalle: "ok" }]; }
      return [];
    };
    window.pppSetStatus = function () {};
    window.pppLoadProgFromSupabase = async function () {};
    window.pgaRecargar = async function () {};

    dsmAbrir("LK 0034");
    const radios = document.querySelectorAll('input[name="dsmVuelve"]');
    const btn = document.getElementById("dsmOk");

    // ---- 1) pregunta, y NINGUNA opción viene marcada ----
    out.hayDosOpciones   = radios.length === 2;
    out.ningunaPorDefecto = ![].slice.call(radios).some(function (x) { return x.checked; });

    // ---- 2) con justificativo pero sin elegir, el botón sigue trabado ----
    document.getElementById("dsmJust").value = "la lista del picking estaba recortada";
    dsmChk();
    out.sinElegirNoDeja = btn.disabled === true;
    out.diceQueFaltaElegir = /Elegí si el pedido vuelve/i.test(
      (document.getElementById("dsmHint") || {}).textContent || "");

    // ---- 3) al elegir, el botón dice QUÉ va a hacer ----
    dsmVuelveSet(true);
    out.eligiendoDestraba = btn.disabled === false;
    out.botonDiceVuelve   = /VUELVA a programar/i.test(btn.textContent || "");
    dsmVuelveSet(false);
    out.botonDiceCancela  = /CANCELAR el pedido/i.test(btn.textContent || "");

    // ---- 4) la elección viaja ----
    dsmVuelveSet(true);
    await dsmConfirmar();
    out.mandaVuelveTrue = !!(enviado && enviado.p_vuelve === true);
    out.mandaLaNp       = !!(enviado && enviado.p_np === "LK 0034");

    enviado = null;
    dsmAbrir("LK 0034");
    document.getElementById("dsmJust").value = "lo canceló el cliente por teléfono";
    dsmVuelveSet(false);
    await dsmConfirmar();
    out.mandaVuelveFalse = !!(enviado && enviado.p_vuelve === false);
    return out;
  });
  const malas = Object.keys(r).filter((k) => !r[k]);
  const pass = malas.length === 0 && errs.length === 0;
  console.log("desarmar-vuelve:", JSON.stringify(r),
    malas.length ? "· fallan: " + malas.join(", ") : "",
    "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
