/* v12.05 — Regresión del módulo "Pedidos sin cargar en PPP" (stkOpenNpFaltan).
   El módulo tenía dos secciones y las dos miraban para el otro lado del problema:
   (1) vista_np_sin_programar = está en la base y NO en programación, (2)
   vista_np_faltantes_secuencia = números que no existen en ninguna fuente. La NP
   programada SIN artículos en la base (caso 98574/98575, tanda D52B) no caía en
   ninguna: solo la cazaba la alerta de Telegram. Se agregó la tercera sección, que
   lee vista_np_prog_sin_base.
   v12.27 — cada fila lleva una ✕ para tacharla: no todo caso es un error (un cliente
   que pide con mucha anticipación queda fuera de la ventana del Sheet de la base).
   El tachado va a NP_Sin_Base_Revisadas y la vista lo excluye, así que también apaga
   la alerta de Telegram.
   Verifica: A) la sección se dibuja con sus NP; B) el badge del panel suma las TRES
   fuentes; C) con la vista vacía la sección no aparece; D) la ✕ postea el tachado y
   saca la fila. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado (ver tests/smoke.cjs)."); process.exit(2); }
}
(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const PROG_SIN_BASE = [
      { np: "98574", tanda: "D52B", cliente: "Torres Y Liva", fecha_entrega: "2026-08-31", m3: 1.02 },
      { np: "98575", tanda: "D52B", cliente: "Torres Y Liva", fecha_entrega: "2026-08-31", m3: 0.5 }
    ];
    const stub = (progSinBase) => {
      window.fetch = async (url) => {
        const u = String(url);
        let data = [];
        if (u.indexOf("vista_np_sin_programar") >= 0) data = [{ np: "98111", fecha: "2026-08-20", cliente: "X", cajas: 3, lineas: 1 }];
        else if (u.indexOf("vista_np_faltantes_secuencia") >= 0) data = [{ np_faltante: "98120", anterior: "98119", siguiente: "98121" }];
        else if (u.indexOf("vista_np_prog_sin_base") >= 0) data = progSinBase;
        return { ok: true, status: 200, json: async () => data };
      };
    };

    stub(PROG_SIN_BASE);
    await stkOpenNpFaltan();
    const html = document.getElementById("stkPopBody").innerHTML;
    const badge = document.getElementById("npFaltanBadge");
    const conSeccion = {
      seccionVisible: html.indexOf("SIN artículos en la base") >= 0,
      titulo2: html.indexOf("2 NP programada(s)") >= 0,
      np98574: html.indexOf("98574") >= 0,
      np98575: html.indexOf("98575") >= 0,
      tandaD52B: html.indexOf("D52B") >= 0,
      // la sección va ARRIBA de las otras dos (es lo más urgente: frena el picking)
      antesDeSalteadas: html.indexOf("SIN artículos en la base") < html.indexOf("salteada"),
      // sigue mostrando lo de siempre
      seccionSalteadas: html.indexOf("salteada") >= 0,
      filaSinProgramar: html.indexOf("98111") >= 0,
      badgeModulo: badge ? badge.textContent : null   // 1 + 1 + 2 = 4
    };

    // El badge del panel (se calcula aparte, sin abrir el módulo) tiene que dar lo mismo.
    await npFaltanLoadBadge();
    const badgePanel = document.getElementById("npFaltanBadge").textContent;

    // Sin NPs sin base: la sección no se dibuja y el resto queda igual.
    stub([]);
    await stkOpenNpFaltan();
    const html2 = document.getElementById("stkPopBody").innerHTML;
    const sinSeccion = {
      seccionOculta: html2.indexOf("SIN artículos en la base") < 0,
      salteadasSiguen: html2.indexOf("salteada") >= 0,
      badgeModulo: document.getElementById("npFaltanBadge").textContent   // 1 + 1 + 0 = 2
    };

    // v12.27 — tachar una NP: "no es un error" (upsert en NP_Sin_Base_Revisadas).
    // Caso real: cliente que pide con mucha anticipación (Matiz SA, NP 97889) queda
    // fuera de la ventana del Sheet de la base y aparece acá sin nada que arreglar.
    stub(PROG_SIN_BASE);
    await stkOpenNpFaltan();
    const htmlAntes = document.getElementById("stkPopBody").innerHTML;
    let posteado = null;
    const fetchLectura = window.fetch;
    window.fetch = async (url, opts) => {
      const u = String(url);
      if (u.indexOf("NP_Sin_Base_Revisadas") >= 0 && opts && opts.method === "POST") {
        posteado = { url: u, body: JSON.parse(opts.body) };
        return { ok: true, status: 201, json: async () => ({}) };
      }
      return fetchLectura(url, opts);
    };
    window.confirm = () => true;
    window.prompt = () => "pide con 3 meses de anticipación";
    window.facAuthWriteHeaders = async (extra) => Object.assign({ apikey: "k", Authorization: "Bearer jwt" }, extra || {});
    await npSinBaseMarcar("98574");
    const htmlDespues = document.getElementById("stkPopBody").innerHTML;
    const tachado = {
      hayBotonX: htmlAntes.indexOf("npSinBaseMarcar('98574')") >= 0,
      posteoOk: !!posteado && posteado.url.indexOf("on_conflict=np") >= 0,
      npPosteada: posteado ? posteado.body.np : null,
      estadoPosteado: posteado ? posteado.body.estado : null,
      motivoPosteado: posteado ? posteado.body.motivo : null,
      // la fila tachada sale de la lista, la otra queda
      saleDeLaLista: htmlDespues.indexOf("98574") < 0,
      quedaLaOtra: htmlDespues.indexOf("98575") >= 0,
      tituloBaja1: htmlDespues.indexOf("1 NP programada(s)") >= 0
    };

    return { conSeccion, badgePanel, sinSeccion, tachado };
  });
  await b.close();

  const A = r.conSeccion.seccionVisible && r.conSeccion.titulo2 && r.conSeccion.np98574 &&
            r.conSeccion.np98575 && r.conSeccion.tandaD52B && r.conSeccion.antesDeSalteadas &&
            r.conSeccion.seccionSalteadas && r.conSeccion.filaSinProgramar;
  const B = r.conSeccion.badgeModulo === "4" && r.badgePanel === "4";
  const C = r.sinSeccion.seccionOculta && r.sinSeccion.salteadasSiguen && r.sinSeccion.badgeModulo === "2";
  const D = r.tachado.hayBotonX && r.tachado.posteoOk && r.tachado.npPosteada === "98574" &&
            r.tachado.estadoPosteado === "no_es_problema" && !!r.tachado.motivoPosteado &&
            r.tachado.saleDeLaLista && r.tachado.quedaLaOtra && r.tachado.tituloBaja1;

  console.log("npf-prog-sin-base:", JSON.stringify(r));
  console.log("  pageerrors:", errs.length ? errs.join(" | ") : "none");
  console.log("  A sección ✓/✗:", A ? "✓" : "✗", "· B badge:", B ? "✓" : "✗", "· C vacío:", C ? "✓" : "✗",
              "· D tachar:", D ? "✓" : "✗",
              "·", (A && B && C && D && !errs.length) ? "OK" : "FAIL");
  process.exit((A && B && C && D && !errs.length) ? 0 : 1);
})();
