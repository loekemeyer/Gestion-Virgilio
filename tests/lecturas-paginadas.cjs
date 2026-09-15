/* Regresión v18.62 — ninguna relación GRANDE se lee sin paginar, ni se pagina sin `order=`.

   El 15/09 `PPP_Web_Base` cruzó las 1000 filas del corte de PostgREST (db-max-rows) y el
   picking dejó de ver los artículos de los pedidos más nuevos: E25A «sin cajas disponibles»,
   D71A sin códigos, E01G armada con códigos que el picking nunca mostró (hubo que desarmarla
   y devolver el stock a mano). No hubo un solo error: PostgREST devuelve **HTTP 200** con las
   primeras 1000 filas y se calla. El `limit=` de la URL es ilusorio — sólo puede achicar.

   Este test NO persigue todos los `fetch` del archivo: persigue las relaciones que YA pasan
   las 1000 filas o están cerca, medidas contra la base. Un test que falla por sesenta cosas
   se ignora — que es exactamente lo que pasó hoy con el CI en rojo.

   Chequea tres cosas:
     1) ninguna relación de la lista se lee con `fetch` suelto (va por supaFetchAll/Safe);
     2) ninguna se pagina SIN `order=` — sin un orden estable el servidor puede devolver la
        misma fila en dos páginas o saltearla, y con 9.664 filas eso son 10 páginas a la
        ruleta. Peor que no paginar, porque encima parece resuelto;
     3) ninguna lleva un `limit=` de 4+ dígitos, que es la firma del que se creía protegido.

   Al agregar una tabla que crece, sumala a RELACIONES_GRANDES. Para medir:
     select count(*) from public."<tabla>";
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");

/* Medido contra la base el 2026-09-15. El umbral de entrada son ~700 filas: a ritmo normal
   eso es cuestión de semanas, y el día que cruza no avisa nadie. */
const RELACIONES_GRANDES = {
  "Movimientos_Stock": 61349,
  "Registros_Produccion_Virgilio": 32135,
  "Entregas_Virgilio": 11185,
  "gv_ppp_np_items": 10963,
  "gv_ppp_base_pedidos": 9664,
  "gv_venta_mensual_cliente": 9174,
  "gv_ppp_entregados_meta": 2897,
  "vista_historial_entregas": 1542,
  "PPP_Web_Base": 1308,          // ← la del 15/09
  "Facturacion_NP": 1265,
  "GV_Geo_Cliente": 1017,
};
/* Las constantes del index que apuntan a una de ésas. */
const ALIAS = {
  "SUPABASE_TABLE_ENDPOINT": "Registros_Produccion_Virgilio",
  "SUPABASE_STOCK_ENDPOINT": "Movimientos_Stock",
  "SUPABASE_ENTREGAS_ENDPOINT": "Entregas_Virgilio",
  "SUPABASE_FACTURACION_NP_ENDPOINT": "Facturacion_NP",
};
/* Excepciones, todas MEDIDAS contra la base el 15/09 — no son "me parece que es chica".
   Una lectura acotada por una CLAVE DE NEGOCIO (una tanda, una NP, un artículo) trae, en el
   peor caso real de hoy:
       Movimientos_Stock por ref de tanda .... 429   (el más ajustado)
       Movimientos_Stock por ref de NP ....... 32
       Entregas_Virgilio por cod_art ......... 362
       Entregas_Virgilio por np .............. 23
       gv_ppp_base_pedidos por pedido ........ 19
       gv_ppp_np_items por np ................ 18
       RPV por opcion + tanda ................ 7
   Ojo: agrupando sin filtrar salen pares de más de 1000 (RPV opcion=AT con texto vacío: 1745),
   pero ESO no lo lee nadie — el front siempre pide una tanda o una NP concreta.
   Lo que NO entra acá y por eso está paginado: leer sin filtro, o por rango de fechas, que es
   el caso que crece solo con el uso. Si alguno de esos números se acerca a 1000, se pagina:
     select max(n) from (select count(*) n from public."Movimientos_Stock" group by ref) x; */
const ACOTADAS = [
  /\b(np|ref|cod_art|texto|pedido|articulo|cod|clave|client_id|id)=eq\./,   // una clave concreta
  /\b(np|ref|cod_art|texto|pedido|articulo|tanda)=in\./,                    // una lista de claves
  /&select=opcion&limit=1\b/,        // el count del monitor (Prefer: count=exact)
  /order=id\.desc&limit=1\b/,        // "la última corrida"
  /limit=1\b/,                       // "¿existe?" — una fila
  /order=[^&"]*\.desc[^"]*limit=[1-9]\d{0,2}\b/,   // "los últimos N" con N<1000: el corte no lo toca
  /texto=ilike\.[^&"]*\|/,          // los eventos de UNA tanda (prefijo "<tanda>|")
  /method:\s*"(POST|PATCH|DELETE|PUT)"/,
];

const fallas = [];
const nombreDe = (txt) => {
  for (const rel of Object.keys(RELACIONES_GRANDES)) if (txt.includes(rel)) return rel;
  for (const [k, v] of Object.entries(ALIAS)) if (txt.includes(k)) return v;
  return null;
};

// ---- 1 y 3) fetch suelto sobre una relación grande ----
for (let i = src.indexOf("fetch("); i >= 0; i = src.indexOf("fetch(", i + 6)) {
  /* 400 caracteres CRUDOS desde `fetch(`. Un regex con `\)` no-greedy corta en el primer
     paréntesis —el de `encodeURIComponent(...)`— y se pierde justo el filtro que decide
     si la lectura está acotada o no. Costó tres falsos positivos. */
  const hit = src.slice(i, i + 400).split(";")[0];
  if (!/rest\/v1|SUPABASE_[A-Z_]*ENDPOINT/.test(hit)) continue;
  const rel = nombreDe(hit);
  if (!rel) continue;
  if (ACOTADAS.some((rx) => rx.test(hit))) continue;
  const limit = (hit.match(/limit=(\d{4,})/) || [])[1];
  fallas.push("`" + rel + "` (" + RELACIONES_GRANDES[rel] + " filas) leída con fetch suelto" +
    (limit ? " y limit=" + limit + " — ese límite NO evita el corte de 1000" : "") +
    ":\n      " + hit.slice(0, 150).replace(/\s+/g, " "));
}

// ---- 2) paginada pero sin order estable ----
const reCall = /supaFetchAllSafe?\(([\s\S]{0,600}?)\)\s*[;,)]/g;
let m;
while ((m = reCall.exec(src)) !== null) {
  const args = m[1];
  const rel = nombreDe(args);
  if (!rel) continue;
  if (/order=/.test(args)) continue;
  // el order puede venir dentro de una variable de consulta (ccnQ, talQ…): la resolvemos
  const v = (args.match(/,\s*([A-Za-z_$][\w$]*)\s*[\)\]\s]*$/) || [])[1];
  if (v) {
    const def = new RegExp("(?:const|let|var)\\s+" + v + "\\s*=[\\s\\S]{0,400}?;");
    const d = src.match(def);
    if (d && /order=/.test(d[0])) continue;
  }
  const ln = src.slice(0, m.index).split("\n").length;
  fallas.push("`" + rel + "` (" + RELACIONES_GRANDES[rel] + " filas) paginada SIN order= " +
    "— las páginas pueden repetir o saltear filas (línea " + ln + "):\n      " +
    args.slice(0, 130).replace(/\s+/g, " "));
}

if (fallas.length) {
  console.log("lecturas-paginadas: ✗ FAIL (" + fallas.length + ")\n  - " + fallas.join("\n  - "));
  process.exit(1);
}
const n = (src.match(/supaFetchAllSafe?\(/g) || []).length;
console.log("lecturas-paginadas: " + Object.keys(RELACIONES_GRANDES).length +
  " relaciones grandes vigiladas · " + n + " lecturas paginadas · todas con order · ✓ OK");
