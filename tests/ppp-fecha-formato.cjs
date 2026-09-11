/* Regresión (v15.50): la columna Fecha de la PPP tenía DOS formatos mezclados.
   Las NP de ISIS pasan por _pppSupaFecha ("2026-09-10 00:00:00" → "10/09/2026");
   las de la página salían CRUDAS de PPP_Web_Programacion (columnas `date`), así
   que el Resumen mostraba "2026-09-09" en los días cuyo primer pedido era web.
   Verifica que:
   (a) pppTraerWebProgramados normalice fecha y fecha_entrega a dd/mm/aaaa,
   (b) el Resumen no imprima NINGUNA fecha en aaaa-mm-dd,
   (c) pppGuardarWeb escriba ISO en la tabla (las columnas son `date` y PostgREST
       corre con DateStyle 'ISO, MDY': "10/09/2026" se habría guardado como
       9 de OCTUBRE, y con día > 12 habría fallado el POST entero). */
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
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const posts = [];
    window.sbAuth = { getAccessToken: async () => "tok" };
    const json = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o),
                           headers: { get: (k) => (String(k).toLowerCase() === "content-range" ? "0-" + Math.max(0, (o.length || 1) - 1) + "/" + (o.length || 0) : null) } });
    const WEB = [{
      empresa: "lk", order_id: 1400, np_idx: 1, np: 66, cod_cliente: "4109",
      razon_social: "Di Leo", direccion: "Bragado 5742", barrio: "Mataderos",
      zona: "Zona 3 - CABA Oeste", tanda: "E18A",
      fecha_entrega: "2026-09-29", fecha_recep: "2026-09-10",
      m3: 0.08, m3_parcial: false, lineas: 1, cajas: 1
    }];
    window.fetch = async (url, opt) => {
      const u = String(url);
      if (opt && opt.method === "POST" && u.includes("PPP_Web_")) { posts.push({ u, b: JSON.parse(opt.body) }); return json([]); }
      if (u.includes("PPP_Web_Programacion")) return json(WEB);
      return json([]);
    };

    // (a) las filas web salen ya en dd/mm/aaaa, igual que las de ISIS
    const filas = await pppTraerWebProgramados();
    const f = filas[0] || {};

    // (b) Resumen con UNA fila de ISIS y UNA web: ninguna fecha en aaaa-mm-dd
    const isis = { np: "98704", tanda: "E17A", cod: "3958", razon_social: "Salvetti",
                   m3: 1.2, localidad: "Mataderos", zona: "Zona 3 - CABA Oeste",
                   fecha: "08/09/2026", fecha_entrega: "10/09/2026", programmed: true };
    const html = pppResumenHtml([isis, f]);
    const fechas = (html.match(/<td class="f">([^<]*)<\/td>/g) || [])
      .map(s => s.replace(/<[^>]*>/g, "")).filter(s => s !== "TOTAL");

    // (c) el guardado viaja en ISO aunque la fila tenga dd/mm/aaaa
    await pppGuardarWeb([f]);
    const cab = (posts.find(x => x.u.includes("PPP_Web_Programacion")) || {}).b || [];

    return {
      fecha: f.fecha, fechaEntrega: f.fecha_entrega,
      fechas: fechas,
      isoEnPantalla: fechas.filter(s => /^\d{4}-\d{2}-\d{2}/.test(s)),
      cabFe: cab[0] ? cab[0].fecha_entrega : null,
      cabFr: cab[0] ? cab[0].fecha_recep : null
    };
  });

  const dmy = /^\d{2}\/\d{2}\/\d{4}$/;
  const ok = dmy.test(r.fecha) && r.fecha === "10/09/2026"
    && dmy.test(r.fechaEntrega) && r.fechaEntrega === "29/09/2026"
    // v15.57 (dueño): en la tabla Fecha × zonas del Resumen la fecha se PINTA "dd/mm" (sin año);
    // el dato de la fila sigue siendo dd/mm/aaaa (r.fecha / r.fechaEntrega, arriba) y a la base va ISO.
    && r.fechas.length === 2 && r.fechas.every(s => /^\d{2}\/\d{2}$/.test(s))
    && r.isoEnPantalla.length === 0
    && r.cabFe === "2026-09-29" && r.cabFr === "2026-09-10"
    && errs.length === 0;

  console.log("ppp-fecha-formato:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join(" | ") : "none", ok ? "· ✓ OK" : "· ✗ FALLÓ");
  await b.close();
  process.exit(ok ? 0 : 1);
})();
