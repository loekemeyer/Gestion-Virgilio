// v21.05 — candados del refresco condicional de vista_stock_procesada.
// Estatico sobre el .sql: la prueba de que FUNCIONA se hizo corriendolo contra
// la base (refresco 1.813 ms / salto 12 ms). Esto cuida que no se pierdan las
// cuatro decisiones que hacen que sea seguro.
const fs = require("fs");
const p = "sql/gv_refresh_stock_si_cambio_v2105.sql";
const s = fs.readFileSync(p, "utf8");
let malos = 0;
const ok = (c, m) => { if (!c) { console.error("FALLA: " + m); malos++; } };

// 1. el arbol de dependencias se camina en vivo, NUNCA una lista escrita a mano
ok(/with recursive dep\(oid\)/.test(s) && /pg_rewrite/.test(s) && /pg_depend/.test(s),
   "gv_stock_huella_detalle tiene que caminar pg_rewrite/pg_depend, no una lista de tablas");
ok(!/Movimientos_Stock'\s*,\s*'/.test(s),
   "no puede haber una lista de nombres de tabla escrita a mano: siempre falta una");

// 2. la matview se excluye de su propia huella
ok(/relkind in \('r','p'\)/.test(s),
   "la huella tiene que filtrar relkind r/p: si cuenta la matview, se refresca para siempre");

// 3. fail-open: sin huella, se refresca
const bloque = s.slice(s.indexOf("v_new := public.gv_stock_huella_detalle()"));
ok(/exception when others then\s*\n\s*v_new := null;/.test(bloque),
   "si la huella falla, v_new queda null y arriba eso significa REFRESCAR (fail-open)");
ok(/if v_new is null then\s*\n\s*v_mot :=/.test(s) && !/if v_new is null then\s*\n\s*v_do := false/.test(s),
   "con la huella caida NO se puede saltear el refresco");

// 4. la comparacion que manda es el jsonb entero, no clave por clave
ok(/elsif v_new is not distinct from v_old then\s*\n(\s*--[^\n]*\n)*\s*v_do := false/.test(s),
   "el salto tiene que colgar de comparar el jsonb ENTERO (una tabla que entra o sale del arbol cuenta)");

// 5. piso de frescura: aunque nada cambie, se refresca cada tanto
ok(/piso de frescura/.test(s) && /p_max_edad_min int default 60/.test(s),
   "tiene que haber un piso de frescura por si el arbol no ve alguna dependencia");

// 6. el centinela va junto con el tapon (misma regla que v20.58)
ok(/create or replace view public\.gv_stock_refresh_salud/.test(s) &&
   /EL CRON NO ESTA CHEQUEANDO/.test(s),
   "sin centinela, que el cron deje de chequear no lo ve nadie");
ok(/security_invoker = true/.test(s), "la vista nueva va con security_invoker");

// 7. el rollback tiene que estar escrito
ok(/cron\.alter_job\(55, command := 'REFRESH MATERIALIZED VIEW CONCURRENTLY/.test(s),
   "el rollback de una linea tiene que estar en el archivo");

if (malos) { console.error(`\n${malos} candado(s) rotos en ${p}`); process.exit(1); }
console.log("stock-refresh-si-cambio: 10 candados OK");
