/* v20.66 — PIPELINE DE CLIENTES NUEVOS (pestaña propia del módulo PPP).

   Luis, 2026-09-21: el cliente nuevo tiene un CAMINO, no un botón. Análisis crediticio en
   Equifax → la dirección lo define Referenciado / Válido / No válido → el Válido paga por
   adelantado (Speech 1, y Speech 2 si no contesta) → recién ahí se programa, con prioridad.

   Y, textual sobre la convivencia: *"De momento convive y el viejo sigue siendo el principal
   que se usa. Cuando verifiquemos que el nuevo va, cambiamos."*

   Ese "convive" es lo que este test protege, porque es lo único que puede salir mal callado:
   si los dos módulos tuvieran cada uno su propia verdad, alguien aprobaría de un lado y el
   otro seguiría mostrando el pedido como si nada. Por eso se verifica que el pipeline NO
   tenga camino propio para las tres cosas que ya existían:

     1. aprobar llama a `cuarLiberar` (la MISMA del submódulo viejo), no a una función propia;
     2. el Speech 1 sella `GV_Clientes_Nuevos_Contacto`, que es el timer del viejo;
     3. los eventos y comentarios van al MISMO log (`GV_Cuarentena_Log`).

   Y además:
     4. la pestaña existe en la barra y tiene su intercept en pppRenderProg;
     5. la etapa NO se guarda en una columna: se deriva de los timestamps;
     6. el badge del pedido es `pedidos + 1` (los facturados son los de ANTES de éste);
     7. el vínculo opera por `gv_excepcion_cuarentena` y no se puede vincular a otro nuevo;
     8. el Speech 2 pide 24 h, no 48 (Luis lo cambió el 21/09);
     9. el pedido NO se cancela solo al vencer: sale un badge en la pestaña.
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const html = fs.readFileSync(path.join(root, "index.html"), "latin1");
const sql  = fs.readFileSync(path.join(root, "sql", "gv_clin_pipeline_v2066.sql"), "utf8");
const fallos = [];

/* ── 1. aprobar es el MISMO camino que el submódulo viejo ─────────────────────────────── */
// el candado invertido: si alguien le escribe al pipeline su propio "aprobar", esto lo caza.
// v20.69: el boton de un pedido REAL sigue aprobando con cuarLiberar; solo el de EJEMPLO
// (clave __DEMO__) va a otro lado, y ese no toca nada.
if (!/const _aprobar = esDemo \? "pipeDemoAprobar\(\)" : "cuarLiberar\('/.test(html))
  fallos.push("el pipeline no aprueba con cuarLiberar: si tiene camino propio, el submodulo viejo no se entera");
// y el ejemplo no puede aprobar ni anular de verdad
if (!/const _eliminar = esDemo \? "pipeDemoEliminar\(\)" : "aprAnularAbrir\('/.test(html))
  fallos.push("el ejemplo puede eliminar un pedido de verdad");
if (!/v_demo := v_clave like/.test(sql))
  fallos.push("el backend no aisla el pedido de EJEMPLO: dejaria basura en el log de Cuarentena");
if (!/if not v_demo then\s*\n\s*insert into public\."GV_Cuarentena_Log"/.test(sql))
  fallos.push("el ejemplo escribe en el log de Cuarentena");
if (/function pipeLiberar|function pipeAprobar/.test(html))
  fallos.push("aparecio un aprobar propio del pipeline (pipeLiberar/pipeAprobar): tiene que ser cuarLiberar");

/* ── 2. el Speech 1 sella el timer del submodulo viejo ────────────────────────────────── */
if (!/if v_ev = 'speech1'[^\n]*then[\s\S]{0,260}GV_Clientes_Nuevos_Contacto/.test(sql))
  fallos.push("gv_clin_evento no sella GV_Clientes_Nuevos_Contacto en speech1: los dos modulos contarian distinto");

/* ── 3. un solo log ───────────────────────────────────────────────────────────────────── */
if (!/insert into public\."GV_Cuarentena_Log"/.test(sql))
  fallos.push("los eventos del pipeline no van al log de Cuarentena");
if (!/'pipeline_' \|\| v_ev/.test(sql))
  fallos.push("los eventos del pipeline no se distinguen en el log (prefijo pipeline_)");

/* ── 4. la pestaña ────────────────────────────────────────────────────────────────────── */
if (!/b\("clin",/.test(html))      fallos.push("falta la pestana `clin` en pppTabsHtml");
if (!/_pppTab === "clin"[\s\S]{0,200}pipeHtml\(\)/.test(html))
  fallos.push("falta el intercept de la pestana `clin` en pppRenderProg");

/* ── 5. la etapa se DERIVA, no se guarda ──────────────────────────────────────────────── */
if (/^\s*etapa\s+text/mi.test(sql.split(/gv_clin_etapa/i)[0]))
  fallos.push("la tabla del pipeline guarda una columna `etapa`: se desincroniza de los hechos");
if (!/create or replace function public\.gv_clin_etapa/i.test(sql))
  fallos.push("falta gv_clin_etapa: la etapa tiene que derivarse de los timestamps");

/* ── 6. el numero de pedido va DENTRO del badge de Cliente nuevo ─────────────────────── */
// Luis lo pidio asi desde el principio: "un badge que indica, ADEMAS de su condicion de ser
// clientes nuevos, el pedido por el que van". Estaba como badge aparte al lado de la NP.
// `nuevo_pedidos` son los FACTURADOS de toda su historia: el de la pantalla es el siguiente.
if (!/const cual = isFinite\(n\) \? \(n \+ 1\) : null;/.test(html))
  fallos.push("el badge no suma 1: nuevo_pedidos son los facturados ANTERIORES a este");
if (!/cuar-badge-nro">.{1,2} ' \+ cual \+ '.{1,2}. pedido/.test(html))
  fallos.push("el numero de pedido no esta dentro del badge de Cliente nuevo");
if (/function pipeNroPedidoHtml/.test(html))
  fallos.push("quedo pipeNroPedidoHtml sin llamadores: el numero ya vive en el badge");

/* ── 7. el vinculo ────────────────────────────────────────────────────────────────────── */
if (!/insert into public\.gv_excepcion_cuarentena[\s\S]{0,400}'vinculo'/.test(sql))
  fallos.push("gv_clin_vincular no escribe la excepcion de cuarentena: el pop-up seria decorativo");
if (!/tambi.{1,2}n figura como cliente nuevo/.test(sql))
  fallos.push("falta el guard: vincular a otro cliente nuevo es heredar cero antiguedad");
// y no puede destrabar el pedido en curso por su cuenta
const cuerpoVinc = (sql.split(/FUNCTION public\.gv_clin_vincular/i)[1] || "").split("$function$;")[0];
if (/GV_Cuarentena_Liberados/.test(cuerpoVinc))
  fallos.push("el vinculo libera el pedido en curso: tiene que seguir su camino hasta que lo aprueben");

/* ── 8. el Speech 2 pide 24 h (Luis lo bajo de 48 el 21/09) ───────────────────────────── */
if (!/pr.{1,2}ximas 24 horas/.test(html))
  fallos.push("el Speech 2 no dice 24 horas");
if (/pr.{1,2}ximas 48 horas/.test(html))
  fallos.push("el Speech 2 sigue diciendo 48 horas: Luis lo bajo a 24 el 21/09");

/* ── 9. lo vencido avisa, NO se cancela solo ──────────────────────────────────────────── */
if (!/pipe-badge-venc/.test(html))
  fallos.push("falta el badge de vencidos en la pestana");
if (!/create or replace view public\.gv_clin_vencidos/.test(sql))
  fallos.push("falta el centinela gv_clin_vencidos");
// el unico cancelado tiene que salir de una persona apretando el boton, nunca de un cron
if (/cron\.schedule[\s\S]{0,200}gv_clin/.test(sql))
  fallos.push("hay un cron tocando el pipeline: el pedido NO se cancela solo (Luis, 21/09)");

/* ── 10. el CUIT: "todavia no llegaron los pedidos" NO es "no hay CUIT" ──────────────── */
// v20.71 — bug real que vio Luis: LK 4282 mostraba «—» con el CUIT cargado en el padron y la
// RPC devolviendolo. A Programar dibujaba con _apr.pedidos vacio, el lote guardaba {} y el
// *Need() no volvia a pedir NUNCA (medido: 0 llamadas en toda la sesion). Afecta a los cuatro
// lotes, no solo al CUIT.
// v20.82: el guard de la v20.71 miraba si habia PEDIDOS y NO alcanzaba — la lista que importa
// es la de RETENIDOS, que llega en otra llamada. Una lista vacia NUNCA se guarda como respuesta.
if (!/function clinVacio\(campo\) \{ _apr\[campo\] = null; \}/.test(html))
  fallos.push("clinVacio guarda algo distinto de null: el dato no se vuelve a pedir en toda la sesion");
if (/function clinSinPedidos/.test(html))
  fallos.push("volvio clinSinPedidos: mirar si hay pedidos no alcanza, los motivos llegan despues");
["cliCuit", "cliValor", "cliContacto", "cliWpp", "pipe"].forEach(function (c) {
  if (new RegExp("if \\(!lista\\.length\\) \\{ _apr\\." + c + " = \\{\\}").test(html))
    fallos.push("el lote de " + c + " sigue guardando {} cuando la lista esta vacia: el dato no se pide nunca mas");
});

/* ── 11. el EJEMPLO tiene que responder a los botones ────────────────────────────────── */
// pipeBuscar mira `pedidosTodos`, donde el ejemplo no esta: sin esta linea pipeAnalisis salia
// por su `if (!p) return` y el boton no hacia nada (lo reporto Luis).
if (!/if \(String\(orderId\) === "__DEMO__"\) return pipeDemoPedido\(\);/.test(html))
  fallos.push("pipeBuscar no conoce al ejemplo: sus botones no hacen nada");
// y Equifax abre con el CUIT por el mismo camino que la columna
if (!/const cuit = String\(pipeCuitTxt\(p\) \|\| ""\)/.test(html))
  fallos.push("la URL de Equifax no usa pipeCuitTxt: al ejemplo le quedaria el {cuit} vacio");

/* ── 12. la MEMORIA del cliente, y el boton que no puede fallar mudo ─────────────────── */
// v20.73 (Luis): "tiene que haber memoria del estado de proceso por el que va el cliente".
// El analisis es del CLIENTE: su 2do pedido no arranca en «Sin analizar» ni vuelve a Equifax.
if (!/analisis_heredado/.test(sql) || !/cli_analisis_at/.test(sql))
  fallos.push("la RPC no trae la memoria del cliente: el 2do pedido volveria a arrancar de cero");
if (!/coalesce\(h\.analisis_at, h\.cli_analisis_at\) as analisis_ef/.test(sql))
  fallos.push("la etapa no usa el analisis EFECTIVO (propio o heredado)");
// la decision NO se hereda: Referenciado ya exime al cliente y el Valido paga pedido por pedido
if (/coalesce\([a-z]\.decision, [a-z]\.cli_decision\)/.test(sql))
  fallos.push("la decision se esta heredando: el pago por adelantado es pedido por pedido");
if (!/function pipeMemoriaHtml/.test(html))
  fallos.push("la memoria del cliente no se muestra en la fila");
// y un analisis heredado no puede correr el reloj de este pedido
if (!/e\.heredado and e\.etapa = 'analisis' then false/.test(sql))
  fallos.push("un analisis heredado vence: el reloj mide lo que espera ESTE pedido");

// Luis apreto «Análisis Cred.» en LK 4282 y no paso nada: pipeBuscar miraba solo
// `pedidosTodos` y la funcion salia por un `return` mudo. Un boton que no hace nada y no
// avisa es peor que uno que falla.
if (/const p = pipeBuscar\(empresa, orderId\); if \(!p\) return;/.test(html))
  fallos.push("pipeAnalisis vuelve a fallar en silencio si no encuentra el pedido");
if (!/\(_apr\.pedidosTodos \|\| \[\]\)\.find\(f\) \|\| \(_apr\.pedidos \|\| \[\]\)\.find\(f\)/.test(html))
  fallos.push("pipeBuscar no mira _apr.pedidos: lo que la pantalla muestra puede no estar en pedidosTodos");
// y la recarga no puede borrar el reloj que se acaba de poner
if (/function pipeRecargar\(\) \{ _apr\.pipe = null;/.test(html))
  fallos.push("pipeRecargar borra el mapa: el timer desaparece hasta que vuelve la RPC");

/* ── 13. la espera va en «Qué sigue» y en día · hora · minuto ────────────────────────── */
// v20.75 (Luis): "la espera debería estar incluida en el «Que sigue» y debería ser en formato
// de dia, hora, minuto". El formato viejo ("6d 3h") escondía los minutos justo cuando se está
// por vencer el plazo.
if (/<th>Espera<\/th>/.test(html))
  fallos.push("la espera sigue siendo una columna propia: va dentro de «Qué sigue»");
if (!/function pipeFmtEspera/.test(html))
  fallos.push("falta pipeFmtEspera: el formato dia · hora · minuto");
if (!/const _esp = [^\n]*pipe-esp-linea/.test(html))
  fallos.push("la espera no se dibuja dentro de la celda de acciones");
// ⚠ el tick de cada minuto reescribe el texto: sin data-fmt lo pisa con el formato viejo
if (!/data-fmt="dhm"/.test(html))
  fallos.push("el timer del pipeline no marca su formato: el tick lo pisaria con el viejo");
if (!/n\.getAttribute\("data-fmt"\) === "dhm" \? pipeFmtEspera/.test(html))
  fallos.push("clinTickStart no respeta el formato del pipeline");

/* ── 14. el vinculo va DENTRO del cuadro de la decision ──────────────────────────────── */
// v20.79 (Luis: "no figura la opcion de vincularlo con otras razones sociales u otros
// clientes"). Estaba en un pop-up SEPARADO que se abria DESPUES de confirmar: habia que
// decidir a ciegas. Y el propio cuadro habla de "una razon social nueva de un cliente ya
// activo" — es ahi donde se esta pensando en el vinculo.
if (!/function pipeFirmaVincHtml/.test(html))
  fallos.push("el cuadro de la decision no trae la seccion de vinculo");
if (!/pipeFirmaAbrir\([^)]*'referenciado'[\s\S]{0,400}',true\)/.test(html))
  fallos.push("el boton Referenciado no abre el cuadro con la seccion de vinculo");
if (!/pipeFirmaAbrir\([^)]*'valido'[\s\S]{0,300}',true\)/.test(html))
  fallos.push("el boton Valido no abre el cuadro con la seccion de vinculo");
// ⚠ el ORDEN (vinculo antes que la decision) lo mide tests/pipe-vinculo-en-el-cuadro.cjs
//   corriendolo de verdad: un regex sobre el codigo no lo caza — se probo, y con la condicion
//   del vinculo desactivada el texto seguia estando y el candado daba verde.
if (!/if \(s\.velegido && !s\.demo\) \{/.test(html))
  fallos.push("el vinculo del cuadro no esta condicionado a que se haya elegido un cliente");
// y no puede volver el pop-up separado que se abria solo despues de confirmar
if (/if \(ev === "referenciado" \|\| ev === "valido"\) pipeVincAbrir/.test(html))
  fallos.push("volvio el pop-up de vinculo que se abria DESPUES de confirmar");

/* ── y lo de siempre: toda vista nueva con security_invoker ───────────────────────────── */
["gv_clin_prioritarios", "gv_clin_vencidos"].forEach(function (v) {
  if (!new RegExp("alter view public\\." + v + "\\s+set \\(security_invoker = true\\)", "i").test(sql))
    fallos.push("la vista " + v + " no reafirma security_invoker (sin eso saltea la RLS)");
});

if (fallos.length) {
  console.error("pipe-clientes-nuevos: " + fallos.length + " problema(s)");
  fallos.forEach(function (f) { console.error("  - " + f); });
  process.exit(1);
}
console.log("pipe-clientes-nuevos: OK — convive con el submodulo viejo (mismo aprobar, mismo timer, mismo log).");
