-- v28.77 (Luis, 08/10): «NPs por Día» (TV / Mon. Admin) y la Programación de la PPP muestran
-- Facturado como «con FC de ISIS parseada / exportadas al Excel». Esta RPC (sólo lectura) dice,
-- de una lista de NP, cuáles ya tienen la factura de ISIS asignada (GV_Cruce_FC_Asig.doc_id, cron 90).
-- Rollback: drop function public.gv_np_fc_parseada(text[]);
create or replace function public.gv_np_fc_parseada(p_nps text[])
returns table(np text)
language sql stable security definer
set search_path to 'public','pg_temp'
as $$
  select distinct regexp_replace(upper(btrim(a.np)), '\.0+$', '')
    from public."GV_Cruce_FC_Asig" a
   where a.doc_id is not null
     and regexp_replace(upper(btrim(a.np)), '\.0+$', '') = any (
           select regexp_replace(upper(btrim(x)), '\.0+$', '') from unnest(coalesce(p_nps, '{}'::text[])) x)
$$;
grant execute on function public.gv_np_fc_parseada(text[]) to anon, authenticated;
