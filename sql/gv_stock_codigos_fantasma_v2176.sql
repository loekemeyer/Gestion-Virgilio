-- v21.76 — Luis, 2026-09-23: "si busco 865 me muestra el 865 pelado (que no existe),
-- ¿se puede poner un filtro para que no muestre esos?"
--
-- DE DÓNDE SALÍA EL 865. De dos filas de `Movimientos_Stock`: un ajuste manual del
-- 18/08 a las 10:32 (−1) y su reversión a las 10:57 (+1). Alguien tipeó `865` en vez
-- de `865E` y lo corrigió 25 minutos después. Pero el universo de stock se arma desde
-- los MOVIMIENTOS, no desde un maestro de artículos, así que el código quedó vivo en
-- la pantalla para siempre. O sea: cada error de tipeo en un ajuste deja un código
-- fantasma permanente. Son 19 al 23/09 — entre ellos `VASTIDOR`, `H201 PART`,
-- `N° 74` y `FLEJES LOEKEMEYER·0.80 X 64`.
--
-- ⚠ ESTO NO CONTRADICE LA v20.95, y la diferencia es toda la regla:
--     v20.95 → el código EXISTE y está en 0  → SE MUESTRA. El 0 es la respuesta.
--     v21.76 → el código NO EXISTE           → no hay nada que contestar.
-- Por eso el filtro NO mira el saldo para decidir: mira si el código es una cosa real.
-- El saldo sólo entra como guard, para no esconder jamás algo que tenga una caja.
--
-- DÓNDE SE APLICA. En `refresh_stocks_carga_rapida()`, que llena la tabla que lee la
-- pantalla, marcando `visible_en_stock = false`. NO se tocó `vista_stock_procesada`:
-- es una matview y cambiarla obliga a DROP + CASCADE, que ya se llevó puesta a
-- `gv_importados_ordenes` dos veces (v16.20 y v16.33).
-- El FRONT NO SE TOCÓ: `_stkSaldosFromView` ya respetaba `visible_en_stock === false`
-- desde antes, con su propio guard de saldo y pedidos en 0. El mecanismo estaba; lo
-- que faltaba era que alguien marcara estos códigos.

-- 1) ¿el código existe como artículo o insumo en algún maestro?
create or replace function public.gv_stock_cod_conocido(p_cod text)
returns boolean language sql stable security definer set search_path = public as $$
  with k as (select upper(regexp_replace(regexp_replace(coalesce(p_cod,''),
                    '\s+(LK|CH|LOKE)$','','i'), '^0+(?=.)','')) as c)
  select exists(select 1 from public.vista_nombres_articulos v, k
                 where upper(regexp_replace(v.cod,'^0+(?=.)','')) = k.c)
      or exists(select 1 from public.vista_uxb_articulo v, k
                 where upper(regexp_replace(v.cod::text,'^0+(?=.)','')) = k.c)
      or exists(select 1 from public."OC_Maximos" v, k
                 where upper(regexp_replace(v.cod::text,'^0+(?=.)','')) = k.c)
      or exists(select 1 from public."GV_Lugar_Item" v, k
                 where upper(regexp_replace(v.cod::text,'^0+(?=.)','')) = k.c)
      or exists(select 1 from public."Capacidad_Sector" v, k
                 where upper(regexp_replace(v.cod::text,'^0+(?=.)','')) = k.c)
      or exists(select 1 from public.proyeccion_madre v, k
                 where upper(regexp_replace(v.cod::text,'^0+(?=.)','')) = k.c)
      or exists(select 1 from public."Insumos" v, k
                 where upper(regexp_replace(v.cod::text,'^0+(?=.)','')) = k.c);
$$;
revoke all on function public.gv_stock_cod_conocido(text) from public;
grant execute on function public.gv_stock_cod_conocido(text) to anon, authenticated, service_role;

-- ⚠ Son SIETE maestros y hacen falta los siete. Medido: con `vista_nombres_articulos`
-- sola se escondían también 991E, 993E, 996E, 997E y 998E — que NO están ahí pero sí en
-- `vista_uxb_articulo`, y que se pickearon de verdad (el 998E el 22/09). Esconderlos
-- habría sido el pozo de la v20.95 otra vez.

-- 2) el parche a refresh_stocks_carga_rapida: se aplica sobre la definición VIVA,
--    es idempotente y FALLA con un raise si el texto cambió, en vez de pisar una
--    versión vieja (varias sesiones tocan estos objetos).
--    El bloque `do $mig$ … $mig$` completo está en el commit de la v21.76; agrega a
--    las dos asignaciones de visible_en_stock (el UPDATE y el INSERT):
--
--      AND (public.gv_stock_cod_conocido(vsp.cod)
--           OR COALESCE(vsp.stock_total,0) <> 0 OR COALESCE(vsp.cajas_pedidas,0) <> 0
--           OR COALESCE(vsp.proy_cajas_mes,0) <> 0 OR COALESCE(vsp.capacidad_gondola,0) <> 0
--           OR COALESCE(scr.fc_sin_salida,0) <> 0)      -- el fc sólo en el UPDATE

-- 3) el centinela: lo que se dejó de dibujar, a la vista
create or replace view public.gv_stock_codigos_fantasma
with (security_invoker = true) as
select s.cod,
       coalesce(nullif(btrim(s.descripcion),''), '(sin descripcion)') as descripcion,
       m.movs, m.saldo, m.tipos, m.depositos, m.primero, m.ultimo,
       case when m.movs = 0                          then 'no tiene ni un movimiento'
            when m.ajustes = m.movs and m.saldo = 0  then 'ajuste mal tipeado que ya se revirtio'
            when m.saldo = 0                         then 'movimientos viejos que cierran en cero'
            else 'revisar: tiene saldo' end          as motivo
  from public.stocks_carga_rapida s
  left join lateral (
      select count(*)::int movs, coalesce(sum(v.delta),0) saldo,
             count(*) filter (where v.tipo='ajuste')::int ajustes,
             string_agg(distinct v.tipo,', ') tipos, string_agg(distinct v.deposito,', ') depositos,
             min(v.ts)::date primero, max(v.ts)::date ultimo
        from public."Movimientos_Stock" v
       where upper(btrim(v.cod_art)) = upper(btrim(s.cod))) m on true
 where s.visible_en_stock = false
   and not public.gv_stock_cod_conocido(s.cod);
revoke all on public.gv_stock_codigos_fantasma from anon, authenticated;
grant select on public.gv_stock_codigos_fantasma to service_role;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('refresh_stocks_carga_rapida','funcion','gv_stock_cod_conocido',
        'Un codigo que no existe en ningun maestro y esta en cero en todo no se dibuja en Stocks (visible_en_stock=false). NO confundir con la v20.95: ahi el codigo EXISTE y el 0 es la respuesta.',
        'Luis','v21.76')
on conflict do nothing;

-- MEDIDO al aplicarlo (23/09):
--   filas de stocks_carga_rapida ................ 367
--   se escondieron .............................. 19   (ninguna con caja, pedido,
--                                                       proyeccion, capacidad ni FC)
--   NO se escondieron, aunque no tienen descripcion:
--     991E 993E 996E 997E 998E  -> estan en vista_uxb_articulo y se pickean
--     556 578 725 7             -> estan en los maestros
--   gv_stock_codigos_fantasma ................... 19 filas, 0 'revisar: tiene saldo'
--   gv_reglas_perdidas .......................... vacia
--
-- ⚠ HALLAZGO APARTE, que NO es de este cambio: el 439E (Colador Pasta) ya venia
-- oculto por la regla vieja del dual partido —base pelada con stock 0— y tiene
-- proyeccion 27 caj/mes y capacidad 66. El guard del front sólo exige stock y
-- pedidos en 0, asi que hoy no se ve. Queda reportado, no se toco.

-- CHEQUEO
--   select * from public.gv_stock_codigos_fantasma order by ultimo desc nulls last;
--   select * from public.gv_reglas_perdidas;                        -- vacia = todo bien
--   select public.gv_stock_cod_conocido('865'), public.gv_stock_cod_conocido('865E');
--                                                                   -- false, true
-- ROLLBACK (una linea: vuelve a copiar la matview tal cual)
--   ... en refresh_stocks_carga_rapida, sacar el AND (...) de las dos asignaciones
--   de visible_en_stock, o restaurar desde zz_backups."GV_Backup_funcdef_20260923".
