-- REGLA_CONFIRMADA_POR_USUARIO (Luis, D3 sí, 14/10/2026)
-- (Las 2 filas de GV_Reglas_Centinela quedaron con la etiqueta v30.40: se cargaron antes de renumerar a v30.43.)
-- v30.43 (Luis, 14/10/2026) — Generador de OC:
--  1) Los 552xx se fabrican SÓLO A PEDIDO: Máximo 0, piden lo pedido − stock.
--     El piso de súper les sumaba una reserva sobre el pedido ya cargado
--     (55219 Maspoli: 2000 pedidas + 626 de piso = 2626; 55289 Pettofrezza: 7980).
--     Patrón configurable: Stock_Config 'oc_solo_a_pedido_regex' (cambiarlo es un update).
--  2) El FALTANTE de una NP pickeada/armada que no se facturó todavía cuenta como demanda.
--     pend_np saca toda NP con tanda pickeada (TP), así que lo que faltó y se puede completar
--     no lo pedía nadie (789 Dorinka CH 0061: 16 pedidas, 2 armadas, 14 faltan → 0 en la OC).
--     Mismo universo que «Completar pedido» (cpLoadFaltantes): cajas_falto > 0, sin facturar,
--     no anulado (-X), no cancelado, salida de los últimos 21 días.
-- Se aplica sobre la definición VIVA (replace con chequeo de que cada fragmento existe).

insert into "Stock_Config"(clave, valor, actualizado)
values ('oc_solo_a_pedido_regex', '^552[0-9]{2}$', now())
on conflict (clave) do update set valor = excluded.valor, actualizado = now();

create or replace view public.gv_oc_faltante_pickeado
with (security_invoker = true) as
select btrim(e.np) as pedido,
       e.cod_art   as articulo,
       sum(e.cajas_falto) as cajas
  from "Entregas_Virgilio" e
 where e.cajas_falto > 0
   and btrim(e.np) not in (select btrim(f.np) from "Facturacion_NP" f where f.np is not null)
   and coalesce(btrim(e.tanda), '') !~* '-X\d*$'
   and upper(btrim(e.np)) not in (select upper(btrim(c.np)) from gv_np_canceladas_lista() c where c.np is not null)
   and left(e.fecha_salida, 10) >= to_char((now() at time zone 'America/Argentina/Buenos_Aires')::date - 21, 'YYYY-MM-DD')
 group by btrim(e.np), e.cod_art;

grant select on public.gv_oc_faltante_pickeado to anon, authenticated;

do $do$
declare
  d text := pg_get_viewdef('public.vista_generador_oc'::regclass);
  a_old text := $a$           FROM (gv_demanda_pedidos b
             JOIN pend_np n ON ((btrim(b.pedido) = n.np)))$a$;
  a_new text := $a$           FROM ( SELECT d0.pedido, d0.articulo, d0.cajas
                   FROM (gv_demanda_pedidos d0
                     JOIN pend_np n ON ((btrim(d0.pedido) = n.np)))
                UNION ALL
                 SELECT f0.pedido, f0.articulo, f0.cajas
                   FROM gv_oc_faltante_pickeado f0
                  WHERE (NOT (f0.pedido IN ( SELECT pend_np.np FROM pend_np)))) b$a$;
  b_old text := $b$                CASE
                    WHEN (COALESCE(cm.llenar_gondola, false) AND$b$;
  b_new text := $b$                CASE
                    WHEN (cm.codn_base ~ COALESCE(( SELECT "Stock_Config".valor FROM "Stock_Config" WHERE ("Stock_Config".clave = 'oc_solo_a_pedido_regex'::text)), '^$'::text)) THEN (0)::numeric
                    WHEN (COALESCE(cm.llenar_gondola, false) AND$b$;
begin
  if position(a_old in d) = 0 then raise exception 'fragmento demanda no encontrado'; end if;
  if position(b_old in d) = 0 then raise exception 'fragmento maximo no encontrado'; end if;
  d := replace(replace(d, a_old, a_new), b_old, b_new);
  execute 'create or replace view public.vista_generador_oc as ' || d;
  execute 'alter view public.vista_generador_oc set (security_invoker = true)';
end
$do$;

insert into "GV_Reglas_Centinela"(objeto, clase, patron, regla, quien_pidio, version, activo)
values
 ('vista_generador_oc', 'vista', 'oc_solo_a_pedido_regex',
  'v30.43: los 552xx se fabrican SOLO A PEDIDO: Maximo 0, la OC pide lo pedido menos stock. Sin esto el piso de super les suma una reserva encima del pedido (55219: 2000+626).',
  'Luis', 'v30.43', true),
 ('vista_generador_oc', 'vista', 'gv_oc_faltante_pickeado',
  'v30.43: el faltante de una NP pickeada/armada sin facturar (completable) cuenta como demanda. Sin esto la OC no pide lo que falto (789 Dorinka CH 0061: 14 cajas).',
  'Luis', 'v30.43', true);
