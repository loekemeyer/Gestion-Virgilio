-- idea normalizar-datos (semana 1, ítems 4.3 + 4.4) — normalizar np y tanda AL ENTRAR.
-- Problema: PPP_Base_Pedidos.pedido llega a veces como "97754.0" (float del Sheet) y
-- las tandas de las tablas PPP llegan en minúsculas/con espacios → el front consulta
-- np y np+".0" (index.html:13937) y toda vista hace upper(btrim(tanda)).
-- Fix backend: BEFORE INSERT triggers en las tablas espejo del Sheet que dejan
-- pedido/np sin ".0" y tanda upper+trim. Los sync hacen full-replace (DELETE+INSERT /
-- TRUNCATE+INSERT), así que con normalizar el INSERT alcanza — el backfill es gratis
-- en el próximo sync. Después de aplicar, se pueden simplificar los dobles-query del front.
-- ⚠ ANTES DE APLICAR: confirmar nombres reales de columnas (pedido/np/tanda) en las 3 tablas.
-- (Aplicado como migración `ppp_normalizar_np_tanda`; copia versionada.)

create or replace function public.ppp_norm_np_tanda()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if to_jsonb(new) ? 'pedido' and new.pedido is not null then
    new.pedido := regexp_replace(trim(new.pedido), '\.0+$', '');
  end if;
  if to_jsonb(new) ? 'np' and new.np is not null then
    new.np := regexp_replace(trim(new.np), '\.0+$', '');
  end if;
  if to_jsonb(new) ? 'tanda' and new.tanda is not null then
    new.tanda := upper(btrim(new.tanda));
  end if;
  return new;
end;
$$;
-- NOTA: plpgsql no permite new.<col> dinámico si la columna no existe en ESA tabla;
-- el to_jsonb(new) ? 'col' de arriba NO evita el error de compilación por columna
-- inexistente. Al aplicar, crear UNA función por tabla con sus columnas reales
-- (ppp_norm_base / ppp_norm_prog / ppp_norm_meta) usando este esqueleto.

-- drop trigger if exists trg_ppp_norm on public."PPP_Base_Pedidos";
-- create trigger trg_ppp_norm before insert on public."PPP_Base_Pedidos"
--   for each row execute function public.ppp_norm_base();
-- (ídem PPP_Programacion_Diaria → ppp_norm_prog, PPP_Entregados_Meta → ppp_norm_meta)
