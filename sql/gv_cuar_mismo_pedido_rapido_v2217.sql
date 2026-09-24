-- v22.17 (Luis, 24/09): gv_cuarentena_mismo_pedido_lote tardaba 16,4 s con 164 pedidos (medido),
-- y la llama gv_cuarentena_marcar_calc -> la pantalla de Cuarentena y el guard (a0d) del armado.
-- Es la causa de los "canceling statement" de Cuarentena (gv_cuarentena_marcar: 3,1 s de media,
-- pico 8,0 s contra el limite de 8 s).
-- Causa: el join de `np` era  w.order_id::text = p.order_id  OR exists(lk_pedidos_match ...)  —
-- con el OR, Postgres arma TODOS los pares (pedido x PPP_Web_Programacion = 164 x 246) y para cada
-- uno recorre lk_pedidos_match entero (1.245 filas, el cast a texto no deja usar el indice):
-- ~50 millones de comparaciones. Ademas llamaba gv_ppp_web_np_label (SQL con search_path, no se
-- inlinea) dos veces por par.
-- Arreglo: los pedidos relacionados (el mismo + pedido_origen para los dos lados) se calculan
-- UNA vez por pedido en `rel`, y el label de cada NP una vez por fila de programacion en `wl`.
-- Misma regla, misma salida: se verifica con EXCEPT ALL en las dos direcciones antes de aplicar.
-- Probado 24/09 en transaccion abortada: 165 filas, 3 exentos, EXCEPT ALL 0 en las dos direcciones;
-- 17.032 ms -> 784 ms. Y con pedido_origen cargado (1347 -> 1343): mismo resultado que la vieja.
-- ⚠ GUARD: la version en la que se baso este archivo tiene md5 e4de216335eca7dcb25ae15993f72f0d.
-- Si la viva cambio, NO se aplica: hay que mirar que agrego la otra sesion y sumarlo aca.
do $g$ begin
  if md5(pg_get_functiondef('public.gv_cuarentena_mismo_pedido_lote(jsonb)'::regprocedure)) <> 'e4de216335eca7dcb25ae15993f72f0d'
     and pg_get_functiondef('public.gv_cuarentena_mismo_pedido_lote(jsonb)'::regprocedure) !~ 'oid_rel' then
    raise exception 'gv_cuarentena_mismo_pedido_lote cambio desde el 24/09: revisar antes de aplicar';
  end if;
end $g$;

create or replace function public.gv_cuarentena_mismo_pedido_lote(p_pedidos jsonb)
 returns table(empresa text, order_id text, exento boolean, deuda_total numeric, deuda_propia numeric, resto numeric, nps text[], nps_facturadas text[], nps_pendientes integer, motivo text)
 language sql stable security definer set search_path to 'public'
as $function$
  -- Luis, 2026-09-21: "si hay una factura vinculada con OTRA NP de la misma order_id,
  -- exceptuarlo del aviso". La palabra que manda es OTRA:
  --   · la deuda se descuenta sólo si viene de una NP HERMANA ya facturada, y
  --   · tiene que quedar al menos una NP del pedido SIN facturar — la que está por salir.
  -- ⚠⚠ NADA de castear order_id a bigint: "A Programar" disfraza una NP de ISIS como pedido con
  -- order_id = 'npNNNNN'. Se castea el bigint DE LA TABLA a texto, que no puede fallar nunca.
  -- v22.17: rel/wl en vez del OR con exists por par (16,4 s -> ver sql/gv_cuar_mismo_pedido_rapido_v2217.sql).
  with cfg as (
    select coalesce((select c.valor from public."PPP_Web_Config" c
                      where c.clave = 'cuar_mismo_pedido_activo'), 1) <> 0 as activo,
           coalesce((select c.valor from public."PPP_Web_Config" c
                      where c.clave = 'cuar_deuda_minima'), 1000)::numeric as minimo
  ),
  ped as (
    select nullif(btrim(e->>'order_id'), '') as order_id,
           lower(coalesce(e->>'empresa','lk')) as empresa,
           id.empresa as emp_ev, id.cod as cod_ev
      from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e
      cross join lateral public.gv_cuarentena_ident(
        lower(coalesce(e->>'empresa','lk')),
        nullif(btrim(e->>'cod'), ''),
        coalesce(nullif(btrim(e->>'order_id'), ''), '') !~* '^np') id
     where nullif(btrim(e->>'order_id'), '') is not null
  ),
  -- Luis 23/09: el pedido de los artículos sin stock (pedido_origen) y el pedido del que salió
  -- son DOS pedidos en el sistema pero UNO para el cliente: la deuda de uno no retiene al otro.
  rel as (
    select p.empresa, p.order_id, p.emp_ev, p.cod_ev, p.order_id as oid_rel from ped p
     where p.order_id !~* '^np'
    union
    select p.empresa, p.order_id, p.emp_ev, p.cod_ev, m.order_id::text
      from ped p join public.lk_pedidos_match m
        on m.empresa = p.empresa and m.pedido_origen is not null and m.pedido_origen::text = p.order_id
     where p.order_id !~* '^np'
    union
    select p.empresa, p.order_id, p.emp_ev, p.cod_ev, m.pedido_origen::text
      from ped p join public.lk_pedidos_match m
        on m.empresa = p.empresa and m.pedido_origen is not null and m.order_id::text = p.order_id
     where p.order_id !~* '^np'
  ),
  wl as (
    select w.empresa, w.order_id::text as oid,
           upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))) as np_label
      from public."PPP_Web_Programacion" w
     where w.empresa in (select distinct r.empresa from rel r)
  ),
  np as (
    select r.empresa, r.order_id, r.emp_ev, r.cod_ev, wl.np_label,
           exists (select 1 from public."Facturacion_NP" f where upper(btrim(f.np)) = wl.np_label) as facturada
      from rel r
      join wl on wl.empresa = r.empresa and wl.oid = r.oid_rel
  ),
  herm as (
    select np.empresa, np.order_id, np.emp_ev, np.cod_ev,
           array_agg(distinct np.np_label) as nps,
           array_remove(array_agg(distinct case when np.facturada then np.np_label end), null) as nps_fc,
           count(*) filter (where not np.facturada)::int as pendientes
      from np group by 1, 2, 3, 4
  ),
  -- ⚠ El comprobante tiene que ser DEL MISMO CLIENTE y de una NP HERMANA ya facturada.
  propia as (
    select h.empresa, h.order_id, coalesce(sum(d.pendiente), 0) as monto
      from herm h
      left join public.gv_cuarentena_deuda_sucursal d
             on upper(btrim(coalesce(d.np, ''))) = any (h.nps_fc)
            and d.empresa = h.emp_ev
            and canon_cod(d.cod) = canon_cod(h.cod_ev)
     group by 1, 2
  ),
  tot as (
    select p.empresa, p.order_id, p.emp_ev, p.cod_ev,
           (select round(f.deuda, 2) from public."GV_Cuarentena_Fuente" f
             where f.empresa = p.emp_ev and f.tipo = 'deuda' and f.cod = p.cod_ev
               and coalesce(f.deuda, 0) > 0
             order by f.cargado_at desc limit 1) as deuda
      from ped p
  )
  select t.empresa, t.order_id,
         ((select activo from cfg)
           and coalesce(pr.monto, 0) > 0
           and coalesce(t.deuda, 0) > 0
           and coalesce(h.pendientes, 0) > 0
           and coalesce(array_length(h.nps_fc, 1), 0) >= 1
           and coalesce(t.deuda, 0) - coalesce(pr.monto, 0) <= (select minimo from cfg)) as exento,
         coalesce(t.deuda, 0),
         coalesce(pr.monto, 0),
         round(coalesce(t.deuda, 0) - coalesce(pr.monto, 0), 2),
         coalesce(h.nps, array[]::text[]),
         coalesce(h.nps_fc, array[]::text[]),
         coalesce(h.pendientes, 0),
         case when not (select activo from cfg)                    then 'apagado'
              when t.order_id ~* '^np'                             then 'np_de_isis'
              when h.nps is null                                   then 'sin_pedido_web'
              when coalesce(t.deuda, 0) = 0                        then 'sin_deuda'
              when coalesce(array_length(h.nps_fc,1), 0) = 0       then 'ninguna_NP_facturada'
              when coalesce(h.pendientes, 0) = 0                   then 'el_pedido_ya_salio_entero'
              when coalesce(pr.monto, 0) = 0                       then 'la_deuda_no_es_de_este_pedido'
              when coalesce(t.deuda,0) - coalesce(pr.monto,0)
                     > (select minimo from cfg)                    then 'queda_deuda_de_otros'
              else 'deuda_de_otra_NP_del_mismo_pedido' end as motivo
    from tot t
    left join herm   h  on h.empresa  = t.empresa and h.order_id  = t.order_id
    left join propia pr on pr.empresa = t.empresa and pr.order_id = t.order_id
   where es_supervisor_virgilio() or gv_es_supervisor_o_servicio();
$function$;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_cuarentena_mismo_pedido_lote','funcion','oid_rel',
        'los pedidos relacionados se calculan una vez por pedido (sin OR + exists por par: 17 s -> 0,8 s)','Luis','v22.17');
