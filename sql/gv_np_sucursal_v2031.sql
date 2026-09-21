-- v20.31 — GV_NP_Sucursal: el registro de A QUE SUCURSAL fue cada NP
--
-- Pedido de Luis (2026-09-21): la cuarentena tiene que poder distinguir la deuda por sucursal.
-- Medido ese dia: la factura de ISIS NO trae la direccion de entrega (0 de 3.522 facturas LK de
-- 365 dias mencionan un domicilio de entrega; `contraparte_direccion` es el domicilio fiscal y en
-- 365 dias un solo cliente tiene dos valores distintos). Lo que la factura si trae es el REMITO
-- (3.476 de 3.522), y el puente remito -> NP ya existe en GV_NP_Remito (101 de 101 remitos LK
-- cruzan contra su factura). Lo que falta, y es lo que arma esta tabla, es NP -> sucursal:
-- la direccion de una NP de ISIS vive en GV_PPP_Programacion_Diaria mientras esta programada
-- (133 filas al 21/09) y despues desaparece. Sin snapshot no hay historia que atribuir.
--
-- Cadena completa, cuando este el detalle del Excel de deuda por comprobante:
--   comprobante (saldo) -> remito_ref -> GV_NP_Remito -> NP -> GV_NP_Sucursal -> sucursal
--
-- Objeto NUEVO con prefijo GV_: no toca ninguna tabla compartida.

create table if not exists public."GV_NP_Sucursal" (
  empresa          text not null,
  np               text not null,
  cod              text,
  razon_social     text,
  direccion        text,
  barrio           text,
  zona             text,
  dir_key          text,
  sucursal_entrega text,
  es_retira        boolean not null default false,
  fecha_entrega    date,
  origen           text,
  first_seen       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  primary key (empresa, np)
);

alter table public."GV_NP_Sucursal" enable row level security;

do $$ begin
  if not exists (select 1 from pg_policy where polname = 'gv_np_sucursal_lectura'
                   and polrelid = 'public."GV_NP_Sucursal"'::regclass) then
    create policy gv_np_sucursal_lectura on public."GV_NP_Sucursal"
      for select to anon, authenticated using (true);
  end if;
end $$;

grant select on public."GV_NP_Sucursal" to anon, authenticated;
revoke insert, update, delete, truncate on public."GV_NP_Sucursal" from anon, authenticated;

create index if not exists gv_np_sucursal_cod_idx  on public."GV_NP_Sucursal" (empresa, cod);
create index if not exists gv_np_sucursal_dir_idx  on public."GV_NP_Sucursal" (empresa, cod, dir_key);

-- ---------------------------------------------------------------------------
-- El snapshot. Corre cada hora porque lo de ISIS se borra solo.
--
-- ⚠ El COALESCE del on conflict va con el valor NUEVO primero (lo de arriba manda) y el viejo
--   solo como respaldo cuando el nuevo viene null. Al reves —que es como estuvo wa_np_snapshot
--   hasta la v16.60, problema 76— una vez cargado el dato no se actualizaba nunca mas y la fila
--   parecia fresca con el contenido del primer dia.
-- ---------------------------------------------------------------------------
create or replace function public.gv_np_sucursal_snapshot()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_n integer := 0;
  v_i integer;
begin
  -- (a) WEB: la programacion web no se borra, pero se persiste igual para tener el origen,
  --     la sucursal elegida en el checkout y la marca de Retira en un solo lugar.
  insert into public."GV_NP_Sucursal" as s
    (empresa, np, cod, razon_social, direccion, barrio, zona, dir_key,
     sucursal_entrega, es_retira, fecha_entrega, origen)
  select w.empresa,
         public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx),
         nullif(btrim(w.cod_cliente), ''),
         nullif(btrim(w.razon_social), ''),
         nullif(btrim(w.direccion), ''),
         nullif(btrim(w.barrio), ''),
         nullif(btrim(w.zona), ''),
         public.gv_dir_key(w.direccion, w.barrio),
         nullif(btrim(m.sucursal_entrega), ''),
         (btrim(coalesce(w.zona, ''))      ~* '^retira'
          or btrim(coalesce(w.barrio, ''))    ~* '^retira$'
          or btrim(coalesce(w.direccion, '')) ~* 'virgilio\s*2788'
          or btrim(coalesce(w.direccion, '')) ~* '(^|[^a-z])retira([^a-z]|$)'),
         w.fecha_entrega,
         'web'
    from public."PPP_Web_Programacion" w
    left join public.lk_pedidos_match m
           on m.empresa = w.empresa and m.order_id = w.order_id
   where w.np is not null
  on conflict (empresa, np) do update set
    cod              = coalesce(excluded.cod, s.cod),
    razon_social     = coalesce(excluded.razon_social, s.razon_social),
    direccion        = coalesce(excluded.direccion, s.direccion),
    barrio           = coalesce(excluded.barrio, s.barrio),
    zona             = coalesce(excluded.zona, s.zona),
    dir_key          = coalesce(excluded.dir_key, s.dir_key),
    sucursal_entrega = coalesce(excluded.sucursal_entrega, s.sucursal_entrega),
    es_retira        = excluded.es_retira,
    fecha_entrega    = coalesce(excluded.fecha_entrega, s.fecha_entrega),
    origen           = coalesce(excluded.origen, s.origen),
    updated_at       = now();
  get diagnostics v_i = row_count;  v_n := v_n + v_i;

  -- (b) ISIS: esto es lo que hay que capturar SI O SI, porque manana no esta.
  --     Se lee la vista (gv_ppp_programacion_diaria), que ya aplica GV_PPP_Prog_Override.
  insert into public."GV_NP_Sucursal" as s
    (empresa, np, cod, razon_social, direccion, barrio, zona, dir_key,
     sucursal_entrega, es_retira, fecha_entrega, origen)
  select lower(public.gv_empresa_de_np_texto(p.np)),
         btrim(p.np),
         nullif(btrim(p.cod), ''),
         nullif(btrim(p.razon_social), ''),
         nullif(btrim(p.direccion), ''),
         nullif(btrim(p.barrio), ''),
         nullif(btrim(p.zona), ''),
         public.gv_dir_key(p.direccion, p.barrio),
         nullif(btrim(v.sucursal_entrega), ''),
         (btrim(coalesce(p.zona, ''))      ~* '^retira'
          or btrim(coalesce(p.barrio, ''))    ~* '^retira$'
          or btrim(coalesce(p.direccion, '')) ~* 'virgilio\s*2788'
          or btrim(coalesce(p.direccion, '')) ~* '(^|[^a-z])retira([^a-z]|$)'),
         case when btrim(coalesce(p.fecha_entrega, '')) ~ '^\d{4}-\d{2}-\d{2}'
              then left(btrim(p.fecha_entrega), 10)::date end,
         'isis'
    from public.gv_ppp_programacion_diaria p
    left join public.vista_np_sucursal v on v.np = p.np
   where nullif(btrim(p.np), '') is not null
     and lower(public.gv_empresa_de_np_texto(p.np)) in ('lk', 'chef')
  on conflict (empresa, np) do update set
    cod              = coalesce(excluded.cod, s.cod),
    razon_social     = coalesce(excluded.razon_social, s.razon_social),
    direccion        = coalesce(excluded.direccion, s.direccion),
    barrio           = coalesce(excluded.barrio, s.barrio),
    zona             = coalesce(excluded.zona, s.zona),
    dir_key          = coalesce(excluded.dir_key, s.dir_key),
    sucursal_entrega = coalesce(excluded.sucursal_entrega, s.sucursal_entrega),
    es_retira        = excluded.es_retira,
    fecha_entrega    = coalesce(excluded.fecha_entrega, s.fecha_entrega),
    origen           = coalesce(excluded.origen, s.origen),
    updated_at       = now();
  get diagnostics v_i = row_count;  v_n := v_n + v_i;

  return v_n;
end;
$function$;

revoke all on function public.gv_np_sucursal_snapshot() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Centinela: cuanta de la facturacion queda sin sucursal registrada.
-- ---------------------------------------------------------------------------
create or replace view public.gv_np_sucursal_cobertura as
with fac as (
  select f.np,
         lower(public.gv_empresa_de_np_texto(f.np)) as empresa,
         f.facturado_at::date as dia,
         case when f.np ~ '^[A-Z]{2} ' then 'web' else 'isis' end as clase
    from public."Facturacion_NP" f
   where f.facturado_at >= now() - interval '180 days'
)
select fa.empresa,
       fa.clase,
       count(*)                                                            as np_facturadas,
       count(*) filter (where s.np is not null)                            as con_sucursal,
       count(*) filter (where s.np is null)                                as sin_sucursal,
       min(fa.dia)                                                         as desde,
       max(fa.dia)                                                         as hasta
  from fac fa
  left join public."GV_NP_Sucursal" s on s.empresa = fa.empresa and s.np = fa.np
 group by 1, 2;

alter view public.gv_np_sucursal_cobertura set (security_invoker = true);
grant select on public.gv_np_sucursal_cobertura to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Cron: cada hora, al minuto 17 (83 usa el 7, 64 el 0). Aplicado = jobid 97.
-- ---------------------------------------------------------------------------
select cron.schedule('gv-np-sucursal-snapshot', '17 * * * *',
                     'select public.gv_np_sucursal_snapshot();');

-- ---------------------------------------------------------------------------
-- Backfill de una sola vez: wa_np_snapshot ya venia guardando las NP de ISIS
-- (cron 64, cada hora, desde el 28/08). No estaba muerta: lo que se congelo el
-- 08/09 es el alta de NP nuevas de ISIS, porque desde entonces programa Gestion.
-- De ahi salen 145 NP con direccion que ya no estan en la programacion viva.
-- ---------------------------------------------------------------------------
insert into public."GV_NP_Sucursal" as s
  (empresa, np, cod, razon_social, direccion, barrio, zona, dir_key,
   sucursal_entrega, es_retira, fecha_entrega, origen, first_seen, updated_at)
select lower(public.gv_empresa_de_np_texto(w.np)), btrim(w.np),
       nullif(btrim(w.cod_cliente),''), nullif(btrim(w.razon_social),''),
       nullif(btrim(w.direccion),''), nullif(btrim(w.barrio),''), nullif(btrim(w.zona),''),
       public.gv_dir_key(w.direccion, w.barrio),
       nullif(btrim(w.sucursal_entrega),''),
       (btrim(coalesce(w.zona,'')) ~* '^retira'
        or btrim(coalesce(w.barrio,'')) ~* '^retira$'
        or btrim(coalesce(w.direccion,'')) ~* 'virgilio\s*2788'
        or btrim(coalesce(w.direccion,'')) ~* '(^|[^a-z])retira([^a-z]|$)'),
       null::date, 'wa_snapshot', w.first_seen, w.updated_at
  from public.wa_np_snapshot w
 where lower(public.gv_empresa_de_np_texto(w.np)) in ('lk','chef')
on conflict (empresa, np) do nothing;

-- Rollback:
--   select cron.unschedule('gv-np-sucursal-snapshot');
--   drop view public.gv_np_sucursal_cobertura;
--   drop function public.gv_np_sucursal_snapshot();
--   drop table public."GV_NP_Sucursal";
