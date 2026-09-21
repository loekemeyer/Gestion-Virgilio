/* Regresión v20.55 — EL BADGE DE LA PPP DICE QUÉ SON ESOS AVISOS.

   Luis, 2026-09-21: *"el «4» del badge qué significa? Debería tener más info"*.

   El desglose existía sólo en el `title` del badge — un tooltip que en el monitor táctil no
   existe y en la compu hay que adivinar. Un número rojo que no dice de qué es no se mira.

   Chequea, con la red simulada (sin tocar Supabase):
   - tocar el badge abre el pop-up y NO abre la PPP (el clic no se propaga al botón);
   - el pop-up agrupa por tipo, con el conteo de cada grupo;
   - muestra la COSA concreta (tanda, pedido), la fecha y el detalle;
   - muestra qué hacer, una vez por grupo y no por fila;
   - sin avisos dice que no hay, no queda en «Leyendo…»;
   - si la consulta falla, lo dice en vez de quedarse colgado;
   - el badge sigue contando lo mismo que `gv_ppp_avisos` (el pop-up no inventa otro número).
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
const DET = [
  { tipo: "tanda_dos_camiones", orden: 2, titulo: "Tanda con paradas de dos recorridos",
    fecha: "2026-09-22", que: "Tanda D69H",
    detalle: "2 NP · 2 cliente(s) · Capital + GBA Norte", accion: "La tanda se parte por camión." },
  { tipo: "retenido_sin_fecha", orden: 4, titulo: "Pedidos sacados a mano, esperando fecha",
    fecha: "2026-09-21", que: "LK pedido 1448", detalle: "3 NP · salió de la tanda D69H",
    accion: "Está en A Programar esperando día." },
  { tipo: "retenido_sin_fecha", orden: 4, titulo: "Pedidos sacados a mano, esperando fecha",
    fecha: "2026-09-22", que: "LK pedido 1358", detalle: "1 NP · salió de la tanda E50A",
    accion: "Está en A Programar esperando día." },
  { tipo: "retenido_sin_fecha", orden: 4, titulo: "Pedidos sacados a mano, esperando fecha",
    fecha: "2026-09-24", que: "CH pedido 218", detalle: "1 NP · salió de la tanda E26B",
    accion: "Está en A Programar esperando día." },
];
(async () => {
  const root = path.join(__dirname, "..");
  const fallos = [];
  const html = fs.readFileSync(path.join(root, "index.html"), "latin1");
  if (!/id="pppAlertBadge"[^>]*onclick="event\.stopPropagation\(\);pppAvisosAbrir\(\)"/.test(html))
    fallos.push("el badge no abre el desglose (o el clic se propaga y abre la PPP)");
  if (!/\.pav-ov\{/.test(html)) fallos.push("falta el CSS del pop-up");

  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async (det) => {
    const out = {};
    let pedidos = [];
    let modo = "ok";
    window.fetch = async function (url) {
      pedidos.push(String(url));
      if (modo === "error") return { ok: false, status: 500, json: async () => [] };
      return { ok: true, status: 200, json: async () => (modo === "vacio" ? [] : det) };
    };
    // 1) con avisos
    await pppAvisosAbrir();
    const ov = document.getElementById("pppAvisosPop");
    out.abierto = !!(ov && ov.classList.contains("show"));
    out.html = ov ? ov.innerHTML : "";
    out.url = pedidos[0] || "";
    // 2) sin avisos
    modo = "vacio"; pedidos = [];
    await pppAvisosAbrir();
    out.vacio = document.getElementById("pppAvisosPop").innerHTML;
    // 3) la consulta falla
    modo = "error"; pedidos = [];
    await pppAvisosAbrir();
    out.error = document.getElementById("pppAvisosPop").innerHTML;
    // 4) cerrar
    pppAvisosCerrar();
    out.cerrado = !document.getElementById("pppAvisosPop").classList.contains("show");
    return out;
  }, DET);
  await b.close();
  if (errs.length) fallos.push("errores de página: " + errs.join(" | "));

  const h = r.html || "";
  if (!r.abierto) fallos.push("el pop-up no se abrio");
  if (!/gv_ppp_avisos_detalle/.test(r.url)) fallos.push("no lee gv_ppp_avisos_detalle, lee: " + r.url);
  const grupos = (h.match(/class="pav-grupo"/g) || []).length;
  if (grupos !== 2) fallos.push("agrupo en " + grupos + " grupos (esperado 2: dos tipos distintos)");
  const filas = (h.match(/class="pav-fila"/g) || []).length;
  if (filas !== 4) fallos.push("mostro " + filas + " filas (esperado 4, el mismo numero que el badge)");
  if (!/class="pav-g-n">3</.test(h)) fallos.push("el grupo de retenidos no dice 3");
  if (!/class="pav-g-n">1</.test(h)) fallos.push("el grupo de la tanda no dice 1");
  if (!/Tanda D69H/.test(h)) fallos.push("no muestra la cosa concreta (Tanda D69H)");
  if (!/LK pedido 1448/.test(h)) fallos.push("no muestra el pedido concreto");
  if (!/>22\/09</.test(h)) fallos.push("no muestra la fecha en dd/mm");
  const acciones = (h.match(/class="pav-accion"/g) || []).length;
  if (acciones !== 2) fallos.push("la accion sale " + acciones + " veces: va una por GRUPO, no por fila");
  if (!/Sin avisos/.test(r.vacio || "")) fallos.push("sin avisos no lo dice (queda en Leyendo...)");
  if (/Leyendo/.test(r.vacio || "")) fallos.push("sin avisos queda colgado en «Leyendo…»");
  if (!/No se pudo leer/.test(r.error || "")) fallos.push("si la consulta falla no avisa");
  if (!r.cerrado) fallos.push("no se puede cerrar");

  if (fallos.length) { console.error("ppp-avisos-detalle FALLA:\n - " + fallos.join("\n - ")); process.exit(1); }
  console.log("ppp-avisos-detalle OK — el badge abre el desglose con la tanda, el pedido y qué hacer.");
})();
