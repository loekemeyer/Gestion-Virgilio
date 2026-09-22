-- v21.31 — Dos cosas del stock, medidas el 22/09 a la tarde con el deposito quieto.
--
-- ══ A. La huella del refresco condicional (v21.06) NO estaba ahorrando ══
--
-- Medido: 166 refrescos contra 2 saltos = 1,2 % ahorrado, cuando lo esperado era
-- 94,5 %. Causa: la huella contaba ESCRITURAS (pg_stat_user_tables) y hay crons
-- que reescriben tablas enteras sin cambiar nada de lo que ve la matview:
--
--   tabla                  inserts   updates   quien
--   PPP_Web_Base               372   582.748   el sync la reescribe entera
--   GV_UxB                       0    34.036   idem
--   Movimientos_Stock        2.847     7.223   cron 81 gv-reconciliar-aguardar, CADA 2 MIN
--   Registros_Produccion_V   1.048     5.471
--   proyeccion_madre         1.383       922   delete+insert diario desde LK
--
-- El cron 81 corre en el MISMO minuto que el 55 (17:18:00,23 contra 17:18:00,19),
-- asi que cada chequeo encontraba escrituras frescas y refrescaba igual.
--
-- ⚠ Esto ya estaba escrito como riesgo en la v21.06 ("un delete+insert con contenido
--   identico dispara un refresco al pedo") y se lo trato como caso raro. NO es raro:
--   es el caso NORMAL de esta base. La medicion de 5 minutos que lo dio por bueno
--   cayo justo entre dos corridas del cron.
--
-- Arreglo: las tablas ruidosas pasan a firma de CONTENIDO, y cual es ruidosa es un
-- INSERT en GV_Stock_Huella_Expr, no codigo. El resto sigue con el contador barato.
-- Costo medido de la huella completa: 60-74 ms (antes 11 ms) contra 1.900 del refresco.
-- Resultado: 0 refrescos / 3 saltos = 100 % ahorrado con el cron 81 corriendo en el medio.
--
-- ⚠ Y el armador de motivos casteaba a bigint: con una firma de texto explota en
--   EJECUCION con 22P02 (el pozo de la v19.44, que ya estaba escrito). Hoy compara
--   como TEXTO y solo resta cuando los dos lados son numeros.
--
-- ══ B. Pedir UN codigo costaba lo mismo que pedir TODOS ══
--
-- `vista_saldos_stock.clave` es una expresion de AGREGACION
-- (`(array_agg(cod_art order by length(cod_art)))[1]` para un no-dual), asi que
-- `clave=eq.438E` NO se puede empujar: el plan recorre las 67.945 filas de
-- Movimientos_Stock, las ORDENA, y despues filtra (`Rows Removed by Filter: 496`).
-- 687 ms para devolver 1 fila. Se lee asi desde 5 lugares de index.html:
-- 1.759 llamadas, 2.850 s — mas que el refresco de la matview (1.808 s).
--
-- ⚠ NINGUN indice sobre `clave` arregla eso, porque `clave` no existe en la tabla.
--   Lo que SI es indexable es `ckey`, la normalizacion del codigo, que es funcion
--   PURA de cod_art y usa solo funciones inmutables. Por eso alcanza con un INDICE
--   DE EXPRESION: no hay columna nueva, no hay trigger, no hay backfill y no se
--   reescribe una sola fila del libro de stock. 496 kB.
--
-- Y para que el indice sirva hace falta que ALGUIEN filtre por esa expresion:
-- gv_saldos_por_clave(text[]) filtra la base por ckey y recien despues agrupa.
--   1 codigo:   687 ms -> 7 ms   (98x)
--   10 codigos: 687 ms -> 69 ms
-- Verificado identico: 496 = 496 filas, EXCEPT ALL 0 en las dos direcciones.
--
-- ⚠ El filtro va con `= any(v_ck)` y la expresion escrita IGUAL que en el indice.
--   Con `in (select k from <cte>)` el planner NO lo usa y vuelve al seq scan
--   (medido: 232 ms). La primera version de la funcion tenia ese bug.
--
-- ⚠ Las 2 lecturas que piden el UNIVERSO entero (`select=*`) se dejaron como estan:
--   887 + 526 llamadas, ~2.221 s. Para esas el indice no sirve — necesitan las 496
--   filas igual. Es lo que queda pendiente.
--
-- Rollback (nada de esto toca datos):
--   drop index if exists public.mov_stock_ckey_idx;
--   drop function if exists public.gv_saldos_por_clave(text[]);
--   delete from public."GV_Stock_Huella_Expr";   -- vuelve al contador de escrituras
--   select cron.alter_job(55, command := 'REFRESH MATERIALIZED VIEW CONCURRENTLY vista_stock_procesada');

-- ── A ──────────────────────────────────────────────────────────────────────
create table if not exists public."GV_Stock_Huella_Expr" (
  objeto    text primary key,
  expr      text not null,
  nota      text,
  creado_en timestamptz not null default now()
);
alter table public."GV_Stock_Huella_Expr" enable row level security;
revoke insert, update, delete, truncate on public."GV_Stock_Huella_Expr" from anon, authenticated;

-- (las 5 filas de configuracion estan aplicadas en la base; se agregan con un
--  insert ... on conflict do update, no hace falta deploy)

-- ── B: el indice de expresion ──────────────────────────────────────────────
-- ⚠ Tiene que estar escrito IGUAL que el `ckey` de vista_saldos_stock, con los
--   ::text explicitos, o el planner no lo reconoce.
create index if not exists mov_stock_ckey_idx
  on public."Movimientos_Stock" ((
    CASE
      WHEN upper(btrim(cod_art)) ~ '^[0-9]+$'::text THEN
        CASE
          WHEN length(regexp_replace(upper(btrim(cod_art)), '^0+(?=.)'::text, ''::text)) >= 3
            THEN regexp_replace(upper(btrim(cod_art)), '^0+(?=.)'::text, ''::text)
          ELSE lpad(regexp_replace(upper(btrim(cod_art)), '^0+(?=.)'::text, ''::text), 3, '0'::text)
        END
      ELSE upper(btrim(cod_art))
    END
  ));

-- Las definiciones vivas de gv_stock_huella_detalle, gv_refresh_stock_si_cambio y
-- gv_saldos_por_clave estan aplicadas en la base; traerlas con pg_get_functiondef
-- antes de tocarlas (regla de la definicion viva).

-- Chequeos:
--   select * from public.gv_stock_refresh_salud;          -- pct_ahorrado alto = anda
--   select * from public."GV_Stock_Huella_Expr";          -- que tabla lleva firma de contenido
--   explain (analyze, buffers) select * from public.gv_saldos_por_clave(array['438E LK']);
--     -> tiene que decir "Bitmap Index Scan on mov_stock_ckey_idx"
--   -- y el que prueba que NO cambio ni una fila:
--   with t as (select array_agg(clave) k from public.vista_saldos_stock),
--        v as (select * from public.vista_saldos_stock),
--        f as (select * from public.gv_saldos_por_clave((select k from t)))
--   select (select count(*) from (select * from v except all select * from f) z),
--          (select count(*) from (select * from f except all select * from v) z);   -- 0, 0
