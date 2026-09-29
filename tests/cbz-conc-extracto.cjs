/* v24.37 — Conciliación: carga del extracto del día + motor de cruce (Luis, 29/09):
   "el módulo debería resolver automáticamente todo lo que pueda con la carga de los extractos
   de movimientos por día y consultarle al humano por las cosas que no puede cuadrar".

   Corre la pantalla de verdad (index.html + cobranzas.js) con la base mockeada y mide:
     (a) el LECTOR del extracto: Santander trae "(2.070,00)" (débito entre paréntesis, es-AR) y dos
         bloques que se pisan -> sin duplicar; Credicoop trae Débito/Crédito en columnas;
     (b) un extracto de OTRO banco que la cuenta elegida no se carga;
     (c) la carga llama a gv_conc_extracto_cargar y después al motor DE A 15 (32 ids = 3 lotes);
     (d) ❓ preguntas: una tarjeta por movimiento, ordenadas por plata, con los candidatos, el
         teléfono y el chip de provincia; «Es este» llama a gv_conc_resolver con ese código;
     (e) 🟡 propuestos: «Confirmar los N» manda los N ids a gv_conc_confirmar;
     (f) el copiado para la planilla sale en 10 columnas (A–J) y el Nº de recibo NO se inventa.
   v24.41: el extracto de una cuenta vive en el POP-UP del banco (pestaña «🏦 Extracto cargado»),
   no en la pantalla principal: acá se abre el pop-up de Santander CH y se mide ahí adentro.
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
  const ctx = await b.newContext({ viewport: { width: 1400, height: 900 }, serviceWorkers: "block" });
  const p = await ctx.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {}; const calls = [];
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    window.alert = function () {}; window.requireSupervisor = function () { return true; };

    /* (a) lector */
    const sant = [
      ["Movimientos del Día"], ["Fecha", "Suc. Origen", "Desc. Sucursal", "Cod. Operativo", "Referencia", "Concepto", "Importe", "Saldo"],
      ["29/09/2026", "0749", "Agronomía", "3253", "000064213", "Iva percepcion rg 2408", "(2.070,00)", null],
      ["25/09/2026", "0501", "Rosario - Paseo del Siglo", "2030", "8910", "Deposito de efectivo en sucursal", "693.000,00", "15.042.821,15"],
      ["Últimos Movimientos"], ["Fecha", "Suc. Origen", "Desc. Sucursal", "Cod. Operativo", "Referencia", "Concepto", "Importe", "Saldo"],
      ["29/09/2026", "0749", "Agronomía", "3253", "000064213", "Iva percepcion rg 2408", "(2.070,00)", null],
      ["24/09/2026", "0749", "Agronomía", "3036", "64149", "Deposito e-cheq 48hs presencia bsr", "450.225,96", "38.504.100,32"]
    ];
    const ps = cbzCcParse(sant);
    out.sBanco = ps.banco; out.sN = ps.movs.length;
    out.sIva = ps.movs.filter((m) => m.codop === "3253")[0] || null;
    out.sEfec = ps.movs.filter((m) => m.codop === "2030")[0] || null;
    const credi = [
      [null, "Fecha", "Concepto", "Nro.Cpbte.", "Débito", "Crédito", "Saldo", "Cód.", null],
      [null, "28/09/2026", "IVA - Alicuota Inscripto", "0", "126", "0", "41404520.43", "IVA08", null],
      [null, "28/09/2026", "Credito Inmediato (DEBIN) dist titular 30718101243-VAR-BAZAR MONICA", "80009", "0", "472524.71", "42560851.62", "1874", null]
    ];
    const pc = cbzCcParse(credi);
    out.cBanco = pc.banco; out.cN = pc.movs.length;
    out.cCred = pc.movs.filter((m) => m.credito > 0)[0] || null;

    const cand = (cod, cli, sc, fc, geo, prov) => ({ cod, cliente: cli, facturas: fc, dias: 11, lista: 1, dto: 0.25, retencion: 0, score: sc, via: "importe", geo, provincia: prov ? [prov] : null });
    const movs = [
      { id: 11, banco: "santander", empresa: "chef", fecha: "2026-09-25", concepto: "Deposito de efectivo en sucursal", sucursal: "Rosario - Paseo del Siglo",
        credito: 693000, debito: 0, estado: "propuesto", metodo: "importe", cod_cliente: "2448", detalle: "SARALI SA", det: "D", operacion: "Deposito",
        candidatos: { lista: [cand("2448", "SARALI SA", 0, "5563", "misma", "Santa Fe"), cand("2469", "AMBROSIO", 0.0102, "5554", "misma", "Santa Fe")] } },
      { id: 12, banco: "santander", empresa: "chef", fecha: "2026-09-25", concepto: "Deposito de efectivo en sucursal", sucursal: "Rio Cuarto",
        credito: 1096000, debito: 0, estado: "propuesto", metodo: "importe", cod_cliente: "2466", detalle: "ELBANTONIO", det: "D", operacion: "Deposito",
        candidatos: { lista: [cand("2466", "ELBANTONIO", 0, "5564+5565", "misma", "Córdoba")] } },
      { id: 13, banco: "santander", empresa: "chef", fecha: "2026-09-10", concepto: "Transferencia recibida - De dealbera, mario albert / - fac / 20278713017",
        cuit: "20278713017", nombre_banco: "dealbera, mario albert", credito: 1290068.34, debito: 0, estado: "pregunta", det: "1", operacion: "Transf",
        alerta: "el CUIT 20278713017 no tiene codigo en CHEF: paga un tercero o falta el alta",
        candidatos: { lista: [cand("1463", "SERPA", 0.0117, "5535"), cand("2677", "MARDO MAYORISTA", 0.0243, "5501")] } },
      { id: 14, banco: "santander", empresa: "chef", fecha: "2026-09-24", concepto: "Deposito de efectivo en sucursal", sucursal: "Cordoba",
        credito: 20600, debito: 0, estado: "pregunta", det: "1", operacion: "Deposito", alerta: "sin CUIT y ningun importe de factura impaga lo explica", candidatos: { lista: [] } },
      { id: 15, banco: "santander", empresa: "chef", fecha: "2026-09-02", concepto: "Transferencia recibida - De renatek srl", cuit: "30714507857",
        credito: 226201.02, debito: 0, estado: "auto", metodo: "cuit", cod_cliente: "2128", detalle: "RENATEK SRL", det: "D", operacion: "Transf", nro_recibo: null, es_cobranza: true },
      { id: 16, banco: "santander", empresa: "chef", fecha: "2026-09-29", concepto: "Iva percepcion rg 2408", credito: 0, debito: 2070, estado: "auto", metodo: "regla",
        detalle: "Gastos", det: "G", operacion: "Gastos" }
    ];
    const body = (opt) => { try { return JSON.parse((opt && opt.body) || "{}"); } catch (_e) { return {}; } };
    const ok = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o), headers: { get: () => null } });
    window.fetch = async (url, opt) => {
      const u = String(url), m = /\/rpc\/([a-z_]+)/.exec(u);
      if (m) {
        calls.push({ fn: m[1], args: body(opt) });
        if (m[1] === "gv_conc_movs") return ok(movs);
        if (m[1] === "gv_conc_extracto_cargar") return ok({ carga_id: 1, movimientos: 34, nuevos: 32, ids: Array.from({ length: 32 }, (_, i) => 100 + i) });
        if (m[1] === "gv_conc_motor") return ok([{ estado: "auto", n: 1 }]);
        if (m[1] === "gv_conc_resolver") return ok({ id: 13, estado: "confirmado", cliente: "MARDO MAYORISTA", alias: true });
        if (m[1] === "gv_conc_confirmar") return ok(2);
        if (m[1] === "gv_cliente_nuevo_wpp_lote") return ok([{ empresa: "chef", cod: "2448", telefono: "5493415551234", origen: "padron_empresa" }]);
        return ok([]);
      }
      return ok([]);
    };

    await openCobranzas("conc");
    cbzCcPopAbrir("santander|chef");
    cbzCcPopTab("extracto");
    await espera(500);
    out.filtroInicial = ((document.querySelector("#cbzPop .cbz-ccest button.on") || {}).textContent || "").trim();
    out.preguntas = Array.from(document.querySelectorAll("#cbzPop .cbz-q .cbz-qimp")).map((x) => x.textContent.trim());
    out.textoPreg = (document.getElementById("cbzPop") || {}).textContent || "";

    /* (d) Es este -> resolver con el código y el recordar */
    const rec = document.getElementById("cbzRec13"); if (rec) rec.checked = true;
    const btn = Array.from(document.querySelectorAll("#cbzPop .cbz-q .cbz-es")).filter((x) => /cbzCcResolver\(13,'2677'\)/.test(x.getAttribute("onclick") || ""))[0];
    out.hayBoton = !!btn;
    if (btn) btn.click();
    await espera(400);
    out.resolver = calls.filter((c) => c.fn === "gv_conc_resolver").map((c) => c.args)[0] || null;

    /* (e) propuestos */
    cbzCcFiltro("propuesto"); await espera(300);
    out.textoProp = (document.getElementById("cbzPop") || {}).textContent || "";
    out.telefono = !!document.querySelector('#cbzPop .cbz-q a[href^="https://wa.me/5493415551234"]');
    const conf = Array.from(document.querySelectorAll("#cbzPop .cbz-ccest .cbz-conf"))[0];
    out.hayConfirmar = conf ? conf.textContent.trim() : "";
    if (conf) conf.click();
    await espera(400);
    out.confirmar = calls.filter((c) => c.fn === "gv_conc_confirmar").map((c) => c.args)[0] || null;

    /* (f) export */
    const tsv = cbzCcTsv().split("\n");
    out.tsvN = tsv.length;
    out.tsvCols = tsv.map((l) => l.split("\t").length);
    out.tsvRenatek = tsv.filter((l) => /RENATEK/.test(l))[0] || "";
    out.tsvDudoso = tsv.filter((l) => /1290068,34/.test(l))[0] || "";

    /* (b) otro banco: con Credicoop elegido, un extracto de Santander no se carga */
    cbzCcSetCuenta("credicoop|lk"); await espera(300);
    const antes = calls.length;
    const ok2 = await (async () => {
      const f = new File(["x"], "descargaUltimosMovimientos.xls");
      window.XLSX = { read: () => ({ SheetNames: ["h"], Sheets: { h: {} } }), utils: { sheet_to_json: () => sant } };
      await cbzCcArchivo({ files: [f], value: "" });
      return calls.slice(antes).filter((c) => c.fn === "gv_conc_extracto_cargar").length === 0 && /SANTANDER/.test(_cbz.cc.msg);
    })();
    out.otroBanco = ok2;

    /* (c) carga + motor de a 15 */
    const antes2 = calls.length;
    await cbzCcCargarMovs("extracto.xls", pc.movs);
    await espera(400);
    const tras = calls.slice(antes2);
    out.cargo = tras.filter((c) => c.fn === "gv_conc_extracto_cargar").length;
    out.lotes = tras.filter((c) => c.fn === "gv_conc_motor").map((c) => (c.args.p_ids || []).length);
    out.msg = _cbz.cc.msg;
    return out;
  });

  await b.close();
  const fallas = [];
  const q = (c, m) => { if (!c) fallas.push(m); };

  q(r.sBanco === "santander" && r.sN === 3, "(a) Santander: esperaba 3 movimientos (dos bloques, sin duplicar), leí " + r.sN + " de " + r.sBanco);
  q(r.sIva && r.sIva.debito === 2070 && r.sIva.credito === 0, "(a) «(2.070,00)» es un DÉBITO de 2.070, salió " + JSON.stringify(r.sIva));
  q(r.sEfec && r.sEfec.credito === 693000 && /Rosario/.test(r.sEfec.sucursal) && r.sEfec.saldo === 15042821.15, "(a) efectivo Santander mal leído: " + JSON.stringify(r.sEfec));
  q(r.cBanco === "credicoop" && r.cN === 2, "(a) Credicoop: esperaba 2 movimientos, leí " + r.cN + " de " + r.cBanco);
  q(r.cCred && r.cCred.credito === 472524.71 && r.cCred.codop === "1874" && r.cCred.referencia === "80009", "(a) crédito Credicoop mal leído: " + JSON.stringify(r.cCred));

  q(r.otroBanco, "(b) un extracto de Santander con la cuenta Credicoop elegida NO se tiene que cargar, y avisar");

  q(r.cargo === 1, "(c) la carga tiene que llamar una vez a gv_conc_extracto_cargar, llamó " + r.cargo);
  q(JSON.stringify(r.lotes) === "[15,15,2]", "(c) el motor va de a 15 (32 ids = 15+15+2), fue " + JSON.stringify(r.lotes));

  q(/Preguntas/.test(r.filtroInicial), "(d) con preguntas pendientes la pantalla abre en ❓ Preguntas, abrió en " + r.filtroInicial);
  q(JSON.stringify(r.preguntas) === JSON.stringify(["$ 1.290.068,34", "$ 20.600"]), "(d) preguntas ordenadas por plata, mayor → menor: " + JSON.stringify(r.preguntas));
  q(/MARDO MAYORISTA/.test(r.textoPreg) && /20278713017/.test(r.textoPreg), "(d) la pregunta tiene que mostrar los candidatos y el CUIT");
  q(r.hayBoton && r.resolver && r.resolver.p_id === 13 && r.resolver.p_cod === "2677" && r.resolver.p_recordar === true,
    "(d) «Es este» tiene que llamar gv_conc_resolver(13, '2677', recordar=true): " + JSON.stringify(r.resolver));

  q(/Santa Fe/.test(r.textoProp), "(e) el propuesto tiene que mostrar la pista de provincia (📍 Santa Fe)");
  q(r.telefono, "(e) el candidato con teléfono tiene que tener su link de WhatsApp");
  q(/Confirmar los 2/.test(r.hayConfirmar), "(e) falta «Confirmar los 2 propuestos»: " + r.hayConfirmar);
  q(r.confirmar && JSON.stringify(r.confirmar.p_ids) === "[11,12]", "(e) confirmar tiene que mandar [11,12]: " + JSON.stringify(r.confirmar));

  q(r.tsvN === 6 && r.tsvCols.every((n) => n === 10), "(f) el copiado sale en 10 columnas A–J, una fila por movimiento: " + JSON.stringify(r.tsvCols));
  q(/^02\/09\/2026\tTransf\t226201,02\t\t\tRENATEK SRL\tD\t\t\t2128$/.test(r.tsvRenatek), "(f) fila de Renatek mal armada (el recibo tiene que ir VACÍO): " + JSON.stringify(r.tsvRenatek));
  q(/\tNo Identificado\t/.test(r.tsvDudoso), "(f) una pregunta sin resolver sale como «No Identificado»: " + JSON.stringify(r.tsvDudoso));

  if (errs.length) fallas.push("errores de JS en la página: " + errs.join(" | "));
  if (fallas.length) { console.log("cbz-conc-extracto: FALLA"); fallas.forEach((f) => console.log("  - " + f)); process.exit(1); }
  console.log("cbz-conc-extracto: OK — lee Santander (paréntesis, dos bloques) y Credicoop, no carga el banco equivocado, " +
    "cruza de a 15, las preguntas salen por plata con candidatos y teléfono, confirma los propuestos y copia A–J sin inventar recibos.");
  process.exit(0);
})();
