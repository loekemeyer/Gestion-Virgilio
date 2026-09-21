/* v20.34 (Thomas, 2026-09-21) — "cuando se escribe un comentario a un cliente nuevo o un cliente
   en cuarentena y se envía, la próxima vez que abrís el módulo para dejar un comentario aparece
   el texto en el cuadro (por más que ya se haya mandado)".

   El pop-up de comentarios es UNO solo (Cuarentena y Clientes nuevos usan el mismo) y no se
   destruye al cerrar: queda `hidden` con su HTML adentro. cuarComRender arranca rescatando lo
   tipeado del <textarea> que encuentra en el DOM, así que levantaba el del cierre anterior.

   Lo que este test candea, y son los tres puntos donde se rompía:
     1. después de mandar el comentario, el cuadro queda vacío EN PANTALLA;
     2. al cerrar, el pop-up se vacía (no queda el textarea viejo colgado);
     3. al reabrirlo, el cuadro arranca vacío. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1200, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {}, esperar = (ms) => new Promise((res) => setTimeout(res, ms));
    const guardados = [];
    // el backend, de mentira: el comentario se "manda" y vuelve en la lista del hilo
    window.aprQuien = async () => "test@virgilio";
    window.aprRpc = async (fn, body) => {
      if (fn === "gv_cuarentena_comentar") { guardados.push(body.p_texto); return null; }
      if (fn === "gv_cuarentena_comentarios")
        return guardados.map((t, i) => ({ creado_at: "2026-09-21T10:0" + i + ":00", persona: "Vivi", por: "test@virgilio", texto: t }));
      return [];
    };
    window.cuarYaProgRecargar = () => {};   // no dispara recargas de tabla en el test
    window.cuarComLoteRecargar = () => {};

    const abrir = async () => {
      cuarComAbrir({ modo: "log", empresa: "lk", clave: "98617", np: "NP 98617", cli: "Riondini Lucas" });
      await esperar(120);
    };
    const ta = () => document.getElementById("cuarComTexto");

    // (1) se abre, se elige quién y se escribe
    await abrir();
    out.abre = !!ta() && !document.getElementById("cuarComModal").hidden;
    cuarQuienSet("Vivi");
    ta().value = "18/09 se volvió a reclamar al vendedor";
    await cuarComAgregar(); await esperar(120);
    out.seMando = guardados.length === 1;
    out.quedaEnElLog = /se volvió a reclamar al vendedor/.test(document.getElementById("cuarComModal").innerHTML);
    // el cuadro tiene que quedar VACÍO apenas se manda (no al reabrir)
    out.cuadroVacioTrasMandar = ((ta() || {}).value || "") === "";

    // (2) al cerrar no puede quedar el textarea viejo colgado en el DOM
    cuarComCerrar(); await esperar(30);
    out.cerradoSinTextarea = !document.getElementById("cuarComTexto");

    // (3) y al reabrir, el cuadro arranca vacío — ÉSTE es el bug que reportó Thomas
    await abrir();
    out.reabreVacio = ((ta() || {}).value || "") === "";
    out.reabreConHilo = /se volvió a reclamar al vendedor/.test(document.getElementById("cuarComModal").innerHTML);

    // (4) y lo que NO hay que romper: mientras el pop-up está abierto, un redibujo no puede
    // comerse lo que la persona está escribiendo a medias
    ta().value = "a medio escribir";
    cuarComRender(); await esperar(30);
    out.conservaBorrador = ((ta() || {}).value || "") === "a medio escribir";
    return out;
  });

  await b.close();
  const fallan = Object.keys(r).filter((k) => !r[k]);
  if (errs.length) { console.error("pageerror:", errs.join(" | ")); process.exit(1); }
  if (fallan.length) { console.error("FALLA cuar-com-limpia:", fallan.join(", "), JSON.stringify(r)); process.exit(1); }
  console.log("OK cuar-com-limpia:", Object.keys(r).length, "checks");
})();
