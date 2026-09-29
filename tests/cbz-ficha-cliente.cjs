/* v23.98 — Submódulo Cobranzas (Luis, 29/09): "pestañas dentro, empezando con la
   búsqueda de clientes; se busca un cliente (lk o ch) y se abre una ficha con
   deuda consolidada".

   Corre la pantalla de verdad (no es un candado de texto) y mide:
     (a) openCobranzas abre y arranca en la pestaña Clientes, con las 4 pestañas;
     (b) la lista sale ordenada por deuda, mayor → menor;
     (c) el MISMO cliente con código en LK y en CH aparece UNA vez y la deuda es
         la suma de los dos — que es lo que pidió Luis;
     (d) buscar por código encuentra al cliente (y buscar por nombre también);
     (e) tocar el renglón abre la ficha, que muestra la deuda consolidada, el
         desglose por empresa y los comprobantes con el pago;
     (f) tocar un comprobante abre la explicación + la escala de descuentos con
         el escalón que corresponde a los días marcado;
     (g) si la base NO contesta, la pantalla lo dice (chip DEMO) en vez de
         mostrar cero — regla "una lectura ROTA no es un CERO".
   Sale 1 si falla. */
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
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    window.alert = function () {}; window.confirm = function () { return true; };
    window.__isSupervisor = true; window.requireSupervisor = function () { return true; };

    const clientes = [
      { empresa: "lk",   cod_cliente: "4045", cliente: "Bazar Monica S. CAP I SECC IV", deuda: 108058.30, vencida: 0,
        comprobantes_abiertos: 1, dias_mas_vieja: 59, ultimo_pago: "2026-09-28", ultimo_pago_monto: 472524.71,
        a_reclamar: 108058.30, ret_cliente: 0, agente_retencion: false, ancla: "2026-09-29T10:00:00Z" },
      { empresa: "chef", cod_cliente: "2211", cliente: "Bazar Monica SRL", deuda: 331020, vencida: 120400,
        comprobantes_abiertos: 3, dias_mas_vieja: 41, ultimo_pago: "2026-09-12", ultimo_pago_monto: 250000,
        a_reclamar: 0, ret_cliente: 0.021, agente_retencion: false, ancla: "2026-09-29T10:00:00Z" },
      { empresa: "lk",   cod_cliente: "288", cliente: "Torres Y Liva S.A Cif", deuda: 44999903, vencida: 13435258,
        comprobantes_abiertos: 11, dias_mas_vieja: 53, ultimo_pago: "2026-09-18", ultimo_pago_monto: 5693184.16,
        a_reclamar: 38405798, ret_cliente: 0.021, agente_retencion: false, ancla: "2026-09-29T10:00:00Z" }
    ];
    const comp = [
      { orden: "2026-07-24", fecha: "2026-07-24", comprobantes: "FCA 0004-00035292", facturado: 1080583.02,
        pendiente: 108058.31, estado: "mal", pago_recibo: "14601", pago_fecha: "2026-09-28", pago_monto: 972524.71,
        dias: 59, dto_tomado: 0.10, dto_ganado: 0.10, retencion: 0, a_reclamar: 108058.30,
        explicacion: "Ponderado da 59 dias: le corresponde -10 %." }
    ];
    const cta = [
      { fecha: "2026-07-24", tipo: "Factura", comprobante: "FC A 35292", condicion: "Contado -25%", debe: 1080583.02, haber: 0, saldo: 1080583.02, detalle: null }
    ];

    const calls = [];
    const ok = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o), headers: { get: () => null } });
    window.fetch = async (url, opt) => {
      const u = String(url), m = /\/rpc\/([a-z_]+)/.exec(u);
      if (m) {
        calls.push(m[1]);
        if (m[1] === "gv_cobranza_clientes") return ok(clientes);
        if (m[1] === "gv_cobranza_clientes_cuit") return ok([
          { empresa: "lk", cod_cliente: "4045", cuit: "30712345678" },
          { empresa: "chef", cod_cliente: "2211", cuit: "30712345678" },
          { empresa: "lk", cod_cliente: "288", cuit: "30556677889" }
        ]);
        if (m[1] === "gv_cobranza_cliente") {
          const body = JSON.parse((opt && opt.body) || "{}");
          return ok(body.p_empresa === "lk" ? comp : []);
        }
        if (m[1] === "gv_cobranza_cuenta") return ok(cta);
        return ok([]);
      }
      if (/cobranzas_escalones/.test(u)) return ok([]);   // cae al fallback local
      return ok([]);
    };

    await openCobranzas();
    await espera(350);

    const ov = document.getElementById("cbzOv");
    out.abre = !!ov && ov.style.display === "flex";
    out.pestanas = Array.from(document.querySelectorAll("#cbzTabs .cbz-tab")).map((x) => x.textContent.trim());
    out.tabActiva = (document.querySelector("#cbzTabs .cbz-tab.on") || {}).textContent || "";
    out.pidio = calls.slice();

    // (b) + (c) consolidación
    const filas = Array.from(document.querySelectorAll("#cbzLista .cbz-row"));
    out.nFilas = filas.length;
    out.orden = filas.map((f) => f.querySelector(".nom").textContent.trim());
    const bazar = filas.filter((f) => /Bazar Monica/i.test(f.textContent));
    out.bazarFilas = bazar.length;
    out.bazarChips = bazar.length ? Array.from(bazar[0].querySelectorAll(".cbz-chip")).map((c) => c.textContent.trim()) : [];
    out.bazarDeuda = bazar.length ? bazar[0].querySelectorAll(".cbz-cel")[0].textContent : "";

    // (d) búsqueda por código de Chef, del cliente que en LK tiene otro código
    cbzBuscar("2211");
    await espera(60);
    out.buscaCod = Array.from(document.querySelectorAll("#cbzLista .cbz-row")).map((f) => f.querySelector(".nom").textContent.trim());
    cbzBuscar("30712345678");
    await espera(60);
    out.buscaCuit = Array.from(document.querySelectorAll("#cbzLista .cbz-row")).map((f) => f.querySelector(".nom").textContent.trim());
    cbzBuscar("torres");
    await espera(60);
    out.buscaNom = Array.from(document.querySelectorAll("#cbzLista .cbz-row")).map((f) => f.querySelector(".nom").textContent.trim());
    cbzBuscar("");
    await espera(60);

    // (e) ficha
    const fila = Array.from(document.querySelectorAll("#cbzLista .cbz-row")).filter((f) => /Bazar Monica/i.test(f.textContent))[0];
    if (!fila) { out.fichaErr = "no encontré el renglón de Bazar Monica"; return out; }
    fila.click();
    await espera(350);
    const kpis = Array.from(document.querySelectorAll(".cbz-kpi")).map((k) => ({
      k: (k.querySelector(".k") || {}).textContent || "", v: (k.querySelector(".v") || {}).textContent || ""
    }));
    out.kpiDeuda = (kpis.filter((x) => /Deuda total/i.test(x.k))[0] || {}).v || "";
    out.kpiSub = (document.querySelector(".cbz-kpi .s") || {}).textContent || "";
    out.desglose = Array.from(document.querySelectorAll(".cbz-dcard")).map((d) => d.textContent.replace(/\s+/g, " ").trim());
    out.subTabs = Array.from(document.querySelectorAll(".cbz-sub button")).map((x) => x.textContent.trim());
    out.compFilas = document.querySelectorAll("#cbzPanel table.cbz-t tbody tr").length;
    out.compTexto = (document.getElementById("cbzPanel") || {}).textContent || "";

    // (f) explicación + escala
    const tr = document.querySelector("#cbzPanel tr.cbz-clic");
    if (tr) { tr.click(); await espera(120); }
    const exp = document.querySelector("#cbzPanel .cbz-exp");
    out.explica = exp ? exp.textContent.replace(/\s+/g, " ").trim() : "";
    out.escalones = Array.from(document.querySelectorAll("#cbzPanel .cbz-esc")).length;
    const on = document.querySelector("#cbzPanel .cbz-esc.on");
    out.escalonMarcado = on ? on.textContent.replace(/\s+/g, " ").trim() : "";

    // cuenta corriente
    cbzSub("cta"); await espera(250);
    out.ctaFilas = document.querySelectorAll("#cbzPanel table.cbz-t tbody tr").length;

    // (g) la base no contesta -> tiene que decirlo, no mostrar cero
    window.fetch = async () => { throw new Error("red caida"); };
    cbzVolver();
    await cbzCargarClientes();
    await espera(200);
    out.demoChip = /DEMO/.test((document.getElementById("cbzWrap") || {}).textContent || "");
    out.demoFilas = document.querySelectorAll("#cbzLista .cbz-row").length;
    return out;
  });

  await b.close();

  const fallas = [];
  const q = (c, m) => { if (!c) fallas.push(m); };

  q(r.abre, "(a) openCobranzas no abrió el overlay");
  q(r.pestanas && r.pestanas.length === 4, "(a) esperaba 4 pestañas, hay " + JSON.stringify(r.pestanas));
  q(/Clientes/.test(r.tabActiva || ""), "(a) no arranca en la pestaña Clientes (arrancó en " + r.tabActiva + ")");
  q((r.pidio || []).indexOf("gv_cobranza_clientes") >= 0, "(a) no pidió gv_cobranza_clientes");

  q(r.nFilas === 2, "(c) esperaba 2 renglones (Bazar consolidado + Torres), hay " + r.nFilas);
  q(r.bazarFilas === 1, "(c) Bazar Monica aparece " + r.bazarFilas + " veces: LK y CH no se consolidaron");
  q((r.bazarChips || []).some((c) => /LK 4045/.test(c)) && (r.bazarChips || []).some((c) => /CH 2211/.test(c)),
    "(c) la fila consolidada no muestra los dos códigos: " + JSON.stringify(r.bazarChips));
  q(/439\.078/.test(r.bazarDeuda || ""), "(c) la deuda consolidada no es la suma 108.058,30 + 331.020 = 439.078 — dice " + JSON.stringify(r.bazarDeuda));
  q((r.orden || [])[0] && /Torres/i.test(r.orden[0]), "(b) no está ordenado por deuda mayor → menor: " + JSON.stringify(r.orden));

  q((r.buscaCod || []).length === 1 && /Bazar/i.test(r.buscaCod[0] || ""),
    "(d) buscar el código de Chef 2211 no trajo a Bazar Monica: " + JSON.stringify(r.buscaCod));
  q((r.buscaCuit || []).length === 1 && /Bazar/i.test(r.buscaCuit[0] || ""),
    "(d) buscar por CUIT no trajo al cliente: " + JSON.stringify(r.buscaCuit));
  q((r.buscaNom || []).length === 1 && /Torres/i.test(r.buscaNom[0] || ""),
    "(d) buscar por nombre no filtró: " + JSON.stringify(r.buscaNom));

  q(!r.fichaErr, "(e) " + r.fichaErr);
  q(/439\.078/.test(r.kpiDeuda || ""), "(e) el KPI de deuda total no trae la consolidada: " + JSON.stringify(r.kpiDeuda));
  q(/consolidada/i.test(r.kpiSub || ""), "(e) el KPI no aclara que la deuda es consolidada");
  q((r.desglose || []).length === 2, "(e) falta el desglose por empresa (hay " + (r.desglose || []).length + ")");
  q((r.subTabs || []).length === 3, "(e) la ficha no tiene las 3 sub-pestañas: " + JSON.stringify(r.subTabs));
  q(/35292/.test(r.compTexto || ""), "(e) la ficha no muestra el comprobante del cliente");
  q(/972\.525|972\.524/.test(r.compTexto || ""), "(e) la ficha no muestra lo pagado");

  q(/59 dias|59 días/.test(r.explica || ""), "(f) al tocar el comprobante no salió la explicación: " + JSON.stringify(r.explica));
  q(r.escalones === 6, "(f) la escala no tiene los 6 escalones (tiene " + r.escalones + ")");
  q(/46 a 60/.test(r.escalonMarcado || ""), "(f) con 59 días el escalón marcado tendría que ser '46 a 60 días', es " + JSON.stringify(r.escalonMarcado));

  q(r.ctaFilas >= 1, "(e) la cuenta corriente quedó vacía");

  q(r.demoChip, "(g) con la base caída no avisa: un cero no puede confundirse con 'no pude leer'");
  q(r.demoFilas > 0, "(g) con la base caída la lista quedó vacía sin explicación");

  if (errs.length) fallas.push("errores de JS en la página: " + errs.join(" | "));

  if (fallas.length) {
    console.log("cbz-ficha-cliente: FALLA");
    fallas.forEach((f) => console.log("  - " + f));
    process.exit(1);
  }
  console.log("cbz-ficha-cliente: OK — 4 pestañas, LK+CH consolidados (439.078), búsqueda por código y por nombre, ficha con desglose, escalón 46-60 marcado a los 59 días, y aviso DEMO con la base caída.");
  process.exit(0);
})();
