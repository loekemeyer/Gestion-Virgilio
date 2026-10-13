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
      const m = /([A-Za-z_$][\w$]*)\s*[([]/.exec(el.getAttribute("onclick") || "");
      if (!m) return; n++;
      if (typeof window[m[1]] === "undefined") falta.push(m[1]);
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
      guardado: guardado
    };
  });
  if (est.ovVisible) fallas.push("el cuadro «¿Quién sos?» quedó abierto después de apretar Luis");
  else ok("el cuadro se cierra al elegir");
  if (!est.panelVisible) fallas.push("#rolPanel no se dibujó: apretar Luis NO entra");
  else ok("el panel del rol se dibuja");
  if (!/Hola, Luis/.test(est.txt)) fallas.push("el panel no saluda a Luis: «" + est.txt.slice(0, 80) + "»");
  else ok("el panel dice «Hola, Luis»");
  if (est.guardado !== "luis") fallas.push("no quedó guardada la elección (gv_sup_quien = «" + est.guardado + "»)");
  else ok("la elección queda guardada por dispositivo");

  // (d bis) los onclick del panel (las filas del checklist y «cambiar») también
  const genPan = await p.evaluate(() => {
    const falta = []; let n = 0;
    document.querySelectorAll("#rolPanel [onclick]").forEach(function (el) {
      const m = /([A-Za-z_$][\w$]*)\s*[([]/.exec(el.getAttribute("onclick") || "");
      if (!m) return; n++;
      if (typeof window[m[1]] === "undefined") falta.push(m[1]);
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

  // (c) ningún error de página
  const malos = errs.filter((m) => /rol|GV_ROL|GV_SUP/i.test(m));
  if (malos.length) fallas.push("errores de página: " + malos.join(" · "));
  else ok("sin errores de página del panel por rol");

  await b.close();
  if (fallas.length) { console.error("\nFALLA:\n - " + fallas.join("\n - ")); process.exit(1); }
  console.log("\nTODO OK — el panel por rol entra al apretar un nombre");
})();
