-- =====================================================================
--  BACKUP — definición VIVA de public.fn_canon_cod_art() ANTES de la v17.01
--  (2026-09-14). Para revertir: ejecutar tal cual.
--
--  Las dos cosas que tenía mal:
--   (1) `if NEW.tipo in ('picking','separado','facturado') then return NEW; end if;`
--       — se autoexcluía justo de los movimientos que escribe el operario, así que
--       el front podía escribir '66' y el cron '066'. Como el índice
--       mov_stock_pipeline_dedup compara por upper(trim(cod_art)), el índice los
--       veía distintos y el picking se duplicaba.
--   (2) Para insumos hacía upper() ciego, pero el catálogo "Insumos" guarda
--       CamelCase (H201Part) → el propio trigger fabricaba la grafía que después
--       no matcheaba con su catálogo.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.fn_canon_cod_art()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$

declare
  k text;
  c text;
begin
  if NEW.cod_art is null then return NEW; end if;

  -- Para insumos: solo upper + trim (no buscar en OC_Maximos)
  if NEW.deposito = 'insumos' then
    NEW.cod_art := upper(btrim(NEW.cod_art));
    return NEW;
  end if;

  if NEW.tipo in ('picking','separado','facturado') then return NEW; end if;
  k := regexp_replace(upper(btrim(NEW.cod_art)), '^0+(?=.)', '');
  if k = '' then return NEW; end if;
  select o.cod into c
    from public."OC_Maximos" o
   where o.activo
     and regexp_replace(upper(btrim(o.cod)), '^0+(?=.)', '') = k
   limit 1;
  if c is not null then
    NEW.cod_art := c;
  elsif NEW.cod_art ~ '^[0-9]+$' then
    NEW.cod_art := case when length(k) >= 3 then k else lpad(k, 3, '0') end;
  end if;
  return NEW;
end;
$function$;
