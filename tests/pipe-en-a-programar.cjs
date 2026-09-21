/* v20.86 — EL PIPELINE REEMPLAZA AL SUBMODULO VIEJO DENTRO DE «A PROGRAMAR».

   Luis, 21/09, las definiciones que lo cierran:
     1. "cuarentena toma prioridad sobre cliente nuevo (ej, un cliente nuevo con deuda pasa
        primero por la cuarentena y despues cuando es liberado... va al modulo de clientes
        nuevos"  -> el pipeline toma SOLO al cliente nuevo puro; el que ademas debe queda en
        Cuarentena. Si los dos modulos tomaran el mismo pedido, apareceria en las dos columnas.
     2. "Agregale zona"
     3. "Despues del analisis solo hay 2 estados: Referenciado y No referenciado"

   ⚠ Esto se corre, no se lee. El candado estatico vive en pipe-clientes-nuevos.cjs; aca se
     dibuja A Programar de verdad y se mira QUE COLUMNA se lleva cada pedido — que es lo unico
     que prueba que no se duplican. Sale 1 si falla. */
const path = require("path");
let chromium; try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (e) { try { ({ chromium } = require("playwright")); }
  catch (e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const pg = await b.newPage();
  const errs = []; pg.on("pageerror", e => errs.push(String(e)));
  await pg.goto("file://" + path.join(__dirname, "..", "index.html"));
  await pg.waitForTimeout(900);
  const r = await pg.evaluate(async () => {
    const out = {};
    window.aprRpc = async function () { return []; };
    // dos pedidos: uno cliente nuevo PURO y otro cliente nuevo CON DEUDA
    const puro = { order_id: "9001", empresa: "lk", cod: "4999", razon_social: "NUEVO PURO SRL",
                   zona: "Zona 3 - CABA Oeste", m3: 0.41, np_total: 1, bloques: [],
                   cuarentena_motivos: ["cliente_nuevo"], cuarentena_detalle: { nuevo_pedidos: 1 } };
    const conDeuda = { order_id: "9002", empresa: "lk", cod: "4998", razon_social: "NUEVO CON DEUDA SA",
                   zona: "Zona 1", m3: 0.22, np_total: 1, bloques: [],
                   cuarentena_motivos: ["deuda", "cliente_nuevo"],
                   cuarentena_detalle: { nuevo_pedidos: 2, deuda: 500000 } };
    _apr.listo = true; _apr.pedidos = [puro, conDeuda]; _apr.pedidosTodos = _apr.pedidos;
    _apr.pipe = {}; _apr.cliValor = {}; _apr.cliWpp = {}; _apr.cuarComN = {};
    _apr.cliCuit = {}; _apr.pipeDemo = false; _apr.pipeCfg = {}; _apr.pipeStale = false;
    try { localStorage.setItem("vir_cli_colapsado", "0"); } catch (_e) {}

    // (a) el pipeline vive DENTRO de A Programar, no en una pestaña propia
    out.pestanaVieja = /b\("clin",/.test(String(pppTabsHtml));
    const pipe = pipeHtml(), cuar = aprColCuarentena();
    out.pipeTieneAlPuro    = pipe.indexOf("NUEVO PURO SRL") >= 0;
    out.pipeTieneAlDeDeuda = pipe.indexOf("NUEVO CON DEUDA SA") >= 0;   // tiene que ser FALSE
    out.cuarTieneAlDeDeuda = cuar.indexOf("NUEVO CON DEUDA SA") >= 0;
    out.cuarTieneAlPuro    = cuar.indexOf("NUEVO PURO SRL") >= 0;       // tiene que ser FALSE

    // (b) la zona, con su badge
    out.zonaEnCabecera = /<th>Zona<\/th>/.test(pipe);
    out.zonaDelPedido  = pipe.indexOf("Zona 3 - CABA Oeste") >= 0;

    // (c) dos estados: No referenciado si, No valido no
    out.botonNoReferenciado = /No referenciado/.test(pipe);
    out.botonReferenciado   = /Referenciado/.test(pipe);
    out.botonNoValido       = /No v[aá]lido/i.test(pipe);               // tiene que ser FALSE
    out.puedeEliminar       = /Eliminar pedido/.test(pipe);

    // (d) colapsable, y la preferencia queda guardada
    out.tieneColapsar = /aprCliColapsar\(\)/.test(pipe);
    aprCliColapsar();
    out.colapsadoGuardado = localStorage.getItem("vir_cli_colapsado") === "1";
    const pipeCol = pipeHtml();
    out.colapsadoNoDibujaLaTabla = pipeCol.indexOf("NUEVO PURO SRL") < 0;
    out.colapsadoSigueContando   = /Clientes nuevos <b>\(1\)<\/b>/.test(pipeCol);
    aprCliColapsar();

    // (e) y la pestaña vieja cae sola en A Programar
    _pppTab = "clin"; try { pppRenderProg(); } catch (_e) { out.err = String(_e); }
    out.pestanaCaeEnProg = _pppTab === "prog";
    return out;
  });
  console.log(JSON.stringify(r, null, 1));
  console.log("pageerrors:", errs.length ? errs.slice(0, 2) : "none");
  await b.close();
  const fallos = [];
  const ok = (c, m) => { if (!c) fallos.push(m); };
  ok(!r.pestanaVieja,       "quedo la pestaña `clin`: el pipeline va dentro de A Programar");
  ok(r.pipeTieneAlPuro,     "el cliente nuevo puro no aparece en el pipeline");
  ok(!r.pipeTieneAlDeDeuda, "el cliente nuevo CON DEUDA cae en el pipeline: se duplica con Cuarentena");
  ok(r.cuarTieneAlDeDeuda,  "el cliente nuevo con deuda no quedo en Cuarentena (cuarentena va primero)");
  ok(!r.cuarTieneAlPuro,    "el cliente nuevo puro quedo tambien en Cuarentena: esta en dos columnas");
  ok(r.zonaEnCabecera,      "falta la columna Zona");
  ok(r.zonaDelPedido,       "la zona del pedido no se dibuja");
  ok(r.botonNoReferenciado, "falta el boton `No referenciado`");
  ok(r.botonReferenciado,   "falta el boton `Referenciado`");
  ok(!r.botonNoValido,      "quedo `No valido`: despues del analisis hay DOS estados");
  ok(r.puedeEliminar,       "sin `No valido` hay que poder eliminar el pedido, y no se puede");
  ok(r.tieneColapsar,       "el pipeline no es colapsable");
  ok(r.colapsadoGuardado,   "colapsar no guarda la preferencia");
  ok(r.colapsadoNoDibujaLaTabla, "colapsado sigue dibujando la tabla");
  ok(r.colapsadoSigueContando,   "colapsado no muestra el contador");
  ok(r.pestanaCaeEnProg,    "un navegador parado en la pestaña vieja no cae en A Programar");
  ok(!errs.length,          "errores de pagina: " + errs.slice(0, 2).join(" | "));
  if (fallos.length) { fallos.forEach(f => console.error("  - " + f));
    console.error("pipe-en-a-programar: " + fallos.length + " problema(s)"); process.exit(1); }
  console.log("pipe-en-a-programar OK — cuarentena primero, zona, dos estados y colapsable.");
})();
