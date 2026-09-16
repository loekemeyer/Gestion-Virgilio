/* El botón PPP del panel supervisor tiene badge, como los demás. (v19.14, pedido de Luis 2026-09-16:
   *"badge rojo con número arriba a la izquierda del icono de la PPP como con los demás"*)

   El badge existía desde la v8.82 y **no se veía nunca**, por dos motivos que este test cuida:

     1) contaba sólo `Alertas_Pedidos_Web` pendientes, que hoy son 0. Ahora cuenta todos los avisos
        de la PPP (`gv_ppp_avisos`): súper mezclado, tanda con dos recorridos, tanda en dos días,
        pedidos retenidos esperando fecha y las alertas web. Agrupado por COSA, no por fila: un
        camión mezclado cuenta 1 aunque tenga 4 pedidos adentro;
     2) el botón no era `position:relative`, así que el badge —que es `position:absolute`— se
        posicionaba contra otro ancestro y terminaba fuera de la tarjeta. Todos los demás botones
        con badge lo tienen; el de PPP era el único que no.

   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");

const fallas = [];
const btn = (src.match(/<button class="sup-action-btn" onclick="openPPP\(\)"[^>]*>.*?<\/button>/s) || [])[0] || "";
if (!btn) fallas.push("no se encuentra el botón PPP del panel supervisor");
else {
  if (!/position:relative/.test(btn)) fallas.push("el botón PPP no es position:relative — el badge se va a ir de la tarjeta");
  if (!/id="pppAlertBadge"/.test(btn)) fallas.push("el botón PPP no tiene el badge adentro");
  if (!/class="dp-badge"/.test(btn)) fallas.push("el badge de PPP no usa dp-badge: no va a verse igual que los demás");
  if (!/left:2px;right:auto/.test(btn)) fallas.push("el badge de PPP no está a la izquierda, que es donde lo pidió Luis");
}
if (!src.includes("rest/v1/gv_ppp_avisos")) fallas.push("el badge no lee gv_ppp_avisos: volvería a contar sólo las alertas web");
if (/pppAlertBadgeUpdate\(_pppAlertasWeb\)/.test(src)) fallas.push("quedó una llamada vieja que le pasa sólo las alertas web");
if (/ppp-alert-badge/.test(src)) fallas.push("quedó CSS muerto de la clase vieja ppp-alert-badge");

if (fallas.length) { console.log("ppp-badge: ✗ FAIL\n  - " + fallas.join("\n  - ")); process.exit(1); }

let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.log("ppp-badge: estático ✓ OK (sin Playwright para la parte en vivo)"); process.exit(0); }
}

(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ timezoneId: "America/Argentina/Buenos_Aires" });
  const p = await ctx.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.fulfill({ status: 200, headers: { "content-type": "application/json" }, body: "[]" }));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(() => {
    const out = {};
    const el = document.getElementById("pppAlertBadge");
    out.existe = !!el;
    if (!el) return out;

    // (a) con avisos: número rojo, y la suma de TODOS los tipos
    _pppAvisos = [
      { tipo: "super_mezclado",     titulo: "Súper mezclado con clientes en el mismo camión", n: 1 },
      { tipo: "tanda_dos_camiones", titulo: "Tanda con paradas de dos recorridos",            n: 1 },
      { tipo: "tanda_dos_dias",     titulo: "Tanda con el mismo código en dos días",          n: 1 },
      { tipo: "retenido_sin_fecha", titulo: "Pedidos sacados a mano, esperando fecha",        n: 7 }
    ];
    pppAlertBadgeUpdate();
    out.suma = el.textContent;                       // 10, no 4: suma los n, no cuenta los tipos
    out.rojo = el.className === "dp-badge";
    out.visible = el.style.display !== "none";
    out.izquierda = getComputedStyle(el).left === "2px";
    out.titleDesglosa = /7 · Pedidos sacados a mano/.test(el.title) && /1 · Súper mezclado/.test(el.title);

    // (b) el badge vive DENTRO del botón, y el botón está posicionado
    const bt = el.closest("button");
    out.dentroDelBoton = !!bt && /PPP/.test(bt.textContent);
    out.botonPosicionado = !!bt && getComputedStyle(bt).position === "relative";

    // (c) sin avisos: ✓ verde, igual que los demás módulos
    _pppAvisos = [];
    pppAlertBadgeUpdate();
    out.vacioTilde = el.textContent === "✓";
    out.vacioVerde = el.className === "dp-badge ok";
    out.vacioSigueIzquierda = getComputedStyle(el).left === "2px";

    // (d) un tipo con n grande no rompe nada
    _pppAvisos = [{ tipo: "retenido_sin_fecha", titulo: "Pedidos esperando fecha", n: 137 }];
    pppAlertBadgeUpdate();
    out.grande = el.textContent === "137";
    return out;
  });

  const mal = [];
  const ok = (c, m) => { if (!c) mal.push(m); };
  ok(errs.length === 0, "errores de página: " + errs.join(" | "));
  ok(r.existe, "no existe el badge pppAlertBadge");
  ok(r.suma === "10", "el badge tiene que sumar los avisos (1+1+1+7 = 10) y muestra: " + r.suma);
  ok(r.rojo, "con avisos el badge no queda rojo");
  ok(r.visible, "con avisos el badge no se muestra");
  ok(r.izquierda, "el badge no queda a la izquierda");
  ok(r.titleDesglosa, "el título del badge no desglosa qué son los avisos");
  ok(r.dentroDelBoton, "el badge no está dentro del botón de PPP");
  ok(r.botonPosicionado, "el botón de PPP no es position:relative — el badge se va de la tarjeta");
  ok(r.vacioTilde, "sin avisos el badge debería mostrar ✓ como los demás módulos");
  ok(r.vacioVerde, "sin avisos el badge no se pinta verde");
  ok(r.vacioSigueIzquierda, "al pasar a ✓ el badge se corrió de lugar (supSetBadge repone className)");
  ok(r.grande, "un número de 3 dígitos no se muestra");

  await b.close();
  if (mal.length) { console.log("ppp-badge: ✗ FAIL\n  - " + mal.join("\n  - ")); process.exit(1); }
  console.log("ppp-badge: ✓ OK (suma todos los avisos, a la izquierda, ✓ verde cuando no hay nada)");
})();
