/* v18.90 (Thomas, 2026-09-16) — CANCELAR UN PEDIDO desde el módulo de Facturación.
   Pedido: *"un botón para cancelar pedido; un pop-up que pregunte el motivo y que me deje salir
   si toqué sin querer; dos botones, falta stock y otro (en otro me deja escribir); si se
   cancela desaparece de la PPP pero no de Supabase, y lo que estaba armado va a la bodega de
   a guardar"*.

   Chequea:
     (a) la fila de Facturación trae el botón «✕ Cancelar», tanto en una NP web como en una de ISIS;
     (b) abrirlo NO llama a nada y muestra los DOS motivos;
     (c) se sale sin hacer nada con «Volver» y con Escape (el pedido no se toca);
     (d) «Seguir» sin motivo no avanza, y con «Otro» exige texto escrito;
     (e) el paso de confirmar dice las tres consecuencias (no se factura / no se borra de la
         base / lo armado va a A guardar) — es la 2da confirmación de la v15.65;
     (f) al confirmar se llama `gv_ppp_np_desarmar` con p_vuelve=false y p_a_guardar=TRUE y el
         motivo dentro del justificativo. Si alguien cambia esos dos flags, el pedido volvería a
         A Programar o la mercadería volvería a góndola: es el corazón del pedido del dueño;
     (g) el motivo «Falta stock» viaja como tal sin pedir que lo tipeen;
     (h) si la RPC falla, el pop-up NO se cierra y muestra el error (la fila no puede
         desaparecer de la pantalla si el backend no la canceló).
   Sin red. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const llamadas = [];
    let fallar = false;

    // Sesión de supervisor simulada: facAuthWriteHeaders pide un token y aprQuien lee el mail.
    const payload = btoa(JSON.stringify({ email: "loekemeyer.n8n@gmail.com" }));
    window.sbAuth = { getAccessToken: async function () { return "x." + payload + ".y"; } };
    window.fetch = function (url, opt) {
      url = String(url);
      if (url.indexOf("/rpc/") >= 0) {
        llamadas.push({ url: url, body: JSON.parse((opt && opt.body) || "{}") });
        if (fallar) return Promise.resolve({ ok: false, status: 400, text: function () { return Promise.resolve('{"message":"La NP ya tiene Carga Camion"}'); } });
        return Promise.resolve({ ok: true, status: 200, text: function () {
          return Promise.resolve(JSON.stringify([{ np: "LK 0024", es_isis: false, tanda: "E01A", arts: 3, cajas: 12,
            detalle: "3 articulos · 12 cajas devueltas (12 a A guardar) · pedido CANCELADO: sale de la PPP y no vuelve" }]));
        } });
      }
      return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve([]); },
                               text: function () { return Promise.resolve("[]"); } });
    };
    window.facReintentar = function () { out.recargo = true; };

    // ── (a) la fila trae el botón ────────────────────────────────────────────
    _facNpsHoy = new Set(); _facNpsTodos = new Set();
    _facCajas = new Map([["LK 0024", 12], ["98651", 7]]);
    facRender([{ tanda: "E01A", fechaEntrega: "16/09", fechaEntregaRaw: "2026-09-16", pedidos: [
      { np: "LK 0024", cod: "4181", razonSocial: "Mitre Hugo Alberto", m3: 1.2 },
      { np: "98651",   cod: "2001", razonSocial: "Osa SRL",            m3: 0.5 }
    ] }]);
    const filaWeb  = document.querySelector('tr[data-fac-np="LK 0024"]');
    const filaIsis = document.querySelector('tr[data-fac-np="98651"]');
    const btnWeb   = filaWeb  && filaWeb.querySelector(".fac-btn-cancel");
    out.botonWeb  = !!btnWeb;
    out.botonIsis = !!(filaIsis && filaIsis.querySelector(".fac-btn-cancel"));
    // control de no-trivialidad: el tilde de la NP de ISIS sigue estando (no lo pisamos)
    out.tildeIntacto = !!(filaIsis && filaIsis.querySelector(".fac-btn-tick"));

    // (a2) v18.93 (Thomas: "que los botones de acción aparezcan uno al lado del otro, como en
    // columnas diferentes") — no apilados. Se mide de verdad: el módulo está oculto en la
    // pantalla inicial, así que primero se lo fuerza visible y después se miran los rectángulos.
    for (let n = document.getElementById("facContainer"); n && n !== document.body; n = n.parentElement) {
      n.removeAttribute("hidden"); n.style.display = "block"; n.style.visibility = "visible";
    }
    out.ladoALado = [filaWeb, filaIsis].every(function (fila) {
      const els = [...fila.querySelectorAll("td.fac-accion-cell button, td.fac-accion-cell span.fac-tick-web")];
      if (els.length !== 2) return false;
      const r = els.map(function (e) { const b = e.getBoundingClientRect(); return { cen: Math.round(b.top + b.height / 2), izq: Math.round(b.left) }; });
      return r[0].cen === r[1].cen        // misma línea, centrados entre sí
          && r[1].izq > r[0].izq;          // el ✕ a la DERECHA del ✓ / ⬇ Excel
    });
    // y la columna no se desborda por meter los dos
    out.sinDesborde = [...document.querySelectorAll("td.fac-accion-cell")]
      .every(function (td) { return td.scrollWidth <= td.clientWidth + 1; });

    // ── (b) abrirlo no llama a nada y muestra los dos motivos ───────────────
    btnWeb.click();
    const ov = document.getElementById("facCancelOverlay");
    out.abre = !!ov && ov.classList.contains("show");
    const body = document.getElementById("facCancelBody");
    out.dosMotivos = /Falta stock/.test(body.innerHTML) && />✏ Otro</.test(body.innerHTML);
    out.diceLaNp = /LK 0024/.test(body.innerHTML) && /Mitre Hugo/.test(body.innerHTML);
    // Ojo: facRender dispara sus propias lecturas (neto, correcciones, …) y todas pasan por
    // /rpc/. Lo que se mide acá es que NO se llamó al DESARME, que es lo que cancela el pedido.
    const desarmes = function () { return llamadas.filter(function (c) { return /gv_ppp_np_desarmar/.test(c.url); }); };
    out.abrirNoLlama = desarmes().length === 0;

    // ── (c) salir sin hacer nada ────────────────────────────────────────────
    facCancelClose();
    out.cierraVolver = !ov.classList.contains("show") && desarmes().length === 0;
    btnWeb.click();
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    out.cierraEscape = !ov.classList.contains("show") && desarmes().length === 0;

    // ── (d) «Seguir» sin motivo, y «Otro» sin texto ─────────────────────────
    btnWeb.click();
    facCancelPaso2();
    out.sinMotivoNoAvanza = /Eleg. el motivo/i.test(document.getElementById("facCancelBody").innerHTML);
    facCancelMotivo("otro");
    out.otroAbreTexto = !!document.getElementById("facCancelTxt");
    document.getElementById("facCancelTxt").value = "no";
    facCancelPaso2();
    out.otroExigeTexto = /Escrib. por qu. se cancela/i.test(document.getElementById("facCancelBody").innerHTML)
                         && !!document.getElementById("facCancelTxt");

    // ── (e) el paso de confirmar ────────────────────────────────────────────
    document.getElementById("facCancelTxt").value = "el cliente lo dio de baja por telefono";
    facCancelPaso2();
    const conf = document.getElementById("facCancelBody").innerHTML;
    out.confirmaDice = /No se factura/i.test(conf) && /No se borra de la base/i.test(conf)
                       && /A guardar/.test(conf) && /el cliente lo dio de baja/.test(conf);
    out.confirmaTieneVolver = /facCancelVolver\(\)/.test(conf);

    // ── (f) la llamada ──────────────────────────────────────────────────────
    await facCancelConfirmar();
    const c = desarmes()[desarmes().length - 1] || { url: "", body: {} };
    out.llamaDesarmar = /\/rpc\/gv_ppp_np_desarmar$/.test(c.url);
    out.np            = c.body.p_np === "LK 0024";
    out.noVuelve      = c.body.p_vuelve === false;
    out.aGuardar      = c.body.p_a_guardar === true;
    out.justificativo = /Cancelado desde Facturaci.n: el cliente lo dio de baja por telefono/.test(String(c.body.p_justificativo || ""));
    out.quien         = String(c.body.p_por || "") === "loekemeyer.n8n@gmail.com";
    out.cierraAlOk    = !ov.classList.contains("show");
    out.sacaLaFila    = !document.querySelector('tr[data-fac-np="LK 0024"]');

    // ── (g) «Falta stock» sin tipear nada ───────────────────────────────────
    facRender([{ tanda: "E01A", fechaEntrega: "16/09", fechaEntregaRaw: "2026-09-16", pedidos: [
      { np: "LK 0024", cod: "4181", razonSocial: "Mitre Hugo Alberto", m3: 1.2 }] }]);
    document.querySelector('tr[data-fac-np="LK 0024"] .fac-btn-cancel').click();
    facCancelMotivo("stock");
    out.stockNoPideTexto = !document.getElementById("facCancelTxt");
    facCancelPaso2();
    await facCancelConfirmar();
    out.stockJustificativo = /Cancelado desde Facturaci.n: falta stock/
      .test(String((desarmes()[desarmes().length - 1] || { body: {} }).body.p_justificativo || ""));

    // ── (h) si el backend dice que no, el pop-up se queda y lo muestra ──────
    fallar = true;
    facRender([{ tanda: "E01A", fechaEntrega: "16/09", fechaEntregaRaw: "2026-09-16", pedidos: [
      { np: "LK 0024", cod: "4181", razonSocial: "Mitre Hugo Alberto", m3: 1.2 }] }]);
    document.querySelector('tr[data-fac-np="LK 0024"] .fac-btn-cancel').click();
    facCancelMotivo("stock"); facCancelPaso2();
    await facCancelConfirmar();
    out.errorNoCierra = ov.classList.contains("show")
      && /Carga Camion/.test(document.getElementById("facCancelBody").innerHTML);
    out.errorNoSacaFila = !!document.querySelector('tr[data-fac-np="LK 0024"]');

    // ── cableado: el botón está EN el render, no sólo en el DOM de esta prueba
    out.enElRender = /fac-btn-cancel/.test(String(facRender)) && /facCancelarNP\(this\)/.test(String(facRender));
    out.css = [...document.styleSheets].some((ss) => {
      try { return [...ss.cssRules].some((x) => /\.faccan-op/.test(x.cssText)); } catch (_e) { return false; }
    });
    return out;
  });
  await b.close();

  const fails = [];
  const chk = (c, m) => { console.log((c ? "ok   " : "MAL  ") + m); if (!c) fails.push(m); };
  chk(r.botonWeb, "(a) la fila de una NP web trae el botón ✕ Cancelar");
  chk(r.botonIsis, "(a) la fila de una NP de ISIS también lo trae");
  chk(r.tildeIntacto, "(a) el tilde ✓ de la NP de ISIS sigue estando");
  chk(r.ladoALado, "(a2) los dos botones van UNO AL LADO DEL OTRO, centrados, con el ✕ a la derecha");
  chk(r.sinDesborde, "(a2) y la columna Acción no se desborda");
  chk(r.abre, "(b) el botón abre el pop-up");
  chk(r.dosMotivos, "(b) el pop-up muestra los dos motivos: Falta stock y Otro");
  chk(r.diceLaNp, "(b) el pop-up dice qué NP y qué cliente se cancela");
  chk(r.abrirNoLlama, "(b) abrirlo no llama al backend");
  chk(r.cierraVolver, "(c) «Volver» cierra sin cancelar nada");
  chk(r.cierraEscape, "(c) Escape cierra sin cancelar nada");
  chk(r.sinMotivoNoAvanza, "(d) sin motivo no avanza");
  chk(r.otroAbreTexto, "(d) «Otro» abre el campo de texto");
  chk(r.otroExigeTexto, "(d) «Otro» exige que se escriba el motivo");
  chk(r.confirmaDice, "(e) el paso de confirmar dice las tres consecuencias y repite el motivo");
  chk(r.confirmaTieneVolver, "(e) del paso de confirmar también se puede volver");
  chk(r.llamaDesarmar, "(f) llama a gv_ppp_np_desarmar");
  chk(r.np, "(f) manda la NP");
  chk(r.noVuelve, "(f) p_vuelve = false (el pedido NO vuelve a A Programar)");
  chk(r.aGuardar, "(f) p_a_guardar = true (lo armado va a la bodega A guardar)");
  chk(r.justificativo, "(f) el motivo escrito viaja en el justificativo");
  chk(r.quien, "(f) queda registrado quién lo canceló");
  chk(r.cierraAlOk, "(f) al salir bien, el pop-up se cierra");
  chk(r.sacaLaFila, "(f) al salir bien, la fila desaparece de la lista");
  chk(r.recargo, "(f) y se vuelve a leer la PPP para que la fila no reaparezca");
  chk(r.stockNoPideTexto, "(g) «Falta stock» no pide tipear nada");
  chk(r.stockJustificativo, "(g) «Falta stock» viaja como motivo");
  chk(r.errorNoCierra, "(h) si el backend rechaza, el pop-up queda abierto con el error");
  chk(r.errorNoSacaFila, "(h) y la fila NO desaparece");
  chk(r.enElRender, "el botón está cableado en facRender, no sólo en el DOM de la prueba");
  chk(r.css, "el CSS del pop-up está en la hoja de estilos");
  if (errs.length) { console.log("MAL  errores de página: " + errs.join(" | ")); fails.push("pageerror"); }
  if (fails.length) { console.error("\nFALLÓ: " + fails.length); process.exit(1); }
  console.log("\nfac-cancelar-pedido: OK");
})();
