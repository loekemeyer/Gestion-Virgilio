-- v26.62 (Luis, 2026-10-05: "la PPP no esta cargando… el problema es en A programar")
--
-- gv_cuarentena_ya_programado (el recuadro «Ya programados en cuarentena» de A Programar)
-- tardaba 10,5 s y authenticated corta a los 8 s: 16 de 16 llamadas en 500 (57014) desde
-- las 08:40 del 05/10.
--
-- Causa (EXPLAIN ANALYZE): los CTE `repo` y `mismo` se nombran UNA sola vez, adentro del
-- subselect correlacionado que arma `motivos_ok`, así que Postgres los INLINEA ahí y corre
-- gv_cuarentena_repo_seguro (~105 ms) y gv_cuarentena_mismo_pedido_seguro (~60 ms) POR CADA
-- PEDIDO con motivo de reposición: 24 + 23 vueltas = 3,9 s, y el subselect se evalúa otra vez
-- por cada columna que lee motivos_ok. Con `as materialized` se calculan una vez:
-- 10.471 ms -> ~460 ms, mismas filas.
--
-- No cambia ninguna regla (los tres patrones de GV_Reglas_Centinela siguen: el left join de
-- liberados_familia, gv_cuarentena_repo_seguro y _rec5). Se aplica sobre la definición VIVA,
-- es idempotente (marcador v26.60-cuar-mat: es la llave, no cambiarlo aunque la version sea v26.62)
-- y falla con raise si el texto no matchea.
--
-- APLICADO el 05/10 11:25 ART con el si de Luis ("fijate que este ok eso ahora y dale"): 480 ms,
-- 13 filas (las mismas, 0 diferencias por EXCEPT ALL), gv_reglas_perdidas vacia.
-- Centinela nuevo: GV_Reglas_Centinela id 299 (version 'v26.60', la del marcador), patron 'repo as materialized \('.
--
-- Rollback: el mismo bloque con los replace al revés (sacar " materialized" de repo y mismo).

-- REGLA_CONFIRMADA_POR_USUARIO (Luis, 05/10)
do $do$
declare
  d text := pg_get_functiondef('public.gv_cuarentena_ya_programado()'::regprocedure);
  n text;
begin
  if d ~ 'v26\.60-cuar-mat' then
    raise notice 'ya aplicado';
    return;
  end if;
  n := replace(d, E'  repo as (\n', E'  -- v26.60-cuar-mat: materialized = una vez, no por pedido (estaba en 10,5 s)\n  repo as materialized (\n');
  n := replace(n, E'  mismo as (\n', E'  mismo as materialized (\n');
  if n = d or n !~ 'repo as materialized' or n !~ 'mismo as materialized' then
    raise exception 'gv_cuarentena_ya_programado: el texto no matchea, no se aplicó nada';
  end if;
  execute n;
end
$do$;
