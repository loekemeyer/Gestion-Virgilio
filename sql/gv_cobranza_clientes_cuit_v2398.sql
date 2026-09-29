-- v23.98 — (empresa, codigo) -> CUIT, para el submodulo de Cobranzas
--
-- POR QUE: Luis (29/09) pidio la ficha de cliente "con deuda consolidada". Un cliente
-- puede tener codigo en LK y en Chef, y esos codigos no se parecen en nada
-- (LK 4045 / CH 2211). La identidad la da el CUIT, nunca el codigo ("el cod cliente
-- no significa nada, solo el CUIT vale", v13.76) y tampoco la razon social: ISIS le
-- pega el sufijo de la sucursal, asi que "Bazar Monica S. CAP I SECC IV" (LK) y
-- "Bazar Monica SRL" (CH) son EL MISMO cliente escrito de dos formas. Agrupar por
-- nombre lo parte en dos, y dos nombres parecidos de clientes distintos los fusiona.
--
-- MEDIDO el 29/09 sobre los ultimos 450 dias de facturas:
--   codigos con CUIT en LK ....... 760
--   codigos con CUIT en Chef ..... 175
--   CUIT presentes en LAS DOS .... 69   <- los que la ficha consolida
--   filas que devuelve la RPC .... 927
--
-- Misma fuente y mismo guard que gv_cobranza_cliente_cuit(text), que ya existia.
-- No toca ningun dato: es lectura.

create or replace function public.gv_cobranza_clientes_cuit()
returns table(empresa text, cod_cliente text, cuit text)
language sql stable security definer set search_path to 'public' as $fn$
  select 'lk'::text, regexp_replace(coalesce(d.contraparte_codigo,''),'^0+','') ,
         regexp_replace(coalesce(d.contraparte_cuit,''),'\D','','g')
    from isis_lk.documentos d
   where d.fecha >= current_date - 450
     and coalesce(d.contraparte_codigo,'') <> ''
     and regexp_replace(coalesce(d.contraparte_cuit,''),'\D','','g') <> ''
     and (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio())
   group by 2,3
  union
  select 'chef'::text, regexp_replace(coalesce(d.contraparte_codigo,''),'^0+','') ,
         regexp_replace(coalesce(d.contraparte_cuit,''),'\D','','g')
    from isis_ch.documentos d
   where d.fecha >= current_date - 450
     and coalesce(d.contraparte_codigo,'') <> ''
     and regexp_replace(coalesce(d.contraparte_cuit,''),'\D','','g') <> ''
     and (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio())
   group by 2,3;
$fn$;

revoke all on function public.gv_cobranza_clientes_cuit() from public;
grant execute on function public.gv_cobranza_clientes_cuit() to anon, authenticated, service_role;

-- chequeo
-- select count(*) filas, count(*) filter (where empresa='chef') chef from public.gv_cobranza_clientes_cuit();
-- cuantos clientes quedan consolidados (codigo en las dos empresas):
-- select count(*) from (select cuit from public.gv_cobranza_clientes_cuit()
--                        group by cuit having count(distinct empresa) = 2) z;   -- 69 al 29/09

-- ROLLBACK (la RPC es nueva: borrarla no rompe nada de lo que habia antes;
-- el front cae solo a "cada codigo va por separado", con el chip "sin CUIT")
-- drop function if exists public.gv_cobranza_clientes_cuit();
