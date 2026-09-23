/* v21.97 (Luis, 23/09) — pop-up de DÍA OCUPADO al soltar un pedido en un día con programación.
   Se corre la pantalla: se abre el pop-up con las simulaciones mockeadas, se leen las 3 opciones
   y se eligen. Muerde por los dos lados:
   (a) día VACÍO → no hay pop-up, va derecho a aprGenerarTanda (como siempre);
   (b) día OCUPADO → 3 opciones, cada una con su reporte (problemas, tandas que se mueven, fijas);
   (c) elegir 3 → primero gv_ppp_dia_reprogramar con p_simular=false y modo correr, DESPUÉS la tanda
       nueva (si fuera al revés, la tanda nueva también se correría);
   (d) elegir 1 → no llama a reprogramar, sólo arma la tanda. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "load" });

  const r = await p.evaluate(async () => {
    const log = [];
    const F = "2026-09-30";
    const corr = [
      { tanda: "E48G", fecha_actual: F, fecha_nueva: "2026-10-01", accion: "mueve", motivo: "pendiente", m3: 2.5, zona: "Zona 3 - CABA Oeste", vence: true, vencia: false },
      { tanda: "E48H", fecha_actual: F, fecha_nueva: "2026-10-01", accion: "mueve", motivo: "armada: se mueve con su mismo código", m3: 0.5, zona: "Zona 2 - CABA Centro", vence: false, vencia: false },
      { tanda: "E50B", fecha_actual: F, fecha_nueva: F, accion: "fijo", motivo: "en proceso (picking o armado sin terminar): no se toca", m3: 1.2, zona: "Zona 5 - GBA Oeste", vence: false, vencia: false },
      { tanda: "E60A", fecha_actual: F, fecha_nueva: F, accion: "fijo", motivo: "súper: queda en su día (moverlo a mano si hace falta)", m3: 3, zona: "Super", vence: false, vencia: false },
      { tanda: "E70A", fecha_actual: "2026-10-01", fecha_nueva: "2026-10-02", accion: "mueve", motivo: "pendiente", m3: 1, zona: "Zona 4 - GBA Sur", vence: false, vencia: false }
    ];
    const auto = corr.filter(function (x) { return x.fecha_actual === F; });
    window.aprQuien = async function () { return "test@x"; };
    window.aprRender = function () {};
    window.aprGenerarTanda = async function (f, keys, o) { log.push("generar:" + f + ":" + keys.join(",") + ":" + !!(o && o.sinConfirm)); };
    let vacio = false;
    window.aprRpc = async function (fn, body) {
      log.push(fn + ":" + body.p_modo + ":" + body.p_simular);
      if (vacio) return [];
      return body.p_modo === "correr" ? corr : auto;
    };
    const ped = { empresa: "lk", order_id: 1600, zona: "Zona 1 - CABA Sur", m3: 0.4, np_total: 1 };

    // (a) día vacío
    vacio = true; await aprDiaOcupadoAbrir(F, ped);
    const a = { log: log.slice(), popup: !!(document.getElementById("aprDoOv") && document.getElementById("aprDoOv").classList.contains("show")) };
    log.length = 0; vacio = false;

    // (b) día ocupado
    await aprDiaOcupadoAbrir(F, ped);
    const ov = document.getElementById("aprDoOv");
    const ops = [...ov.querySelectorAll(".ado-op")].map(function (o) { return o.textContent.replace(/\s+/g, " "); });
    const bShow = ov.classList.contains("show");

    // (c) elegir 3
    log.length = 0;
    const btn3 = ov.querySelectorAll(".ado-op")[2].querySelector(".ado-b");
    btn3.click(); await new Promise(function (res) { setTimeout(res, 50); });
    const c = log.slice();

    // (d) elegir 1
    await aprDiaOcupadoAbrir(F, ped); log.length = 0;
    ov.querySelectorAll(".ado-op")[0].querySelector(".ado-b").click(); await new Promise(function (res) { setTimeout(res, 50); });
    const d = log.slice();
    return { a: a, bShow: bShow, ops: ops, c: c, d: d };
  });

  const fallas = [];
  if (r.a.popup) fallas.push("(a) con el día vacío abrió el pop-up");
  if (!r.a.log.some(function (x) { return /^generar:2026-09-30/.test(x); })) fallas.push("(a) día vacío no fue derecho a armar la tanda: " + r.a.log.join(" | "));
  if (!r.bShow || r.ops.length !== 3) fallas.push("(b) el pop-up no tiene 3 opciones: " + r.ops.length);
  else {
    if (!/Sumarlo/.test(r.ops[0])) fallas.push("(b) opción 1 no es Sumarlo");
    if (!/más de 2/.test(r.ops[0])) fallas.push("(b) opción 1 no avisa los camiones de más: " + r.ops[0]);
    if (!/E50B.*en proceso/.test(r.ops[2])) fallas.push("(b) opción 3 no muestra la tanda EN PROCESO fija: " + r.ops[2]);
    if (!/E60A.*súper/.test(r.ops[2])) fallas.push("(b) opción 3 no muestra el súper fijo");
    if (!/E48H.*mismo código/.test(r.ops[2])) fallas.push("(b) opción 3 no dice que la armada va con su mismo código");
    if (!/Pasan a vencer[\s\S]*E48G/.test(r.ops[2])) fallas.push("(b) opción 3 no avisa que E48G pasa a vencer");
    if (!/Reprogramar el resto/.test(r.ops[1])) fallas.push("(b) opción 2 no es Reprogramar el resto");
  }
  const iRep = r.c.findIndex(function (x) { return x === "gv_ppp_dia_reprogramar:correr:false"; });
  const iGen = r.c.findIndex(function (x) { return /^generar:2026-09-30:lk\|1600|^generar:2026-09-30/.test(x); });
  if (iRep < 0) fallas.push("(c) elegir 3 no ejecutó el corrimiento: " + r.c.join(" | "));
  if (iGen < 0 || iGen < iRep) fallas.push("(c) la tanda nueva no se armó DESPUÉS de correr: " + r.c.join(" | "));
  if (r.d.some(function (x) { return /:false$/.test(x) && /reprogramar/.test(x); })) fallas.push("(d) sumar llamó a reprogramar");
  if (!r.d.some(function (x) { return /^generar:/.test(x); })) fallas.push("(d) sumar no armó la tanda");
  if (errs.length) fallas.push("pageerrors: " + errs.join(" | "));

  const ok = fallas.length === 0;
  console.log("apr-dia-ocupado:", JSON.stringify({ c: r.c, d: r.d }));
  if (!ok) console.log("  ✗ " + fallas.join("\n  ✗ "));
  console.log(ok ? "· ✓ OK" : "· ✗ FALLÓ");
  await b.close();
  process.exit(ok ? 0 : 1);
})();
