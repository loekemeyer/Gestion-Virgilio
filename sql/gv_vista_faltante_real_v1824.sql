-- =====================================================================================
-- gv_vista_faltante_real_v1824.sql
-- "Faltantes x dia no muestra todos los faltantes. Esta andando mal!" (Thomas, 15/09).
-- ✅ APLICADO el 2026-09-15. Problemas 238 (los filtros) y 239 (el parser decimal).
--
-- LO MEDIDO, antes de tocar nada
-- ---------------------------------------------------------------------------------
--   ultimos 7 dias : 148 faltantes de picking · 929 cajas · 36 tandas  -> la vista daba 9
--   ultimos 45 dias: 756 faltantes · 128 codigos                        -> la vista daba 9
--
-- Tres filtros se los comian, y ninguno de los tres tiene que ver con si el faltante ocurrio:
--
--   1. SOLO MIRABA LAS TANDAS DE ISIS. `tandas_activas` salia de
--      `GV_PPP_Programacion_Diaria`; las tandas WEB viven en `PPP_Web_Programacion` y no
--      entraban. 38 de los 148 de la semana estaban solo ahi.
--   2. EXCLUIA LA NP YA FACTURADA O ENTREGADA. De los 88 faltantes de ISIS de esos 7 dias,
--      ese filtro dejaba 9. Que el pedido se haya facturado despues NO borra que al pickear
--      faltaron cajas, y ver eso es justamente para que sirve el modulo.
--   3. EXIGIA UN EVENTO TP en la tanda (armado terminado). Un PKC con faltante es un dato
--      completo por si solo.
--
-- Y habia un cuarto agujero, mas silencioso: el JOIN con la programacion era INNER, y la
-- programacion conserva ~3 semanas. Un faltante mas viejo que eso desaparecia aunque el
-- evento estuviera guardado: 585 de los 756 de 45 dias estaban en ese caso.
--
-- LO QUE SE HIZO
-- ---------------------------------------------------------------------------------
--   · `prog` = ISIS UNION ALL WEB. De la web la empresa es un dato (`empresa`), no hay que
--     adivinarla del numero de NP, y la etiqueta sale de `gv_ppp_web_np_label`.
--   · Se dejan de excluir las facturadas y entregadas. Lo unico que se sigue sacando son las
--     NP CANCELADAS: ese pedido no existio.
--   · Se saca el requisito del TP.
--   · El JOIN pasa a LEFT: si la tanda ya no esta en ninguna programacion, la fila queda
--     igual con np/rs vacios y la fecha del propio evento.
--   · Se agrega el filtro de legajos de prueba (`not es_legajo_test`), que estaba en
--     `tandas_preparadas` y se habria perdido al sacarlo.
--
-- ⚠⚠ Y EL PARSER BORRABA EL PUNTO DECIMAL (problema 239)
-- ---------------------------------------------------------------------------------
-- `regexp_replace(campo, '[^0-9-]', '', 'g')::integer` sobre "333.33" devuelve 33333: el
-- numero queda multiplicado por 100. Caso real encontrado al destapar la vista: el evento
--     D62A|55289|333.33|0
-- figuraba como 33.333 cajas faltantes — el 91% del total de 45 dias salia de esa sola fila.
-- Es la MISMA familia que el incidente del 2026-08-26 anotado en el CLAUDE.md (55215: 20833
-- en vez de 208.33). Ahora se conserva el separador y se castea a numeric (la coma pasa a
-- punto). Son 2 de 6.623 eventos en 45 dias, pero pesan lo que pesan:
--     total de cajas faltantes en 45 dias: 36.667 -> 3.667,33
--
-- ⚠ `cajas_falto` pasa de integer a numeric, asi que va DROP + CREATE, no CREATE OR REPLACE
--   (Postgres no deja cambiar el tipo de una columna de vista). Comprobado antes: 0 vistas y
--   0 funciones la nombran. Los grants se reponen al final.
--
-- RESULTADO: 9 -> 756 filas · 128 codigos · 3.667,33 cajas · 0 filas sin fecha ·
--            gv_endpoints_rotos en 0 · security_invoker conservado.
-- Respaldo de la definicion previa: zz_backups."GV_Backup_Def_FaltanteReal_20260915".
-- =====================================================================================

drop view public.vista_faltante_real;
create view public.vista_faltante_real with (security_invoker = true) as
 WITH np_canceladas AS (
         SELECT DISTINCT btrim("NP_Canceladas".np) AS np FROM "NP_Canceladas"
        ), prog AS (
         -- ISIS: la empresa sale del numero de NP, como siempre (>90000 = LK)
         SELECT upper(btrim(p.tanda)) AS tanda,
            btrim(p.np) AS np,
            COALESCE(p.razon_social, ''::text) AS rs,
            "left"(p.fecha_entrega, 10) AS fecha_salida,
                CASE WHEN COALESCE(regexp_replace(p.np, '\D'::text, ''::text, 'g'::text), '0'::text)::bigint > 90000
                     THEN 'LK'::text ELSE 'CH'::text END AS empresa
           FROM "GV_PPP_Programacion_Diaria" p
          WHERE upper(btrim(COALESCE(p.tanda, ''::text))) <> ''::text
            AND NOT (btrim(p.np) IN ( SELECT np_canceladas.np FROM np_canceladas))
        UNION ALL
         -- WEB: aca la empresa es un dato, no hay que adivinarla
         SELECT upper(btrim(w.tanda)) AS tanda,
            gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) AS np,
            COALESCE(w.razon_social, ''::text) AS rs,
            to_char(w.fecha_entrega, 'YYYY-MM-DD'::text) AS fecha_salida,
                CASE WHEN w.empresa = 'chef'::text THEN 'CH'::text ELSE 'LK'::text END AS empresa
           FROM "PPP_Web_Programacion" w
          WHERE upper(btrim(COALESCE(w.tanda, ''::text))) <> ''::text
        ), tanda_np AS (
         SELECT DISTINCT ON (prog.tanda) prog.tanda, prog.np, prog.rs, prog.fecha_salida, prog.empresa
           FROM prog
          ORDER BY prog.tanda, prog.fecha_salida DESC NULLS LAST
        ), pkc_raw AS (
         SELECT upper(btrim(split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1))) AS tanda,
            btrim(split_part("Registros_Produccion_Virgilio".texto, '|'::text, 2)) AS cod_raw,
            -- ⚠ el '.' y la ',' NO se borran: "333.33" no son 33.333 cajas
            COALESCE(NULLIF(replace(regexp_replace(COALESCE(split_part("Registros_Produccion_Virgilio".texto, '|'::text, 3), '0'::text), '[^0-9.,-]'::text, ''::text, 'g'::text), ','::text, '.'::text), ''::text), '0'::text)::numeric AS esp,
            COALESCE(NULLIF(replace(regexp_replace(COALESCE(split_part("Registros_Produccion_Virgilio".texto, '|'::text, 4), '0'::text), '[^0-9.,-]'::text, ''::text, 'g'::text), ','::text, '.'::text), ''::text), '0'::text)::numeric AS real_c,
            "Registros_Produccion_Virgilio".ts_cliente,
            row_number() OVER (PARTITION BY (upper(btrim(split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1)))), (upper(btrim(split_part("Registros_Produccion_Virgilio".texto, '|'::text, 2)))) ORDER BY "Registros_Produccion_Virgilio".ts_cliente DESC) AS rn
           FROM "Registros_Produccion_Virgilio"
          WHERE "Registros_Produccion_Virgilio".opcion = 'PKC'::text
            AND "Registros_Produccion_Virgilio".ts_cliente >= (now() - '45 days'::interval)
            AND NOT es_legajo_test("Registros_Produccion_Virgilio".legajo)
        ), pkc_last AS (
         SELECT pkc_raw.tanda, pkc_raw.cod_raw, pkc_raw.esp, pkc_raw.real_c,
            pkc_raw.esp - pkc_raw.real_c AS falto, pkc_raw.ts_cliente
           FROM pkc_raw
          WHERE pkc_raw.rn = 1 AND (pkc_raw.esp - pkc_raw.real_c) > 0::numeric
        )
 SELECT
        CASE
            WHEN norm_cod(pk.cod_raw) = ANY (ARRAY['437E'::text, '438E'::text, '439E'::text, '809E'::text])
             AND tn.empresa IS NOT NULL
            THEN (norm_cod(pk.cod_raw) || ' '::text) || tn.empresa
            ELSE norm_cod(pk.cod_raw)
        END AS cod,
    pk.tanda,
    COALESCE(tn.np, ''::text) AS np,
    COALESCE(tn.rs, ''::text) AS rs,
    pk.falto AS cajas_falto,
    pk.cod_raw,
    COALESCE(NULLIF(tn.fecha_salida, ''::text), to_char(pk.ts_cliente AT TIME ZONE 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD'::text)) AS fecha_salida
   FROM pkc_last pk
     LEFT JOIN tanda_np tn ON tn.tanda = pk.tanda;

grant select, insert, update, delete, references, trigger, truncate on public.vista_faltante_real to anon, authenticated, service_role;


-- VERIFICAR ===========================================================================
-- (a) esperado: 756 filas · 128 codigos · 3667.33 cajas · 0 sin fecha
select count(*) filas, count(distinct cod) codigos, round(sum(cajas_falto),2) cajas,
       count(*) filter (where fecha_salida = '') sin_fecha
from public.vista_faltante_real;

-- (b) el outlier del parser ya no esta: el 55289 tiene que dar 333.33, no 33333
select cod, cajas_falto, tanda, np from public.vista_faltante_real order by cajas_falto desc limit 5;

-- (c) nada roto, y la vista conserva security_invoker
select * from public.gv_endpoints_rotos;
select relname, reloptions from pg_class where oid = 'public.vista_faltante_real'::regclass;

-- (d) las tandas WEB entran (antes no aparecia ninguna)
select count(*) from public.vista_faltante_real v
 where v.tanda in (select distinct upper(btrim(tanda)) from public."PPP_Web_Programacion");


-- ROLLBACK ============================================================================
-- drop view public.vista_faltante_real;
-- y recrearla con la definicion de zz_backups."GV_Backup_Def_FaltanteReal_20260915"
-- (columna `def`), reponiendo `with (security_invoker = true)` y los grants de arriba.
