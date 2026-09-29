/* v24.3 — Submódulo Cobranzas: búsqueda de cliente + ficha integrada.
   Luis, 29/09: "pestañas dentro, empezando con la de búsqueda de clientes … una ficha
   con deuda consolidada" y después "tenemos la data de la deuda que se sube para la
   cuarentena, tenés acceso a la facturación y a la conciliación: conectá esas fuentes
   a la ficha".

   Corre la pantalla de verdad (no es un candado de texto) y mide:
     (a) openCobranzas abre, 4 pestañas, arranca en Clientes y pide la lista;
     (b) la lista sale ordenada por deuda, mayor → menor;
     (c) el MISMO cliente con código en LK y en CH aparece UNA vez, consolidado por CUIT;
     (d) busca por código, por nombre y por CUIT;
     (e) la ficha pide gv_cobranza_ficha UNA vez por código y suma los dos: los KPI
         salen de ahí (deuda viva), no de la lista;
     (f) las 5 sub-pestañas traen su fuente — Deuda (Excel de Cuarentena + ISIS −
         banco), Pagos (conciliación imputada: dto tomado vs ganado, a reclamar),
         Entregas (Facturacion_NP), Explicación (con la escala y el escalón marcado)
         y Cuenta corriente;
     (h) v24.41: la ficha ABRE en «📋 Resumen», la planilla de cobranza del Excel: facturas,
         pagos con su ponderación, días ponderados (59), la escala con el escalón marcado y la
         NC de descuento que falta, partida en neto e IVA; la deuda abierta va primero;
     (i) v24.41: cambiar a Conciliación y volver NO cierra el cliente (Luis: "debería quedarse
         en el cliente que elegí");
     (g) si la base NO contesta, la pantalla lo dice (chip DEMO) en vez de mostrar cero
         — regla "una lectura ROTA no es un CERO".
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
  // el SW navega la ventana la primera vez en un origen (flag "forzado-v2370"): bloqueado,
  // como en vendor-sin-cdn, para que no mate un evaluate a mitad de camino
  const ctx = await b.newContext({ viewport: { width: 1500, height: 900 }, serviceWorkers: "block" });
  const p = await ctx.newPage();
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
      { empresa: "lk",   cod_cliente: "4045", cliente: "Bazar Monica S. CAP I SECC IV", deuda: 108058.30, vencida: 108058.30,
        comprobantes_abiertos: 1, dias_mas_vieja: 67, ultimo_pago: "2026-09-28", ultimo_pago_monto: 472524.71,
        a_reclamar: 108058.30, ret_cliente: 0, agente_retencion: false, ancla: "2026-09-28T11:59:00Z" },
      { empresa: "chef", cod_cliente: "2211", cliente: "Bazar Monica SRL", deuda: 331020, vencida: 120400,
        comprobantes_abiertos: 3, dias_mas_vieja: 41, ultimo_pago: "2026-09-12", ultimo_pago_monto: 250000,
        a_reclamar: 0, ret_cliente: 0.021, agente_retencion: false, ancla: "2026-09-28T11:59:00Z" },
      { empresa: "lk",   cod_cliente: "288", cliente: "Torres Y Liva S.A Cif", deuda: 44999903, vencida: 13435258,
        comprobantes_abiertos: 11, dias_mas_vieja: 53, ultimo_pago: "2026-09-18", ultimo_pago_monto: 5693184.16,
        a_reclamar: 38405798, ret_cliente: 0.021, agente_retencion: false, ancla: "2026-09-28T11:59:00Z" }
    ];
    const fichaLK = {
      cabecera: { empresa: "lk", cod: "4045", cliente: "Bazar Monica S. CAP I SECC IV", cuit: "30712345678",
                  localidad: "San Isidro", provincia: "Buenos Aires", ret_cliente: 0, agente_retencion: false },
      totales: { deuda: 108058.31, vencida: 108058.31, comprobantes: 1, dias_mas_vieja: 67, ancla: "2026-09-28T11:59:00Z" },
      deuda: [{ comprobante: "FCA 0004-00035292", fecha: "2026-07-24", vence: "2026-09-22", condicion: "Pago Contado -25%",
                dto_cond: 0.25, lista: 1080583.02, pendiente_ancla: 108058.31, cancelado_banco: 972524.71,
                pendiente: 108058.31, origen: "excel", recibos_banco: "14588+14601", dias: 67, vencido: true }],
      recibos: [{ recibo: "14601", fecha_pago: "2026-09-28", medio: "transferencia", pagado: 472524.71, facturas: "35292",
                  lista: 1080583.02, nc: null, dias: 66, dto_tomado: 0.10, dto_ganado: 0.10, retencion: 0,
                  a_reclamar: 0, calidad: "exacta", plazo: 60, atraso: 6 }],
      entregas: [{ np: "LK 0122", tanda: "E30A", fecha_salida: "2026-09-29", m3: 3.119, facturado_at: "2026-09-28" }]
    };
    const fichaCH = {
      cabecera: { empresa: "chef", cod: "2211", cliente: "Bazar Monica SRL", cuit: "30712345678" },
      totales: { deuda: 331020, vencida: 120400, comprobantes: 3, dias_mas_vieja: 41, ancla: "2026-09-28T11:59:00Z" },
      deuda: [{ comprobante: "FCA 0003-00012190", fecha: "2026-09-02", vence: "2026-09-16", condicion: "Pago Contado -25%",
                dto_cond: 0.25, lista: 120400, pendiente_ancla: 120400, cancelado_banco: 0, pendiente: 120400,
                origen: "isis nuevo", recibos_banco: null, dias: 27, vencido: true }],
      recibos: [{ recibo: "9822", fecha_pago: "2026-09-12", medio: "e-cheque", pagado: 250000, facturas: "11980",
                  lista: 333333, nc: "1042", dias: 31, dto_tomado: 0.25, dto_ganado: 0.15, retencion: 0.021,
                  a_reclamar: 33333, calidad: "exacta", plazo: 30, atraso: 1 }],
      entregas: [{ np: "CH 0044", tanda: "E12B", fecha_salida: "2026-09-11", m3: 0.842, facturado_at: "2026-09-10" }]
    };
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
        const body = JSON.parse((opt && opt.body) || "{}");
        calls.push(m[1] + (body.p_emp ? ":" + body.p_emp : ""));
        if (m[1] === "gv_cobranza_clientes") return ok(clientes);
        if (m[1] === "gv_cobranza_clientes_cuit") return ok([
          { empresa: "lk", cod_cliente: "4045", cuit: "30712345678" },
          { empresa: "chef", cod_cliente: "2211", cuit: "30712345678" },
          { empresa: "lk", cod_cliente: "288", cuit: "30556677889" }
        ]);
        if (m[1] === "gv_cobranza_operaciones") return ok(body.p_emp === "lk" ? {
          abiertas: [{ fecha: "2026-09-22", pendiente: 250000, facturas: [{ comprobante: "FC Electr. A 0005-00035986", fecha: "2026-09-22", pendiente: 250000, lista: 250000 }] }],
          pagadas: [{ facturas_txt: "35292", lista: 1080583.02, lista_nc: 0, fecha_fc: "2026-07-24", plazo: null,
            dto_tomado: 0.10, dto_ganado: 0.10, retencion: 0, a_reclamar: 0, calidad: "exacta",
            facturas: [{ tipo: "FC Electr. A", numero: "35292", fecha: "2026-07-24", total: 1080583.02 }], ncs: [],
            pagos: [{ recibo: "14588", fecha: "2026-09-15", pagado: 500000, medio: "deposito", dias: 53, grupos: 1 },
                    { recibo: "14601", fecha: "2026-09-28", pagado: 472524.71, medio: "transferencia", dias: 66, grupos: 1 }] }]
        } : { abiertas: [], pagadas: [] });
        if (m[1] === "gv_cobranza_ficha")   return ok(body.p_emp === "lk" ? fichaLK : fichaCH);
        if (m[1] === "gv_cobranza_cliente") return ok(body.p_emp === "lk" ? comp : []);
        if (m[1] === "gv_cobranza_cuenta")  return ok(cta);
        return ok([]);
      }
      if (/cobranzas_escalones/.test(u)) return ok([]);   // cae al fallback local
      return ok([]);
    };

    await openCobranzas();
    await espera(400);

    const ov = document.getElementById("cbzOv");
    out.abre = !!ov && ov.style.display === "flex";
    out.pestanas = Array.from(document.querySelectorAll("#cbzTabs .cbz-tab")).map((x) => x.textContent.trim());
    out.tabActiva = (document.querySelector("#cbzTabs .cbz-tab.on") || {}).textContent || "";
    out.pidio = calls.slice();

    const filas = Array.from(document.querySelectorAll("#cbzLista .cbz-row"));
    out.nFilas = filas.length;
    out.orden = filas.map((f) => f.querySelector(".nom").textContent.trim());
    const bazar = filas.filter((f) => /Bazar Monica/i.test(f.textContent));
    out.bazarFilas = bazar.length;
    out.bazarChips = bazar.length ? Array.from(bazar[0].querySelectorAll(".cbz-chip")).map((c) => c.textContent.trim()) : [];
    out.bazarDeuda = bazar.length ? bazar[0].querySelectorAll(".cbz-cel")[0].textContent : "";

    cbzBuscar("2211"); await espera(60);
    out.buscaCod = Array.from(document.querySelectorAll("#cbzLista .cbz-row")).map((f) => f.querySelector(".nom").textContent.trim());
    cbzBuscar("30712345678"); await espera(60);
    out.buscaCuit = Array.from(document.querySelectorAll("#cbzLista .cbz-row")).map((f) => f.querySelector(".nom").textContent.trim());
    cbzBuscar("torres"); await espera(60);
    out.buscaNom = Array.from(document.querySelectorAll("#cbzLista .cbz-row")).map((f) => f.querySelector(".nom").textContent.trim());
    cbzBuscar(""); await espera(60);

    const fila = Array.from(document.querySelectorAll("#cbzLista .cbz-row")).filter((f) => /Bazar Monica/i.test(f.textContent))[0];
    if (!fila) { out.fichaErr = "no encontré el renglón de Bazar Monica"; return out; }
    const antes = calls.length;
    fila.click();
    await espera(450);
    out.fichaPidio = calls.slice(antes);

    const kpis = Array.from(document.querySelectorAll(".cbz-kpi")).map((k) => ({
      k: (k.querySelector(".k") || {}).textContent || "", v: (k.querySelector(".v") || {}).textContent || ""
    }));
    out.kpiDeuda = (kpis.filter((x) => /Deuda total/i.test(x.k))[0] || {}).v || "";
    out.kpiVencida = (kpis.filter((x) => /Vencida/i.test(x.k))[0] || {}).v || "";
    out.kpiComprob = (kpis.filter((x) => /Comprob/i.test(x.k))[0] || {}).v || "";
    out.cabecera = (document.querySelector(".cbz-ficha-top") || {}).textContent || "";
    out.desglose = Array.from(document.querySelectorAll(".cbz-dcard")).map((d) => d.textContent.replace(/\s+/g, " ").trim());
    out.subTabs = Array.from(document.querySelectorAll(".cbz-sub button")).map((x) => x.textContent.trim());
    out.subActiva = (document.querySelector(".cbz-sub button.on") || {}).textContent || "";

    const panel = () => (document.getElementById("cbzPanel") || {}).textContent || "";
    await espera(300);
    out.resOps = Array.from(document.querySelectorAll("#cbzPanel .cbz-opi")).map((x) => x.textContent.replace(/\s+/g, " ").trim());
    out.hayPlanilla = !!document.getElementById("cbzPl");
    cbzOpSel(_cbz.ops.ops[1].key); await espera(100);
    out.resTexto = panel();
    out.escOn = ((document.querySelector("#cbzPl .cbz-plesc tr.on") || {}).textContent || "").replace(/\s+/g, " ").trim();
    out.pidioOps = calls.filter((c) => String(c).indexOf("gv_cobranza_operaciones") === 0).length;

    /* (i) Conciliación y vuelta: el cliente sigue abierto */
    cbzSetTab("conc"); await espera(200);
    cbzSetTab("clientes"); await espera(250);
    out.sigueCliente = !!document.getElementById("cbzPl") && /Bazar Monica/i.test((document.getElementById("cbzWrap") || {}).textContent || "");

    cbzSub("deuda"); await espera(300);
    out.deudaFilas = document.querySelectorAll("#cbzPanel table.cbz-t tbody tr").length;
    out.deudaTexto = panel();

    cbzSub("pagos"); await espera(300);
    out.pagosFilas = document.querySelectorAll("#cbzPanel table.cbz-t tbody tr").length;
    out.pagosTexto = panel();

    cbzSub("entregas"); await espera(300);
    out.entregasTexto = panel();

    cbzSub("comp"); await espera(350);
    const tr = document.querySelector("#cbzPanel tr.cbz-clic");
    if (tr) { tr.click(); await espera(150); }
    const exp = document.querySelector("#cbzPanel .cbz-exp");
    out.explica = exp ? exp.textContent.replace(/\s+/g, " ").trim() : "";
    out.escalones = document.querySelectorAll("#cbzPanel .cbz-esc").length;
    const on = document.querySelector("#cbzPanel .cbz-esc.on");
    out.escalonMarcado = on ? on.textContent.replace(/\s+/g, " ").trim() : "";

    cbzSub("cta"); await espera(300);
    out.ctaFilas = document.querySelectorAll("#cbzPanel table.cbz-t tbody tr").length;

    // (g) la base no contesta -> tiene que decirlo, no mostrar cero
    window.fetch = async () => { throw new Error("red caida"); };
    cbzVolver();
    await cbzCargarClientes();
    await espera(250);
    out.demoChip = /DEMO/.test((document.getElementById("cbzWrap") || {}).textContent || "");
    out.demoFilas = document.querySelectorAll("#cbzLista .cbz-row").length;
    return out;
  });

  await b.close();

  const fallas = [];
  const q = (c, m) => { if (!c) fallas.push(m); };

  q(r.abre, "(a) openCobranzas no abrió el overlay");
  q(r.pestanas && r.pestanas.length === 5, "(a) esperaba 5 pestañas, hay " + JSON.stringify(r.pestanas));
  q(/Clientes/.test(r.tabActiva || ""), "(a) no arranca en la pestaña Clientes (arrancó en " + r.tabActiva + ")");
  q((r.pidio || []).indexOf("gv_cobranza_clientes") >= 0, "(a) no pidió gv_cobranza_clientes");

  q(r.nFilas === 2, "(c) esperaba 2 renglones (Bazar consolidado + Torres), hay " + r.nFilas);
  q(r.bazarFilas === 1, "(c) Bazar Monica aparece " + r.bazarFilas + " veces: LK y CH no se consolidaron");
  q((r.bazarChips || []).some((c) => /LK 4045/.test(c)) && (r.bazarChips || []).some((c) => /CH 2211/.test(c)),
    "(c) la fila consolidada no muestra los dos códigos: " + JSON.stringify(r.bazarChips));
  q(/439\.078/.test(r.bazarDeuda || ""), "(c) la deuda consolidada no es la suma 108.058,30 + 331.020 = 439.078 — dice " + JSON.stringify(r.bazarDeuda));
  q((r.orden || [])[0] && /Torres/i.test(r.orden[0]), "(b) no está ordenado por deuda mayor → menor: " + JSON.stringify(r.orden));

  q((r.buscaCod || []).length === 1 && /Bazar/i.test(r.buscaCod[0] || ""), "(d) buscar el código de Chef 2211 no trajo a Bazar Monica: " + JSON.stringify(r.buscaCod));
  q((r.buscaCuit || []).length === 1 && /Bazar/i.test(r.buscaCuit[0] || ""), "(d) buscar por CUIT no trajo al cliente: " + JSON.stringify(r.buscaCuit));
  q((r.buscaNom || []).length === 1 && /Torres/i.test(r.buscaNom[0] || ""), "(d) buscar por nombre no filtró: " + JSON.stringify(r.buscaNom));

  q(!r.fichaErr, "(e) " + r.fichaErr);
  const fichas = (r.fichaPidio || []).filter((c) => c.indexOf("gv_cobranza_ficha") === 0);
  q(fichas.length === 2 && fichas.indexOf("gv_cobranza_ficha:lk") >= 0 && fichas.indexOf("gv_cobranza_ficha:chef") >= 0,
    "(e) la ficha tiene que pedir gv_cobranza_ficha una vez por empresa: " + JSON.stringify(fichas));
  q(/439\.078/.test(r.kpiDeuda || ""), "(e) el KPI de deuda no suma las dos fichas (108.058,31 + 331.020): " + JSON.stringify(r.kpiDeuda));
  q(/228\.458/.test(r.kpiVencida || ""), "(e) el KPI de vencida no suma las dos fichas (108.058,31 + 120.400): " + JSON.stringify(r.kpiVencida));
  q(/^4$/.test((r.kpiComprob || "").trim()), "(e) el KPI de comprobantes no suma los de las dos fichas (1 + 3): " + JSON.stringify(r.kpiComprob));
  q(/30712345678/.test(r.cabecera || ""), "(e) la cabecera no muestra el CUIT que trae la ficha");
  q(/San Isidro/.test(r.cabecera || ""), "(e) la cabecera no muestra la localidad que trae la ficha");
  q(/Cuarentena/i.test(r.cabecera || ""), "(e) la cabecera no dice de dónde sale la deuda (Excel de Cuarentena + ISIS − banco)");
  q((r.desglose || []).length === 2, "(e) falta el desglose por empresa (hay " + (r.desglose || []).length + ")");

  q((r.subTabs || []).length === 6, "(f) esperaba 6 sub-pestañas, hay " + JSON.stringify(r.subTabs));
  q(/Resumen/.test(r.subActiva || ""), "(h) la ficha tiene que abrir en Resumen (arrancó en " + r.subActiva + ")");
  q(r.pidioOps === 2, "(h) Resumen pide gv_cobranza_operaciones una vez por código (2), pidió " + r.pidioOps);
  q(r.hayPlanilla, "(h) Resumen no dibujó la planilla");
  q((r.resOps || []).length === 2 && /35986/.test(r.resOps[0]) && /35292/.test(r.resOps[1]),
    "(h) la deuda abierta va primero y la cobrada después: " + JSON.stringify(r.resOps));
  q(/Días de cobranza\s*59/.test(r.resTexto || ""), "(h) los días ponderados de 35292 son 59 (53 y 66 por lo pagado)");
  q(/Pond/.test(r.resTexto || "") && /27,25/.test(r.resTexto || "") && /32,07/.test(r.resTexto || ""),
    "(h) falta la ponderación de cada pago (53 × 500.000 / 972.524,71 = 27,25 · 66 × 472.524,71 / … = 32,07)");
  q(/NC Dto 10 %/.test(r.resTexto || "") && /108\.058,30/.test(r.resTexto || ""), "(h) falta la NC de descuento del 10 % por $ 108.058,30");
  q(/89\.304,38/.test(r.resTexto || "") && /18\.753,92/.test(r.resTexto || ""), "(h) la NC tiene que partirse en neto 89.304,38 + IVA 18.753,92");
  q(/−10 %/.test(r.escOn || ""), "(h) la escala tiene que marcar el escalón que le tocó (−10 %), marca " + JSON.stringify(r.escOn));
  q(r.sigueCliente, "(i) cambiar a Conciliación y volver tiene que dejar el cliente abierto, no la lista");
  q(r.deudaFilas === 2, "(f) Deuda tendría que traer los 2 comprobantes (uno por empresa), trae " + r.deudaFilas);
  q(/35292/.test(r.deudaTexto || "") && /972\.525/.test(r.deudaTexto || ""),
    "(f) Deuda no muestra el comprobante y lo cobrado por banco (la conciliación)");
  q(/isis nuevo/.test(r.deudaTexto || ""), "(f) Deuda no marca el origen de la factura posterior al Excel");

  q(r.pagosFilas === 2, "(f) Pagos tendría que traer los 2 recibos, trae " + r.pagosFilas);
  q(/33\.333/.test(r.pagosTexto || ""), "(f) Pagos no muestra lo que hay que reclamar por el descuento mal tomado");
  q(/25,0 %/.test(r.pagosTexto || "") && /15,0 %/.test(r.pagosTexto || ""), "(f) Pagos no muestra dto tomado vs dto ganado");

  q(/LK 0122/.test(r.entregasTexto || "") && /E30A/.test(r.entregasTexto || ""), "(f) Entregas no trae la NP facturada y su tanda");
  q(/3,119/.test(r.entregasTexto || ""), "(f) Entregas no muestra los m³");

  q(/59 dias|59 días/.test(r.explica || ""), "(f) al tocar el comprobante no salió la explicación: " + JSON.stringify(r.explica));
  q(r.escalones === 6, "(f) la escala no tiene los 6 escalones (tiene " + r.escalones + ")");
  q(/46 a 60/.test(r.escalonMarcado || ""), "(f) con 59 días el escalón marcado tendría que ser '46 a 60 días', es " + JSON.stringify(r.escalonMarcado));

  q(r.ctaFilas >= 1, "(f) la cuenta corriente quedó vacía");

  q(r.demoChip, "(g) con la base caída no avisa: un cero no puede confundirse con 'no pude leer'");
  q(r.demoFilas > 0, "(g) con la base caída la lista quedó vacía sin explicación");

  if (errs.length) fallas.push("errores de JS en la página: " + errs.join(" | "));

  if (fallas.length) {
    console.log("cbz-ficha-cliente: FALLA");
    fallas.forEach((f) => console.log("  - " + f));
    process.exit(1);
  }
  console.log("cbz-ficha-cliente: OK — LK+CH consolidados por CUIT (439.078), ficha con una llamada por empresa, " +
    "Deuda (Excel Cuarentena + ISIS − banco), Pagos (dto tomado vs ganado, a reclamar), Entregas (NP/tanda/m³), " +
    "explicación con el escalón 46-60 a los 59 días, y aviso DEMO con la base caída.");
  process.exit(0);
})();
