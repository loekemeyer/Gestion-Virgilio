-- BACKUP DDL de las 5 fn_canon_col_* + canon_cod_art_val previo al fix SECURITY DEFINER
-- Tomado 2026-08-31 desde pg_get_functiondef antes de aplicar migración.
-- Todas estaban prosecdef=false (SECURITY INVOKER). canon_cod_art_val con
-- acl = postgres,service_role (revoke anon/authenticated).

CREATE OR REPLACE FUNCTION public.canon_cod_art_val(p_cod text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE PARALLEL SAFE
AS $function$
declare
  trimmed text;
  k text;
  c text;
begin
  if p_cod is null then return null; end if;
  trimmed := upper(btrim(p_cod));
  if trimmed = '' then return ''; end if;
  k := regexp_replace(trimmed, '^0+(?=.)', '');
  select o.cod into c
    from public."OC_Maximos" o
   where o.activo
     and regexp_replace(upper(btrim(o.cod)), '^0+(?=.)', '') = k
   limit 1;
  if c is not null then
    return c;
  elsif trimmed ~ '^[0-9]+$' then
    return case when length(k) >= 3 then k else lpad(k, 3, '0') end;
  else
    return trimmed;
  end if;
end;
$function$;
REVOKE EXECUTE ON FUNCTION public.canon_cod_art_val(text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.canon_cod_art_val(text) TO service_role;

-- 5 trigger fns eran SECURITY INVOKER (owner=postgres, acl con anon/auth EXECUTE)
ALTER FUNCTION public.fn_canon_col_cod_art()         SECURITY INVOKER;
ALTER FUNCTION public.fn_canon_col_cod()             SECURITY INVOKER;
ALTER FUNCTION public.fn_canon_col_cod_art_quoted()  SECURITY INVOKER;
ALTER FUNCTION public.fn_canon_col_codigo()          SECURITY INVOKER;
ALTER FUNCTION public.fn_canon_col_articulo()        SECURITY INVOKER;
