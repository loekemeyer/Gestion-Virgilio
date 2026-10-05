/* v21.97 (Luis, 23/09) — pop-up de DÍA OCUPADO al soltar un pedido en un día con programación.
   Se corre la pantalla: se abre el pop-up con las simulaciones mockeadas, se leen las 3 opciones
   y se eligen. Muerde por los dos lados:
   (a) día VACÍO → no hay pop-up, va derecho a aprGenerarTanda (como siempre);
   (b) día OCUPADO → 3 opciones, cada una con su reporte (problemas, tandas que se mueven, fijas);
   (c) elegir 3 → primero gv_ppp_dia_reprogramar con p_simular=false y modo correr, DESPUÉS la tanda
       nueva (si fuera al revés, la tanda nueva también se correría);
   (d) elegir 1 → no llama a reprogramar, sólo arma la tanda.
   v26.82 (Luis, 05/10) — la opción 2 es gv_ppp_dia_ajustar: lo NUEVO va como dato (queda fijo) y sale
   sólo lo que no entra, por grupo de zonas entero:
   (e) la simulación de la opción 2 manda p_nuevo con el pedido (y si es súper);
   (f) si sumándolo el día se pasa, el encabezado lo dice y la opción 1 es «Programarlo así igual»;
   (g) el reporte de la opción 2 cuenta lo que YA tiene el día destino (E70A el 01/10);
   (h) elegir 2 → gv_ppp_dia_ajustar con p_simular=false y el mismo p_nuevo, DESPUÉS la tanda;
   v26.88 (Luis, 05/10: "olvidate del 2 camiones por día" · "no debería mover los fijos"):
   (i) el día se mide SÓLO por m³: ya no existe el conteo de camiones (_adoCamiones) ni el aviso «más de 2»,
       y un día con 5 grupos de zonas que entra en los 4,30 m³ no tiene problemas;
   (j) lo programado o movido a mano que devuelve gv_ppp_dia_ajustar se lista como fijo en la opción 2.
   v26.93 (Luis, 05/10: "automático debería priorizar que no venza nada"):
   (k) la opción 2 dice que nada se mueve si así pasa a vencer, lista como fija la tanda que la base frena por
       vencimiento y no tiene «Pasan a vencer». */
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
      { tanda: "E70A", fecha_actual: "2026-10-01", fecha_nueva: "2026-10-02", accion: "mueve", motivo: "pendiente", m3: 2, zona: "Zona 4 - GBA Sur", vence: false, vencia: false }
    ];
    // lo que devuelve gv_ppp_dia_ajustar: sólo el día; E48G (Z3) sale al 01/10, donde ya está E70A
    const auto = [
      { tanda: "E48G", fecha_actual: F, fecha_nueva: "2026-10-01", accion: "mueve", motivo: "pendiente: su grupo no entra en los 4,30 m³ del día", m3: 2.5, zona: "Zona 3 - CABA Oeste", vence: false, es_super: false },
      { tanda: "E48H", fecha_actual: F, fecha_nueva: F, accion: "queda", motivo: "pendiente: entra en el día", m3: 0.5, zona: "Zona 2 - CABA Centro", vence: false, es_super: false },
      { tanda: "E50B", fecha_actual: F, fecha_nueva: F, accion: "fijo", motivo: "en proceso (picking o armado sin terminar): no se toca", m3: 1.2, zona: "Zona 5 - GBA Oeste", vence: false, es_super: false },
      { tanda: "E60A", fecha_actual: F, fecha_nueva: F, accion: "fijo", motivo: "súper: queda en su día", m3: 3, zona: "Super", vence: false, es_super: true },
      { tanda: "E49A", fecha_actual: F, fecha_nueva: F, accion: "fijo", motivo: "programada o movida a mano: no se mueve", m3: 0.3, zona: "Zona 4 - GBA Sur", vence: false, es_super: false },
      { tanda: "E49B", fecha_actual: F, fecha_nueva: F, accion: "fijo", motivo: "pendiente: no se mueve porque pasaría a vencer (vence el 30/09)", m3: 0.2, zona: "Zona 6 - GBA Norte", vence: false, es_super: false }
    ];
    const llamadas = [];
    window.aprQuien = async function () { return "test@x"; };
    window.aprRender = function () {};
    window.aprGenerarTanda = async function (f, keys, o) { log.push("generar:" + f + ":" + keys.join(",") + ":" + !!(o && o.sinConfirm)); };
    let vacio = false;
    window.aprRpc = async function (fn, body) {
      log.push(fn + ":" + body.p_modo + ":" + body.p_simular);
      llamadas.push({ fn: fn, body: JSON.parse(JSON.stringify(body)) });
      if (vacio) return [];
      if (fn === "gv_ppp_dia_ajustar") return auto;
      return body.p_modo === "correr" ? corr : [];
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
    const head = ov.querySelector(".ado-h").textContent.replace(/\s+/g, " ");
    const simAj = llamadas.filter(function (x) { return x.fn === "gv_ppp_dia_ajustar"; }).map(function (x) { return x.body; });

    // (c) elegir 3
    log.length = 0;
    const btn3 = ov.querySelectorAll(".ado-op")[2].querySelector(".ado-b");
    btn3.click(); await new Promise(function (res) { setTimeout(res, 50); });
    const c = log.slice();

    // (d) elegir 1
    await aprDiaOcupadoAbrir(F, ped); log.length = 0;
    ov.querySelectorAll(".ado-op")[0].querySelector(".ado-b").click(); await new Promise(function (res) { setTimeout(res, 50); });
    const d = log.slice();

    // (h) elegir 2
    await aprDiaOcupadoAbrir(F, ped); log.length = 0; llamadas.length = 0;
    ov.querySelectorAll(".ado-op")[1].querySelector(".ado-b").click(); await new Promise(function (res) { setTimeout(res, 50); });
    const h = { log: log.slice(), ej: llamadas.filter(function (x) { return x.fn === "gv_ppp_dia_ajustar"; }).map(function (x) { return x.body; }) };

    // (i) sin tope de camiones: 5 grupos de zonas + un súper, 3 m³ en total → sin problemas
    const i = {
      sinConteo: typeof _adoCamiones === "undefined",
      probs: _adoProblemasDia(F, [
        { zona: "Zona 1 - CABA Sur", m3: 0.5 }, { zona: "Zona 2 - CABA Centro", m3: 0.5 }, { zona: "Zona 3 - CABA Oeste", m3: 0.5 },
        { zona: "Zona 4 - GBA Sur", m3: 0.5 }, { zona: "Zona 6 - GBA Norte", m3: 0.5 }, { zona: "Zona 5 - GBA Oeste", m3: 0.5, es_super: true }])
    };
    return { a: a, bShow: bShow, ops: ops, c: c, d: d, head: head, simAj: simAj, h: h, i: i };
  });

  const fallas = [];
  if (r.a.popup) fallas.push("(a) con el día vacío abrió el pop-up");
  if (!r.a.log.some(function (x) { return /^generar:2026-09-30/.test(x); })) fallas.push("(a) día vacío no fue derecho a armar la tanda: " + r.a.log.join(" | "));
  if (!r.bShow || r.ops.length !== 3) fallas.push("(b) el pop-up no tiene 3 opciones: " + r.ops.length);
  else {
    if (!/Programarlo así igual/.test(r.ops[0])) fallas.push("(f) el día se pasa y la opción 1 no dice «Programarlo así igual»: " + r.ops[0]);
    if (!/se pasa/.test(r.head)) fallas.push("(f) el encabezado no avisa que sumándolo el día se pasa: " + r.head);
    if (!/m³ \(más que el promedio/.test(r.ops[0])) fallas.push("(b) opción 1 no avisa los m³ de más: " + r.ops[0]);
    if (/camion/i.test(r.ops[0] + r.head)) fallas.push("(i) el pop-up sigue hablando de camiones: " + r.head + " / " + r.ops[0]);
    if (!/E49A — programada o movida a mano/.test(r.ops[1])) fallas.push("(j) opción 2 no lista como fija la tanda movida a mano: " + r.ops[1]);
    if (!/nada se mueve si así pasa a vencer/.test(r.ops[1])) fallas.push("(k) opción 2 no dice que nada se mueve si así pasa a vencer: " + r.ops[1]);
    if (!/E49B — pendiente: no se mueve porque pasaría a vencer/.test(r.ops[1])) fallas.push("(k) opción 2 no lista como fija la tanda frenada por vencimiento: " + r.ops[1]);
    if (/Pasan a vencer/.test(r.ops[1])) fallas.push("(k) opción 2 tiene tandas que pasan a vencer: " + r.ops[1]);
    if (!/E50B.*en proceso/.test(r.ops[2])) fallas.push("(b) opción 3 no muestra la tanda EN PROCESO fija: " + r.ops[2]);
    if (!/E60A.*súper/.test(r.ops[2])) fallas.push("(b) opción 3 no muestra el súper fijo");
    if (!/E48H.*mismo código/.test(r.ops[2])) fallas.push("(b) opción 3 no dice que la armada va con su mismo código");
    if (!/Pasan a vencer[\s\S]*E48G/.test(r.ops[2])) fallas.push("(b) opción 3 no avisa que E48G pasa a vencer");
    if (!/Reprogramar el resto/.test(r.ops[1])) fallas.push("(b) opción 2 no es Reprogramar el resto");
    if (!/E48G[^→]*30\/9 → [^0-9]*1\/10/.test(r.ops[1])) fallas.push("(g) opción 2 no muestra E48G al 01/10: " + r.ops[1]);
    if (!/1\/10: 4,50 m³/.test(r.ops[1])) fallas.push("(g) opción 2 no cuenta lo que ya tiene el 01/10 (E70A 2 + E48G 2,5): " + r.ops[1]);
  }
  const iRep = r.c.findIndex(function (x) { return x === "gv_ppp_dia_reprogramar:correr:false"; });
  const iGen = r.c.findIndex(function (x) { return /^generar:2026-09-30:lk\|1600|^generar:2026-09-30/.test(x); });
  if (iRep < 0) fallas.push("(c) elegir 3 no ejecutó el corrimiento: " + r.c.join(" | "));
  if (iGen < 0 || iGen < iRep) fallas.push("(c) la tanda nueva no se armó DESPUÉS de correr: " + r.c.join(" | "));
  if (r.d.some(function (x) { return /:false$/.test(x) && /reprogramar/.test(x); })) fallas.push("(d) sumar llamó a reprogramar");
  if (!r.d.some(function (x) { return /^generar:/.test(x); })) fallas.push("(d) sumar no armó la tanda");
  const s0 = r.simAj[0] || {};
  if (!r.simAj.length || s0.p_simular !== true) fallas.push("(e) la opción 2 no se simuló con gv_ppp_dia_ajustar");
  else if (!Array.isArray(s0.p_nuevo) || s0.p_nuevo.length !== 1 || s0.p_nuevo[0].m3 !== 0.4 || s0.p_nuevo[0].zona !== "Zona 1 - CABA Sur" || s0.p_nuevo[0].super !== false)
    fallas.push("(e) p_nuevo de la simulación no trae el pedido: " + JSON.stringify(s0.p_nuevo));
  const iAj = r.h.log.findIndex(function (x) { return x === "gv_ppp_dia_ajustar:undefined:false"; });
  const iGen2 = r.h.log.findIndex(function (x) { return /^generar:2026-09-30/.test(x); });
  if (iAj < 0) fallas.push("(h) elegir 2 no ejecutó gv_ppp_dia_ajustar: " + r.h.log.join(" | "));
  if (iGen2 < 0 || iGen2 < iAj) fallas.push("(h) la tanda nueva no se armó DESPUÉS de ajustar: " + r.h.log.join(" | "));
  if (r.h.log.some(function (x) { return /gv_ppp_dia_reprogramar:automatico/.test(x); })) fallas.push("(h) elegir 2 sigue llamando al automático viejo");
  if (!r.h.ej.length || JSON.stringify(r.h.ej[0].p_nuevo) !== JSON.stringify(s0.p_nuevo)) fallas.push("(h) se ejecutó con otro p_nuevo que el simulado");
  if (!r.i.sinConteo) fallas.push("(i) sigue existiendo el conteo de camiones (_adoCamiones)");
  if (r.i.probs.length) fallas.push("(i) un día de 3 m³ con 5 grupos marca problemas: " + JSON.stringify(r.i.probs));
  if (errs.length) fallas.push("pageerrors: " + errs.join(" | "));

  const ok = fallas.length === 0;
  console.log("apr-dia-ocupado:", JSON.stringify({ c: r.c, d: r.d, h: r.h.log }));
  if (!ok) console.log("  ✗ " + fallas.join("\n  ✗ "));
  console.log(ok ? "· ✓ OK" : "· ✗ FALLÓ");
  await b.close();
  process.exit(ok ? 0 : 1);
})();
