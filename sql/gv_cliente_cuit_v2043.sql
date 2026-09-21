-- v20.43 (Luis, 2026-09-21): "esos clientes nuevos se subieron a la pagina, de ahi tenemos que
-- tener el dato". El CUIT que el padron de ISIS no tiene sale de las paginas
-- (loekemeyer.com / chefsrl.com), que es donde el cliente se dio de alta.
--
-- Se aprovecha la tuberia que YA corre: la Edge Function `gv-sync-padron-direcciones`
-- (cron 79, 08:40 ART) lee `customers` de LK y de Chef todos los dias. Ahora pide tambien el
-- cuit y lo escribe en DOS lugares, y no es redundancia:
--   · GV_Clientes_Direcciones.cuit  -> una fila por DIRECCION
--   · GV_Cliente_Cuit               -> una fila por CLIENTE
-- ⚠ Medido: llenar solo la de direcciones recuperaba 2 de los 35 clientes nuevos que faltaban,
-- porque un cliente recien dado de alta puede no haber cargado ninguna direccion todavia.

alter table public."GV_Clientes_Direcciones" add column if not exists cuit text;

create table if not exists public."GV_Cliente_Cuit" (
  empresa        text not null,
  cod            text not null,
  cuit           text,
  razon_social   text,
  actualizado_at timestamptz not null default now(),
  primary key (empresa, cod)
);

alter table public."GV_Cliente_Cuit" enable row level security;

do $$ begin
  if not exists (select 1 from pg_policy where polname = 'gv_cliente_cuit_lectura'
                   and polrelid = 'public."GV_Cliente_Cuit"'::regclass) then
    create policy gv_cliente_cuit_lectura on public."GV_Cliente_Cuit"
      for select to authenticated using (true);
  end if;
end $$;

grant select on public."GV_Cliente_Cuit" to authenticated;
revoke insert, update, delete, truncate on public."GV_Cliente_Cuit" from anon, authenticated;

-- El CUIT del cliente, en orden: padron de ISIS (Config. Cuarentena) -> padron de la pagina
-- (por cliente) -> padron de la pagina (por direccion). Un cliente NUEVO no esta en el de ISIS
-- todavia: por eso es nuevo.
create or replace function public.gv_cuarentena_cuit_lote(p_clientes jsonb)
returns table(empresa text, cod text, cuit text)
language sql stable security definer set search_path to 'public' as $function$
  with pedido as (
    select distinct lower(coalesce(e->>'empresa','lk')) as empresa,
                    nullif(trim(e->>'cod'), '')         as cod
      from jsonb_array_elements(coalesce(p_clientes, '[]'::jsonb)) e
  )
  select p.empresa, p.cod,
         coalesce(
           (select nullif(regexp_replace(coalesce(f.cuit,''), '\D', '', 'g'), '')
              from public."GV_Cuarentena_Fuente" f
             where f.tipo = 'busqueda' and f.empresa = id.empresa and f.cod = id.cod
               and nullif(btrim(f.cuit), '') is not null
             limit 1),
           (select nullif(regexp_replace(coalesce(k.cuit,''), '\D', '', 'g'), '')
              from public."GV_Cliente_Cuit" k
             where k.empresa = p.empresa and k.cod = p.cod
               and nullif(btrim(k.cuit), '') is not null
             limit 1),
           (select nullif(regexp_replace(coalesce(d.cuit,''), '\D', '', 'g'), '')
              from public."GV_Clientes_Direcciones" d
             where d.empresa = p.empresa and d.cod = p.cod
               and nullif(btrim(d.cuit), '') is not null
             limit 1))
    from pedido p
    cross join lateral public.gv_cuarentena_ident(p.empresa, p.cod, true) id
   where p.cod is not null
     and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio());
$function$;

revoke all on function public.gv_cuarentena_cuit_lote(jsonb) from public, anon;
grant execute on function public.gv_cuarentena_cuit_lote(jsonb) to authenticated;

-- ⚠ Una RPC nueva no la ve PostgREST hasta que recarga su cache de esquema: la primera llamada
-- vuelve 404 y, si el front se la come en un catch, la columna queda vacia para siempre.
notify pgrst, 'reload schema';

-- Corrida real de la Edge Function (v23) despues del cambio:
--   {"ok":true,"direcciones":2312,"escritas":2312,"clientes_cuit":2023,
--    "por_empresa":{"lk":1604,"chef":708},"con_cuit":{"lk":1258,"chef":760},"ms":3206}
-- Clientes nuevos con CUIT resuelto: 345 de 349 (antes del cambio, 312).
