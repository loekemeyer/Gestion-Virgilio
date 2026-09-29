/* v24.04 — CLIENTES NUEVOS: el boton de «cliente de prueba» es ahora 🖨 Imprimir.

   Luis, 29/09: "cambia el boton de cliente de prueba por un boton de imprimir que promptee la
   impresion de un excel ... asegurate de que haya una columna que se llame «Comentarios» que
   tenga todos los comentarios de esa gestion en una celda (bien ordenados, separados y
   visibles)".

   ⚠ Esto se CORRE, no se lee: los comentarios no estan en la pantalla (la tabla solo muestra
     cuantos hay), asi que lo unico que prueba que la celda se arma es ejecutar el export con la
     RPC mockeada y mirar la fila que sale. Sale 1 si falla. */
const path = require("path");
let chromium; try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (e) { try { ({ chromium } = require("playwright")); }
  catch (e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ serviceWorkers: "block" });
  const pg = await ctx.newPage();
  const errs = []; pg.on("pageerror", e => errs.push(String(e)));
  await pg.goto("file://" + path.join(__dirname, "..", "index.html"));
  await pg.waitForTimeout(900);
  const r = await pg.evaluate(async () => {
    const out = {};
    const base = { empresa: "lk", cod: "4286", razon_social: "AUTOSERVICIO CAPO SA",
                   zona: "Zona 1 - CABA Sur", np_total: 2, bloques: [],
                   cuarentena_motivos: ["cliente_nuevo"], cuarentena_detalle: { nuevo_pedidos: 0 } };
    const p1 = Object.assign({}, base, { order_id: "1548", m3: 1.421, fecha_recep: "2026-09-25" });
    const p2 = Object.assign({}, base, { order_id: "1549", m3: 1.051, fecha_recep: "2026-09-25" });
    // 1550 es la parte DIFERIDA de 1549: una sola gestion (v23.06)
    const p3 = Object.assign({}, base, { order_id: "1550", m3: 0.100, fecha_recep: "2026-09-25" });

    _apr.listo = true; _apr.pedidos = [p1, p2, p3]; _apr.pedidosTodos = _apr.pedidos;
    _apr.cuarPartidos = { "lk:1550": "1549" };
    _apr.pipe = {
      "lk:1548": { empresa: "lk", order_id: "1548", etapa: "analisis", reloj_desde: new Date(Date.now() - 3600000).toISOString(), vencido: false },
      "lk:1549": { empresa: "lk", order_id: "1549", etapa: "speech1", reloj_desde: new Date(Date.now() - 90000000).toISOString(), vencido: true, decision_persona: "Vivi" },
      "lk:1550": { empresa: "lk", order_id: "1550", etapa: "speech1" }
    };
    _apr.cliValor = { "lk:1548": { valor: 6433292, valorIva: 7784284, valorImp: 523202, itemsImp: 2 },
                      "lk:1549": { valor: 4888852, valorIva: 5915510, valorImp: 0, itemsImp: 0 },
                      "lk:1550": { valor: 100000, valorIva: 121000, valorImp: 0, itemsImp: 0 } };
    _apr.cliDtoPago = {}; _apr.cliWpp = { "lk:4286": "1140001111" };
    _apr.cliCuit = { "lk:4286": "30685639943" };
    _apr.cuarComN = {}; _apr.pipeDemo = false; _apr.pipeCfg = {}; _apr.pipeStale = false;
    try { localStorage.setItem("vir_cli_colapsado", "0"); } catch (_e) {}

    // (A) la PUERTA: esta Imprimir y ya no esta el cliente de prueba
    const fila = pipeDemoRowHtml();
    out.hayImprimir   = /pipeExportarExcel\(\)/.test(fila);
    out.sinVerEjemplo = !/pipeDemoToggle\(\)/.test(fila) && !/Ver cliente de prueba/.test(fila);
    out.pipeHtmlSinEjemplo = !/Ver cliente de prueba/.test(pipeHtml());

    // (B) el export, con la RPC de comentarios mockeada
    const pedidos = [];
    window.aprRpc = async function (fn, args) {
      if (fn === "gv_cuarentena_comentarios") {
        pedidos.push(String(args.p_empresa) + ":" + String(args.p_order_id));
        if (args.p_order_id === "1548")
          return [{ id: 1, creado_at: "2026-09-26T12:00:00Z", persona: "Vivi", por: "v@x", texto: "Lo llamé, pide plazo" },
                  { id: 2, creado_at: "2026-09-27T15:30:00Z", persona: "Marian", por: "m@x", texto: "Quedó en  pagar\n  el lunes" }];
        if (args.p_order_id === "1549")
          return [{ id: 3, creado_at: "2026-09-28T10:00:00Z", persona: "Vivi", por: "v@x", texto: "Speech 1 enviado" }];
        if (args.p_order_id === "1550")
          return [{ id: 4, creado_at: "2026-09-26T09:00:00Z", persona: "Vivi", por: "v@x", texto: "La parte diferida llega en noviembre" }];
        return [];
      }
      return [];
    };
    let hoja = null, nombre = "";
    window.pppLoadXlsx = async function () {
      return { utils: {
          json_to_sheet: function (f) { hoja = f; return { _f: f }; },
          book_new: function () { return { SheetNames: [], Sheets: {} }; },
          book_append_sheet: function (wb, ws, n) { wb.SheetNames.push(n); wb.Sheets[n] = ws; }
        },
        writeFile: function (wb, n) { nombre = n; } };
    };
    await pipeExportarExcel();
    out.pidioComentarios = pedidos.slice().sort();
    out.nombre = nombre;
    out.filas = hoja ? hoja.length : 0;
    out.cols = hoja && hoja[0] ? Object.keys(hoja[0]) : [];
    const f1548 = (hoja || []).find(function (x) { return String(x["Pedido"]).indexOf("1548") >= 0; });
    const f1549 = (hoja || []).find(function (x) { return String(x["Pedido"]).indexOf("1549") >= 0; });
    out.com1548 = f1548 ? f1548["Comentarios"] : "";
    out.com1549 = f1549 ? f1549["Comentarios"] : "";
    out.pedido1549 = f1549 ? f1549["Pedido"] : "";
    out.m3_1549 = f1549 ? f1549["m3"] : null;
    out.cuit = f1548 ? f1548["CUIT"] : "";
    out.etapa1549 = f1549 ? f1549["Etapa"] : "";
    out.venc1549 = f1549 ? f1549["Vencido"] : "";
    out.neto1548 = f1548 ? f1548["A cobrar (neto)"] : null;
    out.imp1548 = f1548 ? f1548["Importados en falta"] : null;

    // (C) si la lectura de comentarios FALLA, la celda lo dice — no queda vacia
    window.aprRpc = async function (fn) { if (fn === "gv_cuarentena_comentarios") throw new Error("boom"); return []; };
    hoja = null; await pipeExportarExcel();
    out.comError = (hoja && hoja[0]) ? hoja[0]["Comentarios"] : "";
    return out;
  });
  console.log(JSON.stringify(r, null, 1));
  console.log("pageerrors:", errs.length ? errs.slice(0, 2) : "none");
  await b.close();
  const fallos = [];
  const ok = (c, m) => { if (!c) fallos.push(m); };
  ok(r.hayImprimir,          "no esta el boton Imprimir en la fila del submodulo");
  ok(r.sinVerEjemplo,        "sigue la puerta del cliente de prueba");
  ok(r.pipeHtmlSinEjemplo,   "el texto del submodulo sigue mandando a «Ver cliente de prueba»");
  ok(r.filas === 2,          "el pedido partido tiene que ser UNA fila: salieron " + r.filas);
  ok((r.cols || []).indexOf("Comentarios") >= 0, "falta la columna Comentarios");
  ok((r.cols || []).length >= 15, "el Excel salio con pocas columnas: " + (r.cols || []).length);
  ok(/clientes nuevos .*\.xlsx$/.test(r.nombre || ""), "el archivo no se llama como corresponde: " + r.nombre);
  ok((r.pidioComentarios || []).join(",") === "lk:1548,lk:1549,lk:1550",
     "no pidio los comentarios de cada parte: " + (r.pidioComentarios || []).join(","));
  ok(/^1\) 26\/09\/26 .*Vivi: Lo llamé, pide plazo/.test(r.com1548 || ""),
     "el 1.er comentario no sale numerado y fechado: " + r.com1548);
  ok((r.com1548 || "").indexOf("\n2) ") > 0, "los comentarios no van separados en la celda");
  ok(!/\n\s\s/.test(r.com1548 || "") && (r.com1548 || "").indexOf("pagar el lunes") > 0,
     "el salto de linea de adentro de un comentario rompe la celda: " + JSON.stringify(r.com1548));
  ok(/1550/.test(r.pedido1549 || "") && /1549/.test(r.pedido1549 || ""),
     "la fila del partido no nombra sus dos partes: " + r.pedido1549);
  ok((r.com1549 || "").indexOf("LK 1550") > 0 && (r.com1549 || "").indexOf("LK 1549") > 0,
     "los comentarios del partido no dicen de que parte son: " + r.com1549);
  ok(/^1\) 26\/09\/26/.test(r.com1549 || ""), "los comentarios del partido no estan ordenados por fecha: " + r.com1549);
  ok(Math.abs(Number(r.m3_1549) - 1.151) < 0.0005, "el m3 del partido no suma las partes: " + r.m3_1549);
  ok(r.cuit === "30-68563994-3", "el CUIT no sale formateado: " + r.cuit);
  ok(r.etapa1549 === "Esperando pago", "la etapa no sale con su nombre: " + r.etapa1549);
  ok(r.venc1549 === "SI", "el vencido no se marca");
  ok(Number(r.neto1548) === 6433292, "el neto a cobrar no sale: " + r.neto1548);
  ok(Number(r.imp1548) === 523202, "los importados en falta no salen: " + r.imp1548);
  ok(/no se pudieron leer/i.test(r.comError || ""),
     "con la RPC caida la celda queda vacia (una lectura rota no es «sin comentarios»): " + JSON.stringify(r.comError));
  ok(!errs.length, "hubo pageerrors: " + errs.slice(0, 2));
  if (fallos.length) { console.error("FALLA:\n - " + fallos.join("\n - ")); process.exit(1); }
  console.log("pipe-imprimir-excel: OK");
})();
