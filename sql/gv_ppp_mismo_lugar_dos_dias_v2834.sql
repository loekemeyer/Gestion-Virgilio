-- v28.34 (Luis, 07/10/2026, D6): aviso en la PPP cuando un MISMO CLIENTE tiene pedidos para el
-- MISMO LUGAR (misma dirección de entrega) programados en DÍAS DISTINTOS.
--
-- No es la regla derogada "mismo cliente, mismo día" (v21.87): ésa juntaba por CLIENTE, y un cliente
-- con sucursales en dos zonas son dos viajes. Acá la clave es (empresa, cod, dirección): la misma
-- dirección en dos días son dos viajes al mismo lugar. Es AVISO: no mueve nada.
--
-- Fuera: súper (turnos), retira / expo (no usan camión), lo que ya salió (CCN/CRN de legajo real).
-- Lo lee el front en Programación y en el Resumen de la PPP.
--
-- Rollback: drop view if exists public.gv_ppp_mismo_lugar_dos_dias;

create or replace view public.gv_ppp_mismo_lugar_dos_dias with (security_invoker = true) as
with salidos as (
  select regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('CCN','CRN')
     and coalesce(btrim(r.legajo), '') not in ('0','1')
     and btrim(coalesce(r.texto, '')) <> ''
   group by 1
), base as (
  select lower(coalesce(w.empresa, 'lk')) as empresa,
         btrim(coalesce(w.cod_cliente, '')) as cod,
         btrim(coalesce(w.razon_social, '')) as razon_social,
         w.fecha_entrega as dia,
         btrim(w.tanda) as tanda,
         public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) as np,
         coalesce(w.zona, '') as zona,
         coalesce(w.m3, 0) as m3,
         btrim(coalesce(w.direccion, '')) as direccion,
         btrim(coalesce(w.barrio, '')) as barrio
    from public."PPP_Web_Programacion" w
   where coalesce(btrim(w.tanda), '') <> ''
     and w.fecha_entrega is not null and w.fecha_entrega >= current_date
  union all
  select case when btrim(i.np) ~ '^4' then 'chef' else 'lk' end,
         btrim(coalesce(i.cod, '')),
         btrim(coalesce(i.razon_social, '')),
         left(btrim(i.fecha_entrega), 10)::date,
         btrim(i.tanda),
         btrim(i.np),
         coalesce(i.zona, ''),
         coalesce(i.m3, 0),
         btrim(coalesce(i.direccion, '')),
         btrim(coalesce(i.barrio, ''))
    from public.gv_ppp_programacion_diaria i
   where coalesce(btrim(i.tanda), '') <> ''
     and btrim(i.fecha_entrega) ~ '^\d{4}-\d{2}-\d{2}'
     and left(btrim(i.fecha_entrega), 10)::date >= current_date
), limpia as (
  select b.*,
         public.gv_dir_key(b.direccion, b.barrio) as dir_key
    from base b
   where b.cod <> ''
     and b.zona !~* 'super|retira|expo'
     and b.direccion !~* 'virgilio\s*2788'
     and not coalesce(public.gv_es_super(b.empresa, b.cod), false)
     and not exists (select 1 from salidos s
                      where s.np = regexp_replace(upper(btrim(b.np)), '\.0+$', ''))
), grupo as (
  select empresa, cod, dir_key, count(distinct dia) as dias
    from limpia
   where coalesce(dir_key, '') <> ''
   group by 1, 2, 3
  having count(distinct dia) > 1
)
select l.empresa, l.cod, l.razon_social, l.dir_key, l.direccion, l.barrio,
       l.np, l.tanda, l.dia, l.zona, l.m3, g.dias as dias_distintos
  from limpia l
  join grupo g on g.empresa = l.empresa and g.cod = l.cod and g.dir_key = l.dir_key
 order by l.empresa, l.cod, l.dir_key, l.dia, l.np;

alter view public.gv_ppp_mismo_lugar_dos_dias set (security_invoker = true);
grant select on public.gv_ppp_mismo_lugar_dos_dias to anon, authenticated;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_ppp_mismo_lugar_dos_dias', 'vista', 'gv_dir_key',
        'Aviso PPP: mismo cliente + misma dirección en días distintos (sin súper ni retira)',
        'Luis', 'v28.34')
on conflict do nothing;  -- aplicado el 07/10: centinela id 356
