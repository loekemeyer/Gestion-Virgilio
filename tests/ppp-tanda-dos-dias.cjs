/* Una tanda no puede salir en dos días. (v18.92, problema 338 — lo preguntó Luis 2026-09-16:
   *"¿por qué la D69C terminó en dos días diferentes? ¿cómo puede ser?"*)

   Podía porque `gv_ppp_isis_programar` reusa el código de la tanda anterior cuando todas las NP
   que se están reprogramando vienen de ella (v16.03, para no repetir el picking ya hecho) — y ese
   guard **cuenta las que entran, no las que quedan**. El 16/09 se reprogramaron 98615 y 98616 al
   17/09 reusando D69C mientras 98622 seguía en D69C el 21/09, así que el mismo código quedó en dos
   camiones de dos días.

   El arreglo vive entero en Supabase, así que desde acá se verifica el ARTEFACTO: que el archivo
   que lo describe siga en el repo y siga diciendo lo mismo que se aplicó. La verificación real es
   el centinela de la base:

       select * from public.gv_ppp_tanda_dos_dias;   -- vacía = todo bien

   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");

const p = path.join(__dirname, "..", "sql", "gv_ppp_isis_programar_reusar_v1892.sql");
if (!fs.existsSync(p)) {
  console.log("ppp-tanda-dos-dias: ✗ FAIL\n  - falta sql/gv_ppp_isis_programar_reusar_v1892.sql");
  process.exit(1);
}
const src = fs.readFileSync(p, "utf8");
const fallas = [];

// 1) el guard nuevo: se cuentan las NP de esa tanda que quedan en OTRO día
if (!/v_otras/.test(src)) fallas.push("no está el contador de NP que quedan en otro día (v_otras)");
if (!/q\.fecha is distinct from p_fecha/.test(src)) {
  fallas.push("el guard no compara contra el día destino: volvería a reusar la tanda partiéndola");
}
if (!/No se reusó la tanda/.test(src)) fallas.push("no avisa por qué no reusó la tanda");

// 2) y NO se rompió el caso para el que el reuso existe: si no queda ninguna hermana en otro día,
//    se sigue volviendo a la tanda vieja para no repetir el picking.
if (!/v_code  := v_prev;/.test(src) || !/NO hay que pickearla de nuevo/.test(src)) {
  fallas.push("se perdió el reuso legítimo (misma tanda cuando no queda ninguna hermana en otro día)");
}

// 3) el centinela
if (!/gv_ppp_tanda_dos_dias/.test(src)) fallas.push("falta el centinela gv_ppp_tanda_dos_dias");
if (!/security_invoker = true/.test(src)) fallas.push("el centinela sin security_invoker saltea la RLS");

// 4) por qué NO se bloquea con un raise: separar un pedido de su tanda es una decisión legítima
//    del supervisor. Si esto no queda escrito, la próxima sesión lo "endurece" y lo deja sin salida.
if (!/no bloquear/.test(src)) {
  fallas.push("no queda escrito por qué se abre tanda nueva en vez de bloquear");
}

if (fallas.length) {
  console.log("ppp-tanda-dos-dias: ✗ FAIL\n  - " + fallas.join("\n  - "));
  process.exit(1);
}
console.log("ppp-tanda-dos-dias: ✓ OK (el reuso mira las NP que quedan, y el reuso legítimo sigue vivo)");
