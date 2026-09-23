// v21.48 — candados del encadenado stocks_carga_rapida <- refresco de la matview.
// Estatico sobre el .sql: que FUNCIONA se probo corriendolo contra la base
// (motivo '... + carga_rapida', 3.260 ms, tabla identica md5 3000430e5c...), y el
// fail-open se probo ROMPIENDO refresh_stocks_carga_rapida a proposito en una
// transaccion abortada. Esto cuida que no se pierdan las decisiones que lo hacen
// seguro, que son las que no se ven leyendo el codigo.
const fs = require("fs");
const p = "sql/gv_stock_carga_rapida_encadenada_v2148.sql";
const s = fs.readFileSync(p, "utf8");
let malos = 0;
const ok = (c, m) => { if (!c) { console.error("FALLA: " + m); malos++; } };

// 1. el lock va con TRY, nunca con el bloqueante: la instancia tiene SEIS worker slots
ok(/pg_try_advisory_xact_lock\(5768\)/.test(s),
   "el encadenado tiene que tomar el 5768 con pg_try_advisory_xact_lock");
ok(!/perform pg_advisory_xact_lock\(5768\)/.test(s),
   "NUNCA el lock bloqueante: lo comparten el cron 57 y el 68, y esperarlo come un worker slot");

// 2. fail-open: si la derivada explota, la matview se refresca igual
ok(/exception when others then\s*\n\s*--[^\n]*\n\s*v_cr := ' \(carga_rapida fallo/.test(s)
   || /exception when others then[\s\S]{0,200}?v_cr := ' \(carga_rapida fallo/.test(s),
   "si refresh_stocks_carga_rapida falla, se anota en v_cr y el refresco SIGUE");
ok(!/exception when others then[\s\S]{0,200}?raise/.test(s),
   "la rama de excepcion no puede re-lanzar: tumbaria el refresco de la matview");

// 3. y el fallo queda A LA VISTA (regla de Elias v20.58: un tapon sin centinela es
//    cambiar un error ruidoso por uno mudo)
ok(/v_cr/.test(s) && /ultimo_motivo/.test(s),
   "el resultado del encadenado tiene que viajar al motivo, o el fallo es invisible");
ok(/lock ocupado/.test(s),
   "la rama del lock ocupado tambien tiene que decirse en el motivo, no callarse");

// 4. NO se encadena cuando solo se mide ni cuando se salta
ok(/if v_do and not p_solo_medir then/.test(s),
   "el encadenado va DENTRO de la rama que refresca: si se salta, no se reescribe nada");

// 5. el cron 57 NO se apaga: es la red del lock ocupado y del fallo
ok(/EL CRON 57 NO SE APAGA/.test(s),
   "tiene que quedar escrito que el cron 57 sigue vivo como red de seguridad");
ok(!/cron\.alter_job\(57[^)]*active\s*:=\s*false/.test(s),
   "nada puede desactivar el cron 57 en este archivo");

// 6. la medicion que justifica el cambio, y el rollback
ok(/SIETE MINUTOS/.test(s) && /cron 55/.test(s) && /cron 57/.test(s),
   "tiene que quedar el numero: 2 min del 55 + 5 min del 57 = 7 de atraso en la pantalla");
ok(/ROLLBACK/.test(s) && /GV_Backup_funcdef_20260923/.test(s),
   "el rollback tiene que nombrar el backup de la definicion anterior");

// 7. centinelas puestos
ok(/GV_Reglas_Centinela/.test(s) && /refresh_stocks_carga_rapida'/.test(s)
   && /pg_try_advisory_xact_lock'/.test(s),
   "las dos reglas tienen que tener su fila en GV_Reglas_Centinela");

if (malos) { console.error("stock-carga-rapida-encadenada: " + malos + " candados ROTOS"); process.exit(1); }
console.log("stock-carga-rapida-encadenada: 12 candados OK");
