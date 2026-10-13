/* v29.95 — EL PANEL POR ROL: APRETAR UN NOMBRE TIENE QUE ENTRAR

   Luis, 13/10 (con la captura del cuadro «¿Quién sos?»): "aprieto luis y no entra".

   Causa: todo el bloque del panel por rol (v29.92) vive ADENTRO de la IIFE `initAuth`,
   y sus botones son handlers INLINE (onclick="rolElegir('luis')"). Un handler inline se
   resuelve contra WINDOW, no contra el scope del script: rolElegir no existía ahí y el
   click tiraba "rolElegir is not defined". Mismo pozo que `window.sb` (v23.98).

   ⚠ UN CANDADO ESTÁTICO NO LO VE: el onclick está, la función está. La única forma de
   medirlo es CLICKEAR con la pantalla corriendo.

   Lo que se mide:
     (a) rolPickerAbrir se alcanza desde window y dibuja los 5 nombres
     (b) clickear «Luis» cierra el cuadro, deja el panel con "Hola, Luis" y guarda la elección
     (c) ningún error de página en todo el camino
     (d) GENÉRICO: TODO onclick que dibuje el cuadro o el panel resuelve contra window
         (así un botón nuevo del bloque no vuelve a nacer muerto)
     (e) «cambiar» del panel re-abre el cuadro

   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  // el contador del checklist no es lo que se prueba
  await p.route("**/rest/v1/**", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const fallas = [];
  const ok = (m) => console.log("ok   " + m);

  // (a) el cuadro se abre DESDE WINDOW (es lo que hace el onclick de «cambiar»)
  const tipoAbrir = await p.evaluate(() => typeof window.rolPickerAbrir);
  if (tipoAbrir !== "function") {
    await b.close();
    console.error("\nFALLA:\n - window.rolPickerAbrir no existe (" + tipoAbrir + "): un onclick inline se " +
      "resuelve contra window, no contra el scope de la IIFE — el cuadro no se abre y nada entra");
    process.exit(1);
  }
  ok("rolPickerAbrir se alcanza desde window");

  // el panel supervisor arranca oculto (no hay sesión de Google acá): se muestra su
  // contenedor, que es donde vive #rolPanel, para poder medir que el panel se VEA.
  await p.evaluate(() => {
    const sp = document.getElementById("supervisorPanel");
    if (sp) { sp.classList.remove("hidden"); sp.style.display = ""; }
    try { localStorage.removeItem("gv_sup_quien"); } catch (_e) {}
  });
  await p.evaluate(() => { if (typeof window.rolPickerAbrir === "function") window.rolPickerAbrir(); });

  const nombres = await p.$$eval("#rolPickerOv button", (bs) => bs.map((x) => (x.textContent || "").trim()));
  if (nombres.length !== 5) fallas.push("el cuadro dibujó " + nombres.length + " nombres, tienen que ser 5");
  else ok("el cuadro dibuja los 5 nombres");
  if (!/^Luis\b/.test(nombres[0] || "")) fallas.push("el primer botón no es Luis: «" + nombres[0] + "»");

  // (d) GENÉRICO: todo onclick del cuadro resuelve contra window
  const genOv = await p.evaluate(() => {
    const falta = []; let n = 0;
    document.querySelectorAll("#rolPickerOv [onclick]").forEach(function (el) {
      const code = el.getAttribute("onclick") || "";
      const RES = { event: 1, window: 1, this: 1, document: 1, "return": 1, "if": 1, "typeof": 1 };
      let mm; const re = /(\.?)\s*([A-Za-z_$][\w$]*)\s*[([]/g;
      while ((mm = re.exec(code))) {
        if (mm[1] === "." || RES[mm[2]]) continue;   // método de un objeto o palabra del lenguaje
        n++;
        if (typeof window[mm[2]] === "undefined") falta.push(mm[2]);
      }
    });
    return { n: n, falta: Array.from(new Set(falta)) };
  });
  // ⚠ sin este guard el chequeo da verde cuando el cuadro NO se dibujó (0 onclick = 0 faltantes)
  if (!genOv.n) fallas.push("el cuadro no tiene ningún onclick: no se dibujó");
  else if (genOv.falta.length) fallas.push("el cuadro tiene onclick que window no conoce: " + genOv.falta.join(", "));
  else ok("los " + genOv.n + " onclick del cuadro resuelven contra window");

  // (b) clickear Luis ENTRA
  try { await p.waitForSelector("#rolPickerOv button", { timeout: 4000 }); }
  catch (_e) {
    await b.close();
    console.error("\nFALLA:\n - el cuadro «¿Quién sos?» no dibujó ningún botón");
    process.exit(1);
  }
  await p.click("#rolPickerOv button");
  await p.waitForTimeout(250);

  const est = await p.evaluate(() => {
    const ov = document.getElementById("rolPickerOv");
    const pa = document.getElementById("rolPanel");
    let guardado = ""; try { guardado = localStorage.getItem("gv_sup_quien") || ""; } catch (_e) {}
    return {
      ovVisible: !!(ov && ov.style.display !== "none"),
      panelVisible: !!(pa && pa.style.display !== "none" && pa.offsetHeight > 0),
      txt: pa ? (pa.textContent || "").trim() : "",
      barra: (function () { const b = document.querySelector("#rolPanel .rolp-quien"); return b ? (b.textContent || "").trim() : ""; })(),
      guardado: guardado
    };
  });
  if (est.ovVisible) fallas.push("el cuadro «¿Quién sos?» quedó abierto después de apretar Luis");
  else ok("el cuadro se cierra al elegir");
  if (!est.panelVisible) fallas.push("#rolPanel no se dibujó: apretar Luis NO entra");
  else ok("el panel del rol se dibuja");
  if (!/Luis/.test(est.barra)) fallas.push("la barra no dice quién es: «" + est.barra + "»");
  else ok("la barra dice el nombre y el área");
  if (est.guardado !== "luis") fallas.push("no quedó guardada la elección (gv_sup_quien = «" + est.guardado + "»)");
  else ok("la elección queda guardada por dispositivo");

  // (d bis) los onclick del panel (las filas del checklist y «cambiar») también
  const genPan = await p.evaluate(() => {
    const falta = []; let n = 0;
    document.querySelectorAll("#rolPanel [onclick]").forEach(function (el) {
      const code = el.getAttribute("onclick") || "";
      const RES = { event: 1, window: 1, this: 1, document: 1, "return": 1, "if": 1, "typeof": 1 };
      let mm; const re = /(\.?)\s*([A-Za-z_$][\w$]*)\s*[([]/g;
      while ((mm = re.exec(code))) {
        if (mm[1] === "." || RES[mm[2]]) continue;   // método de un objeto o palabra del lenguaje
        n++;
        if (typeof window[mm[2]] === "undefined") falta.push(mm[2]);
      }
    });
    return { n: n, falta: Array.from(new Set(falta)) };
  });
  if (!genPan.n) fallas.push("el panel no tiene ningún onclick: no se dibujó");
  else if (genPan.falta.length) fallas.push("el panel tiene onclick que window no conoce: " + genPan.falta.join(", "));
  else ok("los " + genPan.n + " onclick del panel resuelven contra window");

  // (e) «cambiar» re-abre el cuadro
  const hayCambiar = await p.$("#rolPanel .rolp-cambiar");
  if (!hayCambiar) fallas.push("el panel no tiene el botón «cambiar»");
  else {
    await p.click("#rolPanel .rolp-cambiar");
    await p.waitForTimeout(150);
    const reabrio = await p.evaluate(() => {
      const ov = document.getElementById("rolPickerOv");
      return !!(ov && ov.style.display !== "none");
    });
    if (!reabrio) fallas.push("«cambiar» no re-abre el cuadro");
    else ok("«cambiar» re-abre el cuadro");
  }

  // (f) v29.98: PLEGADO por defecto, una sola línea, badge con PALABRA y «cambiar» angosto.
  //     Y vale para LOS CINCO roles, no sólo para Luis (Luis, 13/10: "que el arreglo sea
  //     general y no solo para luis").
  for (const k of ["luis", "thomas", "marianela", "tomas", "viviana"]) {
    const m = await p.evaluate(async (rol) => {
      try { localStorage.setItem("gv_sup_quien", rol); localStorage.removeItem("gv_rol_abierto"); } catch (_e) {}
      const ov = document.getElementById("rolPickerOv"); if (ov) ov.style.display = "none";
      window.rolElegir(rol);
      await new Promise((r) => setTimeout(r, 250));
      const sp = document.getElementById("supervisorPanel");
      if (sp) { sp.classList.remove("hidden"); sp.style.display = ""; }
      const c = document.getElementById("rolPanel");
      const bg = document.getElementById("rolpBadge");
      const cb = document.querySelector("#rolPanel .rolp-cambiar");
      const bar = document.querySelector("#rolPanel .rolp-bar");
      const filas = document.querySelectorAll("#rolPanel .rolp-row").length;
      return {
        alto: Math.round(c.getBoundingClientRect().height),
        abierto: c.classList.contains("abierto"),
        badge: bg ? (bg.textContent || "").trim() : "",
        cambiarW: cb ? Math.round(cb.getBoundingClientRect().width) : 0,
        anchoBarra: bar ? Math.round(bar.getBoundingClientRect().width) : 0,
        quien: (document.querySelector("#rolPanel .rolp-quien") || {}).textContent || "",
        filas: filas
      };
    }, k);
    if (m.abierto) fallas.push(k + ": el panel arranca desplegado (tiene que arrancar plegado)");
    if (m.alto > 60) fallas.push(k + ": plegado mide " + m.alto + " px — tiene que ser UNA línea (≤ 60)");
    if (!/[a-zñáéíóú]/i.test(m.badge)) fallas.push(k + ": el badge no lleva palabra, sólo color/número («" + m.badge + "»)");
    if (!m.cambiarW || m.cambiarW > 140) fallas.push(k + ": «cambiar» mide " + m.cambiarW + " px (el button{width:100%} global se lo comió)");
    if (!m.filas) fallas.push(k + ": el checklist quedó vacío");
    if (!m.quien.trim()) fallas.push(k + ": la barra no dice quién es");
  }
  ok("los 5 roles: una línea plegada, badge con palabra, «cambiar» angosto");

  // y al desplegar muestra el checklist
  await p.evaluate(() => { try { localStorage.setItem("gv_sup_quien", "luis"); } catch (_e) {} window.rolElegir("luis"); });
  await p.waitForTimeout(200);
  await p.evaluate(() => { const sp = document.getElementById("supervisorPanel"); if (sp) { sp.classList.remove("hidden"); sp.style.display = ""; } });
  const antes = await p.evaluate(() => Math.round(document.getElementById("rolPanel").getBoundingClientRect().height));
  await p.click("#rolPanel .rolp-bar");
  await p.waitForTimeout(200);
  const desp = await p.evaluate(() => ({
    alto: Math.round(document.getElementById("rolPanel").getBoundingClientRect().height),
    abierto: document.getElementById("rolPanel").classList.contains("abierto"),
    guardado: (function () { try { return localStorage.getItem("gv_rol_abierto"); } catch (_e) { return ""; } })()
  }));
  if (!desp.abierto || desp.alto <= antes) fallas.push("tocar la barra no despliega el checklist (" + antes + " → " + desp.alto + " px)");
  else ok("la barra despliega el checklist (" + antes + " → " + desp.alto + " px)");
  if (desp.guardado !== "1") fallas.push("el estado abierto/cerrado no se guarda por dispositivo");

  // (g) v30.04 — EL PASE GV-UI, medido sobre la pantalla CORRIENDO (no leyendo el CSS):
  //     el `font-size` que vale es el COMPUTADO, y el que manda puede venir del CSS global.
  //     Lo que el pase `disenador-gvui` encontró y esto deja candado:
  //       · el DATO del plegado (el badge) medía 12,5 px contra el nombre —el RÓTULO— a 14
  //       · el ✓ verde daba 3,15 y el «—» de «no pude leer» 2,45 (AA pide 4,5)
  //       · «cambiar» medía 22 px (la mitad de 44) y no se alcanzaba por teclado
  /* ⚠ el helper va como FUNCIÓN, no como string en un template literal: ahí `\d` del regex
     se come la barra (en un template una escapada desconocida deja sólo la letra), el match
     no devuelve nada y TODO contraste sale 1:1 — verde con los colores bien puestos. */
  await p.evaluate(() => {
    const lin = (c) => { c /= 255; return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
    const L = (rgb) => { const m = String(rgb).match(/[0-9]+(\.[0-9]+)?/g) || [0, 0, 0];
      return 0.2126 * lin(+m[0]) + 0.7152 * lin(+m[1]) + 0.0722 * lin(+m[2]); };
    window.__ct = (a, b) => { const x = L(a), y = L(b);
      return Math.round(((Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05)) * 100) / 100; };
  });

  for (const vp of [{ width: 1280, height: 900 }, { width: 390, height: 740 }]) {
    await p.setViewportSize(vp);
    const w = vp.width + "px";

    // los tres estados del número: sin leer («—») · al día («✓») · con pendientes (un número)
    for (const st of [
      { n: "no se pudo leer", body: null },
      { n: "al día",          body: "{}" },
      { n: "con pendientes",  body: '{"sin_zona_ped":3,"atrasados":2}' }
    ]) {
      await p.unroute("**/rest/v1/**");
      await p.route("**/rest/v1/**", (route) => st.body === null
        ? route.abort()
        : route.fulfill({ status: 200, contentType: "application/json", body: st.body }));
      await p.evaluate(() => {
        try { localStorage.setItem("gv_sup_quien", "luis"); localStorage.setItem("gv_rol_abierto", "1"); } catch (_e) {}
        const ov = document.getElementById("rolPickerOv"); if (ov) ov.style.display = "none";
        window.rolElegir("luis");
      });
      await p.waitForTimeout(350);
      await p.evaluate(() => { const sp = document.getElementById("supervisorPanel"); if (sp) { sp.classList.remove("hidden"); sp.style.display = ""; } });

      const m = await p.evaluate(() => {
        const ESCALA = [11, 12, 14, 16, 20, 30, 46];
        const cs = (el) => getComputedStyle(el);
        const num = document.querySelector("#rolPanel .rolp-num");
        const row = document.querySelector("#rolPanel .rolp-row");
        const bg = document.getElementById("rolpBadge");
        const quien = document.querySelector("#rolPanel .rolp-quien");
        const cb = document.querySelector("#rolPanel .rolp-cambiar");
        const bar = document.querySelector("#rolPanel .rolp-bar");
        const fuera = [];
        document.querySelectorAll("#rolPanel, #rolPanel *").forEach((el) => {
          const fs = Math.round(parseFloat(cs(el).fontSize) * 10) / 10;
          if (fs && ESCALA.indexOf(Math.round(fs)) < 0 && Math.abs(fs - Math.round(fs)) < 0.01) fuera.push(fs);
          else if (fs && Math.abs(fs - Math.round(fs)) >= 0.01) fuera.push(fs);
        });
        return {
          numTxt: num ? (num.textContent || "").trim() : "",
          numFs: num ? Math.round(parseFloat(cs(num).fontSize)) : 0,
          numCt: (num && row) ? window.__ct(cs(num).color, cs(row).backgroundColor) : 0,
          hintCt: (function () { const h = document.querySelector("#rolPanel .rolp-hint");
            return (h && row) ? window.__ct(cs(h).color, cs(row).backgroundColor) : 0; })(),
          badgeFs: bg ? Math.round(parseFloat(cs(bg).fontSize)) : 0,
          badgeCt: bg ? window.__ct(cs(bg).color, cs(bg).backgroundColor) : 0,
          quienFs: quien ? Math.round(parseFloat(cs(quien).fontSize)) : 0,
          cbAlto: cb ? Math.round(cb.getBoundingClientRect().height) : 0,
          cbTab: cb ? cb.tabIndex : -99,
          cbEnBarra: !!(cb && bar && bar.contains(cb)),
          aria: bar ? bar.getAttribute("aria-expanded") : null,
          /* nada del panel se sale del panel: a 390 px, sin `min-width:0` en la barra,
             «cambiar» quedaba pegado al borde de la pantalla, 12 px afuera. */
          desborde: (function () {
            const c = document.getElementById("rolPanel").getBoundingClientRect();
            const f = [];
            document.querySelectorAll("#rolPanel *").forEach((el) => {
              const r = el.getBoundingClientRect();
              if (r.width && (r.right > c.right + 1 || r.left < c.left - 1)) f.push(el.className || el.tagName);
            });
            return Array.from(new Set(f));
          })(),
          fuera: Array.from(new Set(fuera))
        };
      });

      const q = " [" + w + " · " + st.n + "]";
      if (m.numCt && m.numCt < 4.5) fallas.push("el número («" + m.numTxt + "») mide " + m.numCt + ":1 sobre la fila — AA pide 4,5" + q);
      if (m.hintCt && m.hintCt < 4.5) fallas.push("el hint mide " + m.hintCt + ":1 sobre la fila" + q);
      if (m.badgeCt && m.badgeCt < 4.5) fallas.push("el badge mide " + m.badgeCt + ":1" + q);
      if (m.numFs && m.numFs < 14) fallas.push("el número mide " + m.numFs + " px — 14 es el PISO de un dato" + q);
      if (m.badgeFs && m.badgeFs < 14) fallas.push("el badge (el DATO del plegado) mide " + m.badgeFs + " px — 14 es el piso" + q);
      if (m.badgeFs && m.quienFs && m.badgeFs <= m.quienFs)
        fallas.push("jerarquía al revés: el badge (dato) " + m.badgeFs + " px vs el nombre (rótulo) " + m.quienFs + " px" + q);
      if (m.cbAlto && m.cbAlto < 44) fallas.push("«cambiar» mide " + m.cbAlto + " px de alto — el blanco de toque es 44" + q);
      if (m.cbTab < 0) fallas.push("«cambiar» no se alcanza por teclado (tabIndex " + m.cbTab + ")" + q);
      if (m.cbEnBarra) fallas.push("«cambiar» está ADENTRO del <button> de la barra: no es HTML válido y se come su área de toque" + q);
      if (m.aria !== "true") fallas.push("la barra no dice aria-expanded=true estando desplegada (" + m.aria + ")" + q);
      if (m.desborde.length) fallas.push("se sale del panel: " + m.desborde.join(", ") + q);
      if (m.fuera.length) fallas.push("tamaños fuera de la escala 11·12·14·16·20·30: " + m.fuera.join(", ") + q);
    }
  }
  await p.setViewportSize({ width: 1280, height: 900 });
  ok("pase GV-UI: escala, contraste de los 3 estados, jerarquía y los 44 px de «cambiar»");

  // (c) ningún error de página
  const malos = errs.filter((m) => /rol|GV_ROL|GV_SUP/i.test(m));
  if (malos.length) fallas.push("errores de página: " + malos.join(" · "));
  else ok("sin errores de página del panel por rol");

  await b.close();
  if (fallas.length) { console.error("\nFALLA:\n - " + fallas.join("\n - ")); process.exit(1); }
  console.log("\nTODO OK — el panel por rol entra al apretar un nombre");
})();
