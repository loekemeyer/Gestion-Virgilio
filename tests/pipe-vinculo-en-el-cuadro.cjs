/* v20.79 — EL VINCULO VA DENTRO DEL CUADRO DE LA DECISION, Y ANTES QUE ELLA.

   Luis, 2026-09-21, mirando el cuadro de «Marcar REFERENCIADO»: *"no figura la opcion de
   vincularlo con otras razones sociales u otros clientes"*.

   Estaba en un pop-up SEPARADO que se abria DESPUES de confirmar, o sea que habia que decidir
   a ciegas y recien ahi aparecia la pregunta. Y el propio cuadro habla de *"el que compra por
   una razon social nueva de un cliente ya activo"*: es ahi donde se esta pensando en el
   vinculo.

   ⚠ Este test mide COMPORTAMIENTO, no texto. El primer candado que se escribio para esto era
   un regex sobre el orden de las dos llamadas en el codigo, y NO cazo el bug cuando se
   desactivo la condicion del vinculo: el texto seguia estando. Por eso se corre de verdad.

   Chequea:
   - el cuadro de Referenciado/Valido trae la seccion de vinculo, marcada como opcional;
   - el buscador lista, marca al que TAMBIEN es cliente nuevo y no lo deja elegir;
   - al confirmar, `gv_clin_vincular` se llama ANTES que `gv_clin_evento` — si el vinculo
     falla, el pedido no puede quedar decidido con el cliente sin vincular;
   - y con los datos correctos (cod del cliente, cod del vinculado, quien lo firma).
   Sale 1 si falla. */
const path = require("path");
let chromium; try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (e) { ({ chromium } = require("playwright")); }
(async () => {
  const b = await chromium.launch(); const pg = await b.newPage();
  const errs = []; pg.on("pageerror", e => errs.push(String(e)));
  // v21.51 — la ruta estaba ABSOLUTA a /home/user/…: existe en el contenedor de una
  // sesión de Claude y NO en el runner de CI, así que este test fallaba SIEMPRE allá
  // con ERR_FILE_NOT_FOUND mientras acá pasaba. Era uno de "los 4 que ya fallaban antes".
  await pg.goto("file://" + path.join(__dirname, "..", "index.html"));
  await pg.waitForTimeout(900);
  const r = await pg.evaluate(async () => {
    const out = { rpcs: [] };
    window.aprRpc = async function (fn, a) {
      out.rpcs.push({ fn: fn, cod: a && a.p_cod, vinc: a && a.p_vinc_cod, ev: a && a.p_evento, pers: a && a.p_persona });
      if (fn === "gv_clin_vinculo_buscar")
        return [{ empresa:"lk", cod:"2470", razon_social:"Distribuidora Big Bang Vip SRL", cuit:"30111111119", es_nuevo:false },
                { empresa:"chef", cod:"45", razon_social:"Distribuidora Cuyana", cuit:"30222222228", es_nuevo:true }];
      if (fn === "gv_clin_evento") return [{ etapa:"referenciado", reloj_desde:null }];
      return [];
    };
    const ped = { order_id:"1448", empresa:"lk", cod:"4282", razon_social:"Silvano Lucas Martin",
                  zona:"Zona 1", m3:0.428, np_total:3, bloques:[],
                  cuarentena_motivos:["cliente_nuevo"], cuarentena_detalle:{ nuevo_pedidos:1 } };
    _apr.listo = true; _apr.pedidos=[ped]; _apr.pedidosTodos=[ped];
    _apr.pipe={"lk:1448":{empresa:"lk",order_id:"1448",etapa:"analisis",reloj_desde:new Date().toISOString(),vencido:false}};
    _apr.cliValor={}; _apr.cliCuit={}; _apr.cliWpp={}; _apr.cuarComN={}; _apr.pipeDemo=false; _apr.pipeCfg={};

    // el boton Referenciado tiene que abrir el cuadro CON la seccion de vinculo
    pipeFirmaAbrir("lk","1448","referenciado","Marcar REFERENCIADO","ayuda",true);
    let h = pipeFirmaHtml();
    out.tieneSeccionVinculo = /pipe-vinc-caja/.test(h);
    out.tieneBuscador = /id="pipeFirmaVincQ"/.test(h);
    out.diceOpcional = /\(opcional\)/.test(h);

    // buscar y elegir
    _apr.pipeFirma.vq = "distribu";
    await pipeFirmaVincBuscar();
    h = pipeFirmaHtml();
    out.listaConResultados = (h.match(/pipe-vinc-it/g) || []).length;
    out.marcaAlOtroNuevo = /también nuevo/.test(h);
    pipeFirmaVincElegir("lk","2470","Distribuidora Big Bang Vip SRL","0");
    h = pipeFirmaHtml();
    out.muestraElegido = /Se vincula a/.test(h);
    // y no deja elegir a otro cliente nuevo
    pipeFirmaVincElegir("chef","45","Distribuidora Cuyana","1");
    out.frenaAlNuevo = /no le daría antigüedad/.test(_apr.pipeFirma.err || "");

    // confirmar: vinculo PRIMERO y despues la decision
    _apr.pipeFirma.persona = "Luis";
    await pipeFirmaConfirmar();
    await new Promise(r => setTimeout(r, 150));
    const orden = out.rpcs.filter(x => x.fn === "gv_clin_vincular" || x.fn === "gv_clin_evento").map(x => x.fn);
    out.ordenLlamadas = orden;
    out.vinculoAntesDeLaDecision = orden[0] === "gv_clin_vincular" && orden[1] === "gv_clin_evento";
    const v = out.rpcs.find(x => x.fn === "gv_clin_vincular");
    out.vinculoBien = !!(v && v.cod === "4282" && v.vinc === "2470" && v.pers === "Luis");
    out.cuadroCerrado = _apr.pipeFirma === null;
    return out;
  });
  console.log(JSON.stringify(r, null, 1));
  console.log("pageerrors:", errs.length ? errs.slice(0,2) : "none");
  await b.close();
  const ok = r.tieneSeccionVinculo && r.tieneBuscador && r.diceOpcional && r.listaConResultados >= 2 &&
             r.marcaAlOtroNuevo && r.muestraElegido && r.frenaAlNuevo && r.vinculoAntesDeLaDecision &&
             r.vinculoBien && r.cuadroCerrado && !errs.length;
  process.exit(ok ? 0 : 1);
})();
