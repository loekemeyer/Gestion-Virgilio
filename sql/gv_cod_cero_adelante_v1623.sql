-- v16.23 (2026-09-12) — el código se ESCRIBE siempre con el cero adelante
--
-- Regla del dueño, textual: "No existe 26. Solo 026. No te equivoques mas com eso.
-- Revisa buscadores y cada vez que se escriba, siempre sea con 0 adelante."
--
-- QUÉ ESTABA MAL. En la v16.21 normalicé el `cod` de GV_UxB con gv_cod_stock() para que el
-- '029' que manda el sync de LK y el '29' del listado cayeran en la misma fila. Funcionó
-- como clave, pero gv_cod_stock PELA el cero, así que la tabla quedó guardando '26', '67',
-- '35E' — grafías que no existen. El maestro Articulos_Cajas siempre usó 3 dígitos con
-- ceros adelante (001, 026, 067) y esa es la forma del negocio.
--
-- LA DISTINCIÓN QUE FALTABA, y que ahora queda explícita:
--
--   COMPARAR  → gv_cod_stock / canon_cod / norm_cod  PELAN el cero.  NO SE TOCAN.
--               Es lo que hace que tipear 26 encuentre el 026 y al revés. Si un día se
--               "arreglaran" para no pelar, los buscadores dejarían de encontrar.
--   ESCRIBIR  → gv_cod_mostrar()  PONE el cero.  Es la forma de guardar y de mostrar.
--
-- gv_cod_mostrar rellena la parte numérica a 3 dígitos, también cuando sigue con letra
-- (35E → 035E). Los de 4+ dígitos (1063, 55215) y los que no arrancan con número (GRJ10,
-- A10, M5) quedan como están.
--
-- DEL LADO DEL FRONT (index.html): la regla ya existía —codCanon() está documentada como
-- "la forma ÚNICA de MOSTRAR un código en toda la app"— pero tenía dos agujeros:
--   a) _padCod() sólo rellenaba el código PURAMENTE numérico (/^[0-9]+$/), así que un 35E
--      que no estuviera en el mapa de OC_Maximos salía pelado. Ahora rellena la parte
--      numérica de cualquier código.
--   b) tallArtAdd(), lugAddItem() y planimAdd() guardaban el código TAL CUAL lo tipeaba el
--      usuario: si alguien escribía "26", quedaba "26" en la base. Ahora pasan por codCanon.
-- Los 14 normalizadores del front que pelan el cero se dejaron como estaban: son de
-- comparación. El alias de window.GONDOLA (que guarda las dos grafías a propósito) también.
--
-- CENTINELA nuevo: select count(*) from public.gv_cod_sin_cero
--                   where cod <> public.gv_cod_mostrar(cod);   -- 0
-- Test: tests/cod-cero-adelante.cjs (en tests/run.sh). Cubre las dos mitades — que el
-- código se escriba con cero, y que los buscadores sigan encontrando con las dos grafías.
--
-- BACKUP: GV_UxB_bkp_prepad_20260912 (con RLS, sin escritura para anon).
-- Nada de esto movió un peso: vista_facturacion_neto_items sigue en $1.395.224.315,83,
-- porque los joins usan los normalizadores que pelan y ésos no se tocaron.

-- ── cómo se ESCRIBE un código ──
create or replace function public.gv_cod_mostrar(p text)
returns text language sql immutable set search_path to 'public','pg_temp' as $$
  select case
    when coalesce(btrim(p),'') = '' then ''
    when upper(btrim(p)) !~ '^[0-9]' then upper(btrim(p))
    else lpad((regexp_match(upper(btrim(p)), '^[0-9]+'))[1],
              greatest(3, length((regexp_match(upper(btrim(p)), '^[0-9]+'))[1])), '0')
         || regexp_replace(upper(btrim(p)), '^[0-9]+', '')
  end
$$;
grant execute on function public.gv_cod_mostrar(text) to anon, authenticated, service_role;

-- ── el trigger de GV_UxB guardaba el cod pelado; ahora lo guarda como se escribe ──
create or replace function public.gv_uxb_normaliza_cod() returns trigger
language plpgsql as $$
begin
  -- gv_cod_stock saca sufijos (· , LK/CH/LOKE, la L final) y deja el núcleo;
  -- gv_cod_mostrar le devuelve el cero adelante, que es como se escribe (026, no 26)
  new.cod := public.gv_cod_mostrar(public.gv_cod_stock(new.cod));
  return new;
end $$;

update public."GV_UxB" set cod = cod;   -- dispara el trigger en las 681 filas
update public."GV_Cod_Dos_Productos" set cod = public.gv_cod_mostrar(cod)
 where cod <> public.gv_cod_mostrar(cod);

-- ── gv_uxb_resuelto exponía el cod pelado (105 casos): se muestra, así que va con cero ──
-- (se hizo con un DO que envuelve b.cod en gv_cod_mostrar sobre pg_get_viewdef; el join
--  interno sigue por el pelado, sólo cambia cómo sale)

-- ── centinela ──
create or replace view public.gv_cod_sin_cero with (security_invoker = true) as
select 'GV_UxB'::text tabla, cod from public."GV_UxB"
union all select 'GV_Cod_Dos_Productos', cod from public."GV_Cod_Dos_Productos"
union all select 'gv_uxb_resuelto', cod from public.gv_uxb_resuelto
union all select 'gv_uxb_lk', cod from public.gv_uxb_lk
union all select 'gv_uxb_sin_dato', cod from public.gv_uxb_sin_dato;
grant select on public.gv_cod_sin_cero to anon, authenticated, service_role;

-- select count(*) from public.gv_cod_sin_cero where cod <> public.gv_cod_mostrar(cod);  -- 0
