-- v31.05 (Luis, 15/10/2026) — Mapa de góndolas · Tránsito
--   «Quiero que todos los insumos que tengan stock pero no lugar en GV aparezcan en tránsito …
--    que al apretarlos permita ubicarlos en un lugar góndola, rack o SC y SP».
--
-- 1) gv_gondola_sector: resuelve una celda de GÓNDOLA (GV_Lugar tipo 'gondola'), exacta o
--    con el cero de relleno (F3 → F03). Medido al aplicar: 0 de 685 celdas de góndola chocan
--    con un rack o con una celda de SC/SP, así que el orden del coalesce no tapa a nadie.
-- 2) gv_insumo_sector: + góndola al FINAL del coalesce. Rack, SC/SP y Tránsito resuelven
--    primero, como antes (centinelas 446 y 476 siguen: gv_scp_sector / gv_transito_sector).
-- 3) gv_transito_celda: tercera rama, sector TRANSITO, con los insumos que tienen stock y
--    ninguna posición del Mapa (las filas 'insumo' de gv_mapa_stock_sin_lugar), descontando lo
--    que ya está en el saldo de Tránsito para no contarlo dos veces. Columnas nuevas al final:
--    origen ('a_guardar' | 'transito' | 'sin_lugar'), ref_id (la fila de Insumos_Ubicaciones
--    anotada en un lugar que no existe, si la hay, para reemplazarla al ubicar) y detalle.
--    No cambia ningún dato: es una vista.

create or replace function public.gv_gondola_sector(p text)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  -- marcador v31.05-gondola-sector
  with t as (select upper(regexp_replace(coalesce(p,''), '\s+', '', 'g')) k)
  select coalesce(
    (select l.sector from public."GV_Lugar" l where l.tipo = 'gondola' and l.activo and l.sector = (select k from t)),
    (select l.sector from public."GV_Lugar" l where l.tipo = 'gondola' and l.activo
      and l.sector = regexp_replace((select k from t), '^([A-Z]{1,2})(\d)$', '\10\2'))
  )
$function$;

create or replace function public.gv_insumo_sector(p text)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
    -- v30.81: + Tránsito / A guardar (tipo 'transito')
    -- v31.05: + góndola, al final (Luis 15/10: un insumo se puede ubicar en góndola, rack o SC y SP)
    select coalesce(public.gv_rack_sector(p), public.gv_scp_sector(p), public.gv_transito_sector(p),
                    public.gv_gondola_sector(p))
$function$;

create or replace view public.gv_transito_celda as
 SELECT l.sector,
    l.orden,
    s.cod_base AS cod,
    s.linea AS emp,
    s.descripcion,
    s.a_guardar AS cantidad,
    'caj'::text AS unidad,
    'a_guardar'::text AS origen,
    NULL::bigint AS ref_id,
    NULL::text AS detalle
   FROM ("GV_Lugar" l
     JOIN stocks_carga_rapida s ON ((COALESCE(s.a_guardar, (0)::numeric) > (0)::numeric)))
  WHERE ((l.tipo = 'transito'::text) AND (l.sector = 'AGUARDAR'::text))
UNION ALL
 SELECT l.sector,
    l.orden,
    t.cod,
    'IN'::text AS emp,
    COALESCE(vi.nombre, t.descripcion) AS descripcion,
    t.saldo AS cantidad,
    t.unidad,
    'transito'::text AS origen,
    NULL::bigint AS ref_id,
    NULL::text AS detalle
   FROM (("GV_Lugar" l
     JOIN ( SELECT m.cod_art AS cod,
            m.unidad,
            min(m.descripcion) AS descripcion,
            sum(m.delta) AS saldo
           FROM "Movimientos_Stock" m
          WHERE ((m.deposito = 'insumos'::text) AND (upper(btrim(m.ubicacion)) = 'TRANSITO'::text))
          GROUP BY m.cod_art, m.unidad
         HAVING (sum(m.delta) > (0)::numeric)) t ON (true))
     LEFT JOIN vista_insumos vi ON ((vi.cod = t.cod)))
  WHERE ((l.tipo = 'transito'::text) AND (l.sector = 'TRANSITO'::text))
UNION ALL
 -- v31.05: stock de insumo sin ninguna posición del Mapa → se ve en Tránsito
 SELECT l.sector,
    l.orden,
    x.cod,
    'IN'::text AS emp,
    COALESCE(vi.nombre, x.cod) AS descripcion,
    x.cantidad,
    x.unidad,
    'sin_lugar'::text AS origen,
    x.ref_id,
    x.detalle
   FROM (("GV_Lugar" l
     JOIN ( SELECT a.cod,
            a.unidad,
            (a.cantidad - COALESCE(tr.saldo, (0)::numeric)) AS cantidad,
            ( SELECT min(u.id) FROM gv_insumo_ubicacion u
               WHERE ((u.estado = 'sin_lugar'::text) AND (upper(btrim(u.cod)) = upper(btrim(a.cod))))) AS ref_id,
            a.detalle
           FROM (gv_mapa_stock_sin_lugar a
             LEFT JOIN ( SELECT m.cod_art, lower(COALESCE(btrim(m.unidad), ''::text)) AS uni, sum(m.delta) AS saldo
                   FROM "Movimientos_Stock" m
                  WHERE ((m.deposito = 'insumos'::text) AND (upper(btrim(m.ubicacion)) = 'TRANSITO'::text))
                  GROUP BY m.cod_art, (lower(COALESCE(btrim(m.unidad), ''::text)))) tr
               ON (((upper(btrim(tr.cod_art)) = upper(btrim(a.cod))) AND (tr.uni = lower(COALESCE(btrim(a.unidad), ''::text))))))
          WHERE (a.tipo = 'insumo'::text)) x ON ((x.cantidad > (0)::numeric)))
     LEFT JOIN vista_insumos vi ON ((vi.cod = x.cod)))
  WHERE ((l.tipo = 'transito'::text) AND (l.sector = 'TRANSITO'::text));

alter view public.gv_transito_celda set (security_invoker = true);

insert into public."GV_Reglas_Centinela"(objeto, clase, patron, regla, quien_pidio, version, activo)
select v.objeto, v.clase, v.patron, v.regla, 'Luis 15/10', 'v31.05', true
  from (values
    ('gv_transito_celda', 'vista', 'sin_lugar', 'Todo insumo con stock y sin posición del Mapa se ve en Tránsito para ubicarlo'),
    ('gv_insumo_sector', 'funcion', 'gv_gondola_sector', 'Un insumo se puede ubicar en góndola, rack, SC y SP o Tránsito')
  ) v(objeto, clase, patron, regla)
 where not exists (select 1 from public."GV_Reglas_Centinela" c where c.objeto = v.objeto and c.patron = v.patron);
