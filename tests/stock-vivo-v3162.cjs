/* v31.62 (Luis, 16/10/2026) — STOCKS EN VIVO.
   "arregla el cron, dale" · "si se puede hacer que solo busque cambios, golazo" · "si la tabla se ve
   en realtime, aun mejor".

   Lo que se rompía: (1) el cron 57 pisaba con la matview los saldos que el trigger ya había dejado
   bien (936E 12 → 11 → 12); (2) las cajas pedidas viajaban sólo por la matview y el neto se leía una
   vez al abrir; (3) el realtime de stocks_carga_rapida no le llegaba al supervisor logueado (política
   de SELECT sólo para anon).

   Este test cuida:
   A) el .sql: la protección de lo movido, escribir sólo lo que cambia, el job "sólo si cambió" con
      TRY del 5768, la política para authenticated, Importación leyendo el mismo número, rollback.
   B) la pantalla: un UPDATE de realtime con las columnas ped_* actualiza la celda (dem) Y el
      tooltip (pedNeto), y redibuja UNA vez por ráfaga.
   C) la carga: si las filas traen ped_vivo_en, el neto sale de ellas (no se lee la vista) y el merge
      con la matview NO pisa las pedidas vivas.
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
let malos = 0;
const ok = (c, m) => { if (!c) { console.error("FALLA: " + m); malos++; } };

// A) ──────────────────────────────────────────────────────────────────────────────────────────
const sql = fs.readFileSync(path.join(__dirname, "..", "sql", "gv_stock_vivo_v3162.sql"), "utf8");
ok(/create policy auth_read_stocks_carga_rapida[\s\S]{0,80}to authenticated/.test(sql),
   "sin la política para authenticated el realtime no le llega al supervisor logueado");
ok(/= any\(v_movidos\)/.test(sql) && /m\.creado > coalesce\(v_ref, now\(\)\)/.test(sql),
   "refresh_stocks_carga_rapida tiene que proteger los códigos movidos después del último refresco");
ok((sql.match(/IS DISTINCT FROM/g) || []).length >= 2,
   "los dos UPDATE de refresh_stocks_carga_rapida escriben SÓLO las filas que cambian");
ok(!/SET fc_sin_salida = 0/.test(sql),
   "nada de poner fc_sin_salida en 0 y de vuelta: son dos eventos de realtime por fila");
ok(/CASE WHEN v_ped_vivo THEN scr\.cajas_pedidas ELSE COALESCE\(vsp\.cajas_pedidas, 0\)/.test(sql),
   "cajas_pedidas es del job mientras esté sano; si se cae, vuelve la matview (fail-open)");
ok(/gv_stock_pedidas_sucio_seq/.test(sql) && /v_vis is distinct from v_seq/.test(sql),
   "el job recalcula sólo si la secuencia se movió");
ok(/pg_try_advisory_xact_lock\(5768\)/.test(sql) && !/perform pg_advisory_xact_lock\(5768\)/.test(sql),
   "el job toma el 5768 con TRY, nunca con el bloqueante");
ok(/when \(\(old\.np_label, old\.articulo, old\.cajas\) is distinct from/.test(sql),
   "PPP_Web_Base se reescribe entera por sync: su trigger de UPDATE sólo dispara si cambia lo que suma");
ok(/new\.opcion in \('TP','EP'\)/.test(sql) && !/'PKC'\)\) execute/.test(sql),
   "en Registros sólo TP y EP (un PKC por caja pickeada recalcularía todo el día)");
ok(/select nextval\('public\.gv_stock_pedidas_sucio_seq'\)/.test(sql),
   "la secuencia se arranca una vez: el primer nextval no mueve last_value");
ok(/FROM stocks_carga_rapida p/.test(sql) && /gv_importados_stock_dep with \(security_invoker = true\)/.test(sql),
   "Importación lee las pedidas de stocks_carga_rapida, con security_invoker repuesto");
ok(/ROLLBACK/.test(sql) && /GV_Backup_funcdef_20261016_stockvivo/.test(sql),
   "el rollback tiene que nombrar el backup de las definiciones");
ok(/GV_Reglas_Centinela/.test(sql), "las reglas nuevas tienen su centinela");

// B) y C) ─────────────────────────────────────────────────────────────────────────────────────
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const fila = (cod, ped, extra) => Object.assign({ cod: cod, descripcion: "x", linea: "LK", terminado: 12,
      excedente: 0, separar_pedidos: 0, a_facturar: 0, a_guardar: 0, racks: 84, racks_ch: 0, para_envasar: 0,
      insumos_dep: 0, stock_total: 96, cajas_pedidas: ped, proy_cajas_mes: 0, capacidad_gondola: 0 }, extra || {});
    const vivo = { ped_vivo_en: "2026-10-16T12:00:00-03:00", ped_neto: 8, ped_con_tp: 4, ped_en_curso: 0,
                   ped_familia: "936E", ped_es_secundario: false, ped_fam_con_tp: 4, ped_fam_en_curso: 0, ped_fam_miembros: 1 };

    // C) helpers de carga
    const sinDato = _stkPedNetoDeFilas([fila("936E", 12)]);
    const conDato = _stkPedNetoDeFilas([fila("936E", 12, vivo), fila("501", 0, Object.assign({}, vivo, { ped_neto: 0 }))]);

    // B) realtime simulado: se captura el handler del UPDATE de stocks_carga_rapida
    let handler = null, renders = 0;
    const canal = { on: function (_t, cfg, fn) { if (cfg.table === "stocks_carga_rapida" && cfg.event === "UPDATE") handler = fn; return canal; },
                    subscribe: function () { return canal; } };
    window.sb = { channel: function () { return canal; }, removeChannel: function () {} };
    const _render0 = window.stkRender;
    window.stkRender = function () { renders++; };
    try { stkUnsubscribeRealtime(); } catch (_e) {}
    _stk = { viewRows: [fila("936E", 12)], dem: { "936E": 12 }, proy: {}, pedNeto: null };
    stkSubscribeRealtime();
    const hayHandler = typeof handler === "function";
    if (hayHandler) {
      handler({ new: fila("936E", 16, Object.assign({}, vivo, { ped_neto: 12 })) });
      handler({ new: fila("936E", 16, Object.assign({}, vivo, { ped_neto: 12 })) });
      handler({ new: fila("936E", 16, Object.assign({}, vivo, { ped_neto: 12 })) });
    }
    const rendersInmediatos = renders;
    await new Promise((res) => setTimeout(res, 800));
    const out = {
      sinDatoEsNull: sinDato === null,
      conDato936: conDato && conDato["936E"] && conDato["936E"].neto === 8 && conDato["936E"].tp === 4 && conDato["936E"].tot === 12,
      conDatoSinPedidasNoEntra: conDato && !conDato["501"],
      hayHandler: hayHandler,
      demVivo: _stk.dem["936E"],
      netoVivo: _stk.pedNeto && _stk.pedNeto["936E"] && _stk.pedNeto["936E"].neto,
      rendersInmediatos: rendersInmediatos,
      rendersTotal: renders,
      pedNetoOf: (function () { const o = _pedNetoOf("936E"); return o && o.tot; })()
    };
    window.stkRender = _render0;
    try { stkUnsubscribeRealtime(); } catch (_e) {}
    return out;
  });
  ok(r.sinDatoEsNull, "sin ped_vivo_en en ninguna fila tiene que devolver null (se lee la vista como siempre)");
  ok(r.conDato936, "con ped_vivo_en el neto/pickeadas/total salen de la fila");
  ok(r.conDatoSinPedidasNoEntra, "un código sin pedidas no entra al mapa (la celda cae al total, como la vista)");
  ok(r.hayHandler, "stkSubscribeRealtime tiene que escuchar UPDATE de stocks_carga_rapida");
  ok(r.demVivo === 16, "el UPDATE de realtime actualiza las cajas pedidas de la celda (dio " + r.demVivo + ")");
  ok(r.netoVivo === 12, "el UPDATE de realtime actualiza el neto del tooltip (dio " + r.netoVivo + ")");
  ok(r.pedNetoOf === 16, "_pedNetoOf lee la entrada parcheada por realtime");
  ok(r.rendersInmediatos === 0 && r.rendersTotal === 1,
     "tres eventos seguidos = UN redibujo, diferido (dio " + r.rendersInmediatos + " inmediatos / " + r.rendersTotal + ")");

  // C) el merge con la matview no pisa las pedidas vivas (estático: el bloque es largo de montar)
  const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
  ok(/if \(r\.ped_vivo_en == null\) r\.cajas_pedidas = vr\.cajas_pedidas;/.test(html),
     "el merge con vista_stock_procesada no puede pisar cajas_pedidas de una fila viva");
  ok(/ped_fam_miembros,ped_vivo_en"\)\.catch/.test(html), "la carga rápida pide las columnas ped_*");
  ok(/_pnFila \? Promise\.resolve\(null\) : stkFetchPedidasNeto\(\)/.test(html),
     "con el neto en la fila no se lee la vista; sin él, sí");

  if (errs.length) { console.error("errores de página:", errs.slice(0, 3)); }
  await b.close();
  if (malos) { console.error(malos + " falla(s)"); process.exit(1); }
  console.log("OK stock-vivo-v3162");
})();
