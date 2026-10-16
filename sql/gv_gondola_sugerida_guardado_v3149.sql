-- ============================================================================================
-- v31.49 (Luis, 16/10/2026) — GUARDAR A GÓNDOLA PREGUNTA DÓNDE si el código no tiene celda
-- Luis: "cuando un operario guarda en gondola un codigo del que no hay posicion establecida,
-- debería preguntar DONDE se está guardando".
-- La app emite el mismo evento del picking (PKG, v29.69) con tanda = 'GUARDADO' y las cajas
-- en el 4º campo: "COD|celda|GUARDADO|cajas". Cae en el mismo cuadro del supervisor.
-- Acá sólo cambia de dónde salen las cajas: para GUARDADO, del propio evento (no hay PKC).
-- Rollback: volver a correr la sección 3 de sql/gv_gondola_sugerida_v2969.sql.
-- ============================================================================================
create or replace function public.gv_gondola_sugerida_pendientes()
returns table(client_id text, ts timestamptz, legajo text, nombre text, tanda text,
              cod text, cod_base text, descripcion text, sector_dicho text, sector text,
              sector_ok boolean, ocupada_por text, tiene_gondola boolean, veces int, cajas numeric)
language sql stable security definer set search_path = public as $$
  with e as (
    select r.client_id, r.ts_cliente ts, r.legajo,
           upper(btrim(split_part(r.texto, '|', 1))) cod,
           btrim(split_part(r.texto, '|', 2)) dicho,
           upper(btrim(split_part(r.texto, '|', 3))) tanda,
           btrim(split_part(r.texto, '|', 4)) cj
      from public."Registros_Produccion_Virgilio" r
     where r.opcion = 'PKG' and not public.es_legajo_test(r.legajo)
       and r.ts_cliente > now() - interval '120 days'
       and not exists (select 1 from public."GV_Gondola_Sugerida_Resol" z where z.client_id = r.client_id)
  ), x as (
    select e.*, regexp_replace(regexp_replace(regexp_replace(e.cod, '\s+(LK|CH)$', ''), '([0-9E])L$', '\1'), '^0+(?=.)', '') ck,
           public.gv_gondola_sector(e.dicho) sec
      from e
  )
  select x.client_id, x.ts, x.legajo,
         (select max(p."Empleado") from public."Empleados" p where p."Legajo"::text = x.legajo),
         nullif(x.tanda, ''), x.cod, x.ck,
         (select max(n.descripcion) from public.vista_nombres_articulos n
           where regexp_replace(upper(btrim(n.cod)), '^0+(?=.)', '') = x.ck),
         x.dicho, x.sec, x.sec is not null,
         (select string_agg(distinct i.cod, ' · ') from public."GV_Lugar_Item" i
           where i.sector = x.sec and coalesce(i.activo, true)
             and regexp_replace(upper(btrim(i.cod)), '^0+(?=.)', '') <> x.ck),
         exists (select 1 from public."GV_Lugar_Item" i join public."GV_Lugar" l on l.sector = i.sector
                  where regexp_replace(upper(btrim(i.cod)), '^0+(?=.)', '') = x.ck and coalesce(i.activo, true)
                    and l.tipo = 'gondola' and coalesce(l.activo, true)),
         (select count(*)::int from x y where y.ck = x.ck and y.sec is not distinct from x.sec),
         case when x.tanda = 'GUARDADO' then   -- v31.49-guardado: las cajas vienen en el evento
           case when x.cj ~ '^[0-9]+(\.[0-9]+)?$' then x.cj::numeric else 0 end
         else
         (select coalesce(sum(case when split_part(r2.texto, '|', 4) ~ '^[0-9]+(\.[0-9]+)?$' then split_part(r2.texto, '|', 4)::numeric else 0 end), 0)
            from public."Registros_Produccion_Virgilio" r2
           where r2.opcion = 'PKC' and upper(btrim(split_part(r2.texto, '|', 1))) = x.tanda
             and regexp_replace(regexp_replace(regexp_replace(upper(btrim(split_part(r2.texto, '|', 2))), '\s+(LK|CH)$', ''), '([0-9E])L$', '\1'), '^0+(?=.)', '') = x.ck)
         end
    from x order by x.ts desc;
$$;
revoke all on function public.gv_gondola_sugerida_pendientes() from public, anon;
grant execute on function public.gv_gondola_sugerida_pendientes() to authenticated;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version, activo)
select 'gv_gondola_sugerida_pendientes', 'funcion', 'x.tanda = ''GUARDADO''',
       'El PKG del guardado a gondola (tanda GUARDADO) trae sus cajas en el evento; no se pierde del cuadro del supervisor.',
       'Luis 16/10/2026', 'v31.49', true
 where not exists (select 1 from public."GV_Reglas_Centinela" where version = 'v31.49' and objeto = 'gv_gondola_sugerida_pendientes');
