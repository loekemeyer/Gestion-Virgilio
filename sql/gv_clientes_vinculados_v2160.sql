-- v21.60 (Luis, 23/09): GV_Clientes_Vinculados = espejo de la tabla CANONICA clientes_vinculados
-- de LK (cliente real con todos sus codigos: Excel de Ventas + CUIT + grupos + vinculos a mano).
-- La escribe LK cada hora (cron LK 55: recalcular_clientes_vinculados + sync_clientes_vinculados_virgilio)
-- por el FDW con el rol lk_ppp_reader. La lee la PPP (pipeline de clientes nuevos) por
-- gv_clientes_vinculados_lote, que devuelve los OTROS codigos del mismo cliente.
-- Fuente y definicion: pagina-LK-copia/sql/clientes_vinculados.sql.
create table if not exists public."GV_Clientes_Vinculados" (
  empresa text not null, cod text not null, grupo text not null, razon_social text, cuit text,
  fuentes text[], n_codigos int, ultima_compra date, es_principal boolean, actualizado_at timestamptz default now(),
  primary key (empresa, cod));
create index if not exists gv_clientes_vinculados_grupo on public."GV_Clientes_Vinculados"(grupo);
alter table public."GV_Clientes_Vinculados" enable row level security;
revoke all on public."GV_Clientes_Vinculados" from anon, authenticated;
grant select, insert, update, delete on public."GV_Clientes_Vinculados" to lk_ppp_reader;
create policy "GV_Clientes_Vinculados_writer" on public."GV_Clientes_Vinculados" for all to lk_ppp_reader using (true) with check (true);

create or replace function public.gv_clientes_vinculados_lote(p_clientes jsonb)
returns table(empresa text, cod text, n_codigos int, otros jsonb)
language sql stable security definer set search_path = public, pg_temp as $$
  with q as (select distinct lower(coalesce(e->>'empresa','lk')) emp, regexp_replace(btrim(e->>'cod'),'^0+(?=.)','') cod
               from jsonb_array_elements(coalesce(p_clientes,'[]'::jsonb)) e where nullif(btrim(e->>'cod'),'') is not null)
  select q.emp, q.cod, v.n_codigos,
         (select jsonb_agg(jsonb_build_object('empresa',w.empresa,'cod',w.cod,'razon_social',w.razon_social,
                  'ultima_compra',w.ultima_compra,'principal',w.es_principal) order by w.ultima_compra desc nulls last)
            from public."GV_Clientes_Vinculados" w where w.grupo = v.grupo and not (w.empresa = q.emp and w.cod = q.cod))
    from q join public."GV_Clientes_Vinculados" v on v.empresa = q.emp and v.cod = q.cod
   where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio());
$$;
revoke all on function public.gv_clientes_vinculados_lote(jsonb) from public, anon;
grant execute on function public.gv_clientes_vinculados_lote(jsonb) to authenticated, service_role;
-- Chequeo: select count(*) from public."GV_Clientes_Vinculados";  -- 906 al 23/09
-- Rollback: drop function public.gv_clientes_vinculados_lote(jsonb); drop table public."GV_Clientes_Vinculados";
--           y en LK: cron 55 volver a 'select public.recalcular_clientes_vinculados()'.
