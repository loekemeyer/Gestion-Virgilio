-- =====================================================================
-- e_madre_desde_proyeccion.sql — la columna "E. Madre" se deriva de proyeccion_madre
-- APLICADO 2026-09-02 (migracion e_madre_desde_proyeccion_2496). Copia documentada.
--
-- == POR QUE ==========================================================
-- E. Madre LK / E. Madre CH son el padron de NOMBRES de articulo (vista_nombres_articulos), pero
-- ademas traian una columna "E. Madre": un numero FIJO por articulo cargado a mano el 12/03/2026.
-- La app GestionProductivaEntero (Vercel) lo pide 42 veces por dia (select=Cod,"E. Madre") y lo
-- usa en 7 modulos como "consumo mensual" en unidades: compras de cajas, flejes y cartones,
-- envios y control de talleristas, stock SP. Era una tercera estadistica madre, con otro
-- criterio, y encima cada modulo combina LK y CH distinto (suma / maximo / LK primero).
-- Medido contra proyeccion_madre: ratio 0,82 en LK (mediana 0,85), 0,19 en CH, y 33 articulos
-- de LK que venden figuraban con 0.
--
-- Decision del usuario: UN solo criterio. La columna pasa a derivarse de
-- proyeccion_madre.proy_uni_mes (LK+Chef), sin tocar la app.
--
-- == REPARTO LK / CH ==================================================
-- E. Madre LK recibe el numero unico. E. Madre CH queda en 0, salvo los codigos que SOLO existen
-- en la tabla CH, que lo reciben ahi. Asi suma, maximo y LK-primero dan el mismo valor.
-- Codigo sin proyeccion (sin venta en 12 meses) -> 0. Codigos normalizados como en el motor
-- (mayusculas, sin ceros a la izquierda): 19 en LK y 25 en CH tienen ceros a la izquierda.
--
-- == CUANDO ===========================================================
-- Trigger AFTER INSERT a nivel sentencia sobre proyeccion_madre: sync_proyeccion_madre_virgilio()
-- (LK, miercoles 09:20 UTC) hace delete + insert en una sentencia, asi que la columna se
-- recalcula sola despues de cada push. SECURITY DEFINER porque el rol del FDW (lk_ppp_reader)
-- no tiene UPDATE sobre las tablas E. Madre y no debe tenerlo. A mano:
--   select public.actualizar_e_madre_desde_proyeccion();
--
-- Backup de los valores fijos de marzo: sql/backups/backup_limpieza_virgilio_20260902.sql
-- (LK 290 filas / suma 299.111 · CH 302 / 43.314). Restore: correr esos UPDATE y
--   drop trigger trg_proyeccion_madre_e_madre on public.proyeccion_madre;
-- =====================================================================
create or replace function public.actualizar_e_madre_desde_proyeccion()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_lk integer; v_ch integer;
begin
  update public."E. Madre LK" e
     set "E. Madre" = coalesce(p.uni, 0)
    from (select e2.id,
                 (select round(pm.proy_uni_mes)::integer from public.proyeccion_madre pm
                   where pm.cod = regexp_replace(upper(btrim(e2."Cod")), '^0+(?=.)', '')) as uni
            from public."E. Madre LK" e2) p
   where p.id = e.id
     and e."E. Madre" is distinct from coalesce(p.uni, 0);
  get diagnostics v_lk = row_count;

  update public."E. Madre CH" e
     set "E. Madre" = coalesce(p.uni, 0)
    from (select e2.id,
                 case when exists (select 1 from public."E. Madre LK" l
                                    where regexp_replace(upper(btrim(l."Cod")), '^0+(?=.)', '')
                                        = regexp_replace(upper(btrim(e2."Cod")), '^0+(?=.)', ''))
                      then 0
                      else (select round(pm.proy_uni_mes)::integer from public.proyeccion_madre pm
                             where pm.cod = regexp_replace(upper(btrim(e2."Cod")), '^0+(?=.)', ''))
                 end as uni
            from public."E. Madre CH" e2) p
   where p.id = e.id
     and e."E. Madre" is distinct from coalesce(p.uni, 0);
  get diagnostics v_ch = row_count;

  return v_lk + v_ch;
end;
$$;

revoke execute on function public.actualizar_e_madre_desde_proyeccion() from public, anon, authenticated;

create or replace function public.trg_e_madre_desde_proyeccion()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.actualizar_e_madre_desde_proyeccion();
  return null;
end;
$$;

drop trigger if exists trg_proyeccion_madre_e_madre on public.proyeccion_madre;
create trigger trg_proyeccion_madre_e_madre
  after insert on public.proyeccion_madre
  for each statement
  execute function public.trg_e_madre_desde_proyeccion();
