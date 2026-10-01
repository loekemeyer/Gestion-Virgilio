/* v23.93 (Luis, 29/09) — EL HEADER DEL MONITOR DEL ADMIN.
   Pedido, sobre la captura: *"saca el monitor viejo, combina analisis e incosistencias en su
   propia pestaña (con subpestañas para cada uno), saca Vista TV y todo ese texto y la barra esa
   y el buscar tanda/operario. Deja: Fecha con reloj, boton de cerrar, el codigo para el login con
   su timer a modo de una rueda"* y *"saca el qr ya que usamos la fichada con el login"*.

   Se chequea corriendo la pantalla (las RPC mockeadas):
     (a) el QR de fichada NO EXISTE más — ni el cajón, ni el canvas, ni qrcode.js, ni el TOTP;
     (b) el header tiene TRES pestañas (Monitor, Mon. Admin y Análisis) y ninguna del monitor viejo ni «Vista TV»;
     (c) el título, la meta, la barra de avance y el buscador no se ven;
     (d) el código de login sale en 4 dígitos y la rueda se dibuja con el `cambia_en_s` del backend
         (42 de 60 → el arco queda al 70 %), no con un reloj propio del front;
     (e) la pestaña Análisis abre las subpestañas Productividad / Inconsistencias.
   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
const IDX = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
let fail = 0;
const ok = (c, m) => { console.log((c ? "✓ " : "✗ ") + m); if (!c) fail++; };

/* (a) el QR se fue del repo servido, no sólo de la pantalla */
ok(!/qrFichadaBox|qrCanvas|_startFichadaQr|FICHADA_HMAC_SECRET/.test(IDX),
   "(a) no queda nada del QR de fichada en index.html");
ok(!/<script src="qrcode\.js">|<script src="fichada-config\.js">/.test(IDX),
   "(a) index.html ya no carga qrcode.js ni fichada-config.js");
ok(fs.existsSync(path.join(__dirname, "..", "fichada.html")),
   "(a) fichada.html NO se borra: el link viejo tiene que seguir andando");

let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.log(fail ? "mon-header-codigo: ✗ FAIL" : "mon-header-codigo: estático ✓ OK (sin Playwright)"); process.exit(fail ? 1 : 0); }
}

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1600, height: 900 } });
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/*", (r) => (r.request().url().startsWith("file://") ? r.continue() : r.abort()));
  await p.route("**/rest/v1/**", (r) => {
    if (/gv_tv_clave_actual/.test(r.request().url())) {
      return r.fulfill({ status: 200, contentType: "application/json",
                         body: JSON.stringify({ clave: "4821", cambia_en_s: 42 }) });
    }
    return r.fulfill({ status: 200, contentType: "application/json", body: "[]" });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  await p.waitForTimeout(1200);
  await p.evaluate(() => { window.requireSupervisor = () => true; openMonitor(); });
  await p.waitForFunction(() => (document.getElementById("monClave") || {}).textContent !== "----",
                          { timeout: 8000 }).catch(() => {});

  const r = await p.evaluate(() => {
    const vis = (id) => {
      const e = document.getElementById(id);
      if (!e) return false;
      const r2 = e.getBoundingClientRect();
      return r2.width > 0 && r2.height > 0;
    };
    const tabs = Array.from(document.querySelectorAll("#monTabSwitch .mod-tab"))
                      .map((x) => x.textContent.trim());
    const out = {
      tabs: tabs,
      clave: (document.getElementById("monClave") || {}).textContent || "",
      arco: (document.getElementById("monClvArco") || {}).getAttribute
              ? document.getElementById("monClvArco").getAttribute("stroke-dashoffset") : null,
      qr: !!document.getElementById("qrFichadaBox"),
      verTitulo: vis("monitorTitleText"), verMeta: vis("monitorMeta"), verFiltro: vis("monFilter"),
      verReloj: vis("monitorClock"), verClave: vis("monClaveBox"),
      subVisibleEnTv: vis("anSubBar")
    };
    /* (f) v24.38 — «CÓDIGO DE INGRESO: 4145», en una línea, grande y CENTRADO. */
    const caja = document.getElementById("monClaveBox");
    const hdr  = caja ? caja.closest(".monitor-header") : null;
    const lab  = caja ? caja.querySelector(".mon-clave-lab") : null;
    const num  = document.getElementById("monClave");
    if (caja && hdr && lab && num) {
      const rc = caja.getBoundingClientRect(), rh = hdr.getBoundingClientRect();
      const rl = lab.getBoundingClientRect(),  rn = num.getBoundingClientRect();
      out.lab = lab.textContent.trim();
      out.px = parseFloat(getComputedStyle(num).fontSize);
      // desvío del centro de la caja contra el centro del header, en % del ancho del header
      out.desvio = Math.abs((rc.left + rc.width / 2) - (rh.left + rh.width / 2)) / rh.width * 100;
      // misma línea: las cajas del rótulo y del número se solapan verticalmente
      out.mismaLinea = Math.min(rl.bottom, rn.bottom) - Math.max(rl.top, rn.top) > 0;
    }
    setMonitorTab("incons");
    out.subVisibleEnAn = vis("anSubBar");
    out.subTabs = Array.from(document.querySelectorAll("#anSubBar .mod-tab")).map((x) => x.textContent.trim());
    out.anOn = (document.getElementById("monTabAn") || {}).className || "";
    return out;
  });

  ok(!r.qr, "(a) el cajón del QR no está en el DOM");
  /* v25.74: se sumó la pestaña «🛠️ Mon. Admin» (el tablero clickeable) entre Monitor y Análisis. */
  ok(r.tabs.length === 3 && /Monitor/.test(r.tabs[0]) && /Mon\. Admin/.test(r.tabs[1]) && /Análisis/.test(r.tabs[2]),
     "(b) el header tiene tres pestañas: Monitor, Mon. Admin y Análisis: " + JSON.stringify(r.tabs));
  ok(!r.tabs.some((t) => /Vista TV|Inconsist/.test(t)),
     "(b) no volvieron «Vista TV» ni «Inconsist.» como pestañas sueltas: " + JSON.stringify(r.tabs));
  ok(!r.verTitulo && !r.verMeta && !r.verFiltro,
     "(c) el título, la meta y el buscador no se ven en el header");
  ok(r.verReloj && r.verClave, "(c) sí se ven la fecha con reloj y el código");
  ok(r.clave.trim() === "4821", "(d) el código de login sale en el header: " + r.clave);
  /* La rueda la manda el backend: 42 s de 60 → queda el 70 % del arco, o sea offset ≈ 30,2
     sobre un largo de 100,53. Si el front se inventara su propio reloj, esto no daría. */
  ok(Math.abs(Number(r.arco) - 30.2) < 1.5,
     "(d) la rueda se dibuja con el cambia_en_s del backend (42/60 → offset ≈ 30,2): " + r.arco);
  ok(!r.subVisibleEnTv && r.subVisibleEnAn, "(e) las subpestañas salen sólo en Análisis");
  ok(r.subTabs.length === 2 && /Productividad/.test(r.subTabs[0]) && /Inconsistencias/.test(r.subTabs[1]),
     "(e) las subpestañas son Productividad e Inconsistencias: " + JSON.stringify(r.subTabs));
  ok(/\bon\b/.test(r.anOn), "(e) la pestaña Análisis queda marcada como activa");
  /* (f) v24.38 (Luis): *"quiero que ese codigo este mas grande, centrado y que sea
     «CÓDIGO DE INGRESO: XXXX» con el timer y toda la bola"*. */
  ok(/^código de ingreso:?$/i.test(String(r.lab || "").trim()),
     "(f) el rótulo dice «Código de ingreso:»: " + JSON.stringify(r.lab));
  ok(r.mismaLinea === true, "(f) el rótulo y el número van en la MISMA línea");
  ok(Number(r.px) >= 34,
     "(f) el número es más grande que antes (era 26-48px, ahora ≥ 34): " + r.px + "px");
  ok(Number(r.desvio) < 2,
     "(f) la caja está centrada en el header (desvío < 2 % del ancho): " +
     (r.desvio == null ? "sin medir" : r.desvio.toFixed(2) + " %"));
  ok(errs.length === 0, "sin errores de JS: " + errs.slice(0, 3).join(" | "));

  await b.close();
  if (fail) { console.log("mon-header-codigo: ✗ FAIL"); process.exit(1); }
  console.log("mon-header-codigo: ✓ OK");
})();
