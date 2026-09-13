-- #####################################################################################
-- EJECUTADO el 2026-09-13 con el "dale" de Thomas (sesión session_016eFzFQwpy6ceA9EEgSqUeC).
-- CORRIÓ PARCIAL. SÍ: backups (override 119 filas, geo 3), columna zona en GV_PPP_Prog_Override,
-- vista gv_ppp_programacion_diaria con el coalesce, override 97889 Matiz → Zona 4 - GBA Sur
-- (verificado), y 4 de las 5 filas de GV_Geo_Cliente (801, 2445, 2447, 2499) + el delete de
-- GV_Geo_Fallidas de 2445. super_mezclado 0, endpoints_rotos 0.
-- NO CORRIÓ: (b) CENCOSUD 2444 y el punto 8 (Del Plastic, Tabaré 1240) — les falta lat/lng y
-- NO SE INVENTAN. Cuando Thomas los dé, se corre sólo ese insert.
-- #####################################################################################
-- ============================================================================
-- PENDIENTE DE EJECUTAR — espera el "dale" de Thomas. NADA de esto se corrió.
-- v16.72 · 2026-09-13 · datos que ensucian el cálculo de jornada de camión (PPP 14–18/09):
--   (a) NP 97889 Matiz SA (Burzaco) con zona "Zona 2 - CABA Centro" → es GBA Sur
--   (b) CENCOSUD Tortuguitas (cod 2444, NP 44609/44610/44611, D72A) sin ubicación
--   (c) las otras 8 direcciones sin geocodificar del 14 al 18/09 y qué se hace con cada una
--
-- QUÉ LEE CADA TABLA QUE SE TOCA:
--   GV_PPP_Prog_Override → la vista `gv_ppp_programacion_diaria` (y a través de ella
--     gv_ppp_base_pedidos, gv_ppp_en_salida, gv_ppp_entregados(_meta), gv_ppp_isis_sin_tanda,
--     gv_fac_armado_sin_facturar, gv_geo_faltantes, gv_lk_np_feed, gv_ppp_cliente_dos_dias,
--     gv_ppp_super_mezclado, gv_viaje_np, gv_clientes_habituales, gv_viaje, gv_viajes_sin_controlar,
--     gv_geo_cobertura, gv_geo_faltantes_padron — barrido transitivo del 13/09, 19 vistas en 3 niveles)
--     y 8 funciones (gv_ppp_tanda_mover, gv_ppp_isis_programar, gv_ppp_isis_desprogramar,
--     gv_ppp_np_cancelar, gv_ppp_en_salida_marcar/_desmarcar, gv_ppp_web_letra_y_camion,
--     gv_ppp_web_codigo_tomado). Ninguna lee una columna `zona` del override (no existe todavía), así
--     que agregarla no cambia nada para ellas. 119 filas hoy. Ningún trigger.
--   GV_Geo_Cliente → el front (`pppRefreshGeo` → `_pppGeoDe`, 1ª prioridad por cód+dirección), la Edge
--     Function gv-geocodificar (cron 75; `manual = true` la deja en paz) y `gv_geo_de_cliente`.
--     PK (cod, dir_key). Ningún trigger.
--   GV_PPP_Programacion_Diaria → NO se toca (espejo de ISIS; regla: sobre lo compartido se agrega,
--     no se modifica). La zona mala se pisa con el override, como la tanda de 44619 (§3.ap/§3.aq).
--
-- ⚠ La corrección DE FONDO de (a) es en la PPP de ISIS (el panel de la app dice literalmente
--   "revisar/corregir en el Excel"): si ISIS vuelve a mandar la fila con Zona 2, el override la sigue
--   pisando; si la corrigen allá, el override queda redundante y se puede borrar.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- (0) BACKUP (RLS + sin escritura para anon, protocolo de CLAUDE.md)
-- ---------------------------------------------------------------------------
create table zz_backups."GV_Backup_prog_override_20260913" as
  select * from public."GV_PPP_Prog_Override";                                   -- 119 filas
alter table zz_backups."GV_Backup_prog_override_20260913" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GV_Backup_prog_override_20260913" from anon, authenticated;
create table zz_backups."GV_Backup_geo_cliente_20260913" as
  select * from public."GV_Geo_Cliente" where cod in ('2444','2445','2447','2499','801');   -- lo que toca (b)/(c)
alter table zz_backups."GV_Backup_geo_cliente_20260913" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GV_Backup_geo_cliente_20260913" from anon, authenticated;

-- ---------------------------------------------------------------------------
-- (a) NP 97889 — Matiz SA, cod 4263, "Constitución 1665", barrio Burzaco, 9,25 m³, D71A, mié 16/09.
--     Medido: GV_PPP_Programacion_Diaria id 115989 tiene zona 'Zona 2 - CABA Centro'. Burzaco es
--     'Zona 4 - GBA Sur' (gv_zona_de_barrio('Burzaco') = 'Zona 4 - GBA Sur'; GV_Barrios_Sector
--     burzaco → sector L "GBA Sur Lomas"). En GV_PPP_Programacion_Diaria las 3 filas con barrio
--     Burzaco (16/09 → 28/10) tienen TODAS 'Zona 2' — es Matiz las tres veces, o sea que ISIS carga a
--     este cliente con la zona mal; no hay otro cliente de Burzaco para comparar.
--     Hoy el override NO tiene columna zona: se agrega (nullable, sin default, sólo se lee si viene
--     cargada) y la vista la superpone igual que hace con tanda y fecha_entrega.
--     ⚠ Matiz está en la lista de SÚPER del front (pppEsSuper por cód): el camión que le toca es un
--       "súper solo" sea cual sea la zona. La zona corrige el aviso "ZONA?" del panel, la etiqueta y
--       lo que lean gv_ppp_web_camion_del_dia/gv_ppp_super_mezclado, no el reparto de camiones.
-- ---------------------------------------------------------------------------
alter table public."GV_PPP_Prog_Override" add column if not exists zona text;
comment on column public."GV_PPP_Prog_Override".zona is
  'v16.72: pisa la zona del espejo de ISIS para esa NP (null = no pisa). Primer caso: 97889 Matiz, Burzaco cargado como Zona 2.';

-- la vista, con la zona superpuesta (definición del 13/09 + `coalesce(nullif(btrim(o.zona), ''), p.zona)`)
-- Mismas 16 columnas, mismo orden y tipos → CREATE OR REPLACE conserva OID, grants (select anon/authenticated,
-- all service_role) y las 19 vistas dependientes. security_invoker = true como estaba.
create or replace view public.gv_ppp_programacion_diaria
with (security_invoker = true) as
 SELECT p.id,
        p.np,
        CASE WHEN COALESCE(o.desprogramada, false) THEN ''::text
             ELSE COALESCE(NULLIF(btrim(o.tanda), ''::text), p.tanda) END AS tanda,
        p.tipo, p.fecha_recep, p.cod, p.razon_social, p.m3, p.v, p.direccion, p.barrio, p.op,
        CASE WHEN COALESCE(o.desprogramada, false) THEN ''::text
             ELSE COALESCE(o.fecha_entrega::text || ' 00:00:00'::text, p.fecha_entrega) END AS fecha_entrega,
        p.fecha_fc,
        COALESCE(NULLIF(btrim(o.zona), ''::text), p.zona) AS zona,          -- v16.72
        p.observaciones
   FROM "GV_PPP_Programacion_Diaria" p
     CROSS JOIN gv_espejo_corte() c(lk, chef)
     LEFT JOIN "GV_PPP_Prog_Override" o ON o.np = regexp_replace(p.np, '\.0+$'::text, ''::text)
  WHERE gv_espejo_np_pasa(p.np, c.lk, c.chef) AND NOT COALESCE(o.oculto, false);

insert into public."GV_PPP_Prog_Override" (np, zona, nota)
values ('97889', 'Zona 4 - GBA Sur',
        'v16.72 2026-09-13 · zona: ISIS la carga como Zona 2 - CABA Centro y Burzaco es GBA Sur (Matiz SA, 9,25 m3, D71A 16/09). Corregir también en la PPP de ISIS.')
on conflict (np) do update
  set zona = excluded.zona,
      nota = coalesce("GV_PPP_Prog_Override".nota, '') || ' | ' || excluded.nota;

-- verificación
select np, tanda, zona, barrio, m3, fecha_entrega from public.gv_ppp_programacion_diaria where np = '97889';   -- Zona 4 - GBA Sur
select np, zona, nota from public."GV_PPP_Prog_Override" where np = '97889';
select * from public.gv_ppp_super_mezclado;                                   -- espera vacío
select * from public.gv_endpoints_rotos;                                      -- espera vacío

-- ---------------------------------------------------------------------------
-- (b) CENCOSUD S.A., cod 2444, "Km 38.5, Au Panamericana     0", Tortuguitas, zona Super, D72A 16/09
--     (NP 44609 0,866 m³ · 44610 0,604 · 44611 0,852). dir_key exacto (gv_dir_key / _rtDirKey):
--       'km 38.5, au panamericana 0|tortuguitas'
--     0 filas en PPP_Geo, 0 en GV_Geo_Cliente, 0 en GV_Geo_Fallidas (la Edge Function nunca lo intentó
--     o no lo registró). Nominatim no resuelve "km 38.5" de una autopista: hay que cargarla A MANO.
--     Formato = el de las filas manuales que ya existen (4114 Luján, 4189, 4198): fuente
--     'google_maps_dueño', precision 'manual', manual = true (el cron no la pisa), comp null.
--     ⚠ Sin salida a internet desde esta sesión no se pudo obtener lat/lng: quedan <LAT>/<LNG>.
--       Para el recálculo de docs/JORNADA-CAMIONES-14-18-09.md se usó una aproximación
--       (-34.456, -58.760: Panamericana ramal Pilar a la altura de Tortuguitas), que sólo afecta al
--       camión del súper — que va solo — y no cambia la cantidad de camiones de ningún día.
--       Referencia cercana en la base: Inc S.A. (cod 1651) "Av Otto Krausse 5108, Tortuguitas" =
--       -34.4477118, -58.6992615 (Parque Industrial El Triángulo, al lado del CD de Cencosud).
-- ---------------------------------------------------------------------------
insert into public."GV_Geo_Cliente" (cod, dir_key, razon_social, direccion, barrio, lat, lng, comp, fuente, manual, usos, precision)
values ('2444', 'km 38.5, au panamericana 0|tortuguitas', 'CENCOSUD S.A.', 'Km 38.5, Au Panamericana     0', 'Tortuguitas',
        <LAT>, <LNG>, null, 'google_maps_dueño', true, 1, 'manual')
on conflict (cod, dir_key) do update
  set lat = excluded.lat, lng = excluded.lng, fuente = excluded.fuente, manual = true, precision = 'manual', actualizado_at = now();

-- verificación
select cod, dir_key, lat, lng, fuente, manual from public."GV_Geo_Cliente" where cod = '2444';
select * from public.gv_geo_de_cliente('2444');

-- ---------------------------------------------------------------------------
-- (c) LAS OTRAS 8 DIRECCIONES SIN GEOCODIFICAR DEL 14 AL 18/09 (14 filas = 9 direcciones con la de
--     Cencosud). Medido con la MISMA regla del front (`_pppGeoDe`: GV_Geo_Cliente cód+dirección →
--     PPP_Geo por dirección → cualquier ubicación del cód). Todas son de la página (PPP_Web_Programacion).
--
--   1. cod 801 Coto "Los Andes 1381 - E.Echeverría CD" (E16A 15/09, súper 2,207 m³)
--      → hoy cae al paracaídas por cód y acierta (GV_Geo_Cliente 'los andes 1381|esteban echeverría').
--      Es la misma dirección con otro tipeo: se guarda la clave exacta para que no dependa del paracaídas.
--   2. cod 4103 Villar "Retira" (E19A 15/09) → NO se geocodifica: Retira no viaja.
--   3. cod 2105 Cresta "Exp. Cargo — PEPEIRI 1386, Pompeya" (E03C 15/09, LK 0033/0048)
--      → cae al paracaídas por cód (Cabred 4700, Pompeya, otra dirección del mismo cliente, misma
--      zona). Es depósito de expreso: lo intenta el cron; si Nominatim no lo saca ("Pepeirí" es
--      "Pepirí"), se carga a mano cuando haya lat/lng. No se toca acá.
--   4. cod 2447 Bazar Mandarin (LK) "Exp. Fantacci — BEAZLEY 3519, Nueva Pompeya" (E12D 17/09, LK 0060/0061)
--      → cae al paracaídas por cód ¡y el cód 2447 también es Clapera en CHEF (Rabanal 2866, Soldati)!
--      Hoy lo ubica 2,5 km al sur. PPP_Geo ya tiene 'beazley 3519|nueva pompeya': se guarda esa
--      ubicación bajo la clave exacta.
--   5. cod 2445 Gastronomia Gonzalez "Triunvirato Av. 5463-V.Urquiza" (E12C 17/09, común)
--      → GV_Geo_Fallidas: 16 intentos, "sin resultado" (el "-V.Urquiza" pegado rompe a Nominatim).
--      PPP_Geo tiene 'triunvirato av. 5463|villa urquiza' (-34.5779008, -58.481073): se copia.
--   6. cod 2499 Maravillas de Concepción "Exp. Mostto- Pergamino — PERGAMINO 3751- NAVE D- MOD 90, SOLDATI"
--      (E12D 17/09, LK 0046/0047) → es el depósito de Pergamino 3751 (PPP_Geo lo tiene): se copia.
--   7. cod 4036 Perez Zarate "Alem 385-Cordoba" barrio Soldati (E12D 17/09, común en el listado pero
--      NO lo es) → la dirección es la del CLIENTE en Córdoba capital y el pedido no dice por qué
--      expreso sale. GV_Geo_Fallidas: 14 intentos. No se puede geocodificar hasta que la página
--      (o compras) diga el expreso; hoy cuenta la parada (15') sin km. Queda para Thomas / la página.
--   8. cod 1996 Del Plastic "Exp. — Taabre 1240" Pompeya (E12H 17/09, CH 0018)
--      → "Taabre" es un typo de "Tabaré" (calle de Nueva Pompeya). Sin internet no hay lat/lng: queda
--      <LAT>/<LNG>; si se corrige el tipeo en el pedido el cron lo resuelve solo.
-- ---------------------------------------------------------------------------
insert into public."GV_Geo_Cliente" (cod, dir_key, razon_social, direccion, barrio, lat, lng, comp, fuente, manual, usos, precision)
values
  -- 1. Coto: misma dirección, clave exacta de la página
  ('801',  'los andes 1381 - e.echeverría cd|esteban echeverría', 'Coto C.I.C.S.A.', 'Los Andes 1381 - E.Echeverría CD', 'Esteban Echeverría',
           -34.7816861, -58.4904123, null, 'copia de GV_Geo_Cliente 801 (los andes 1381) v16.72', true, 1, 'manual'),
  -- 4. Bazar Mandarin LK: depósito del expreso Fantacci = Beazley 3519 (PPP_Geo)
  ('2447', 'exp. fantacci — beazley 3519, nueva pompeya (calle 50 n 637-la plata (l.1))|pompeya', 'Bazar Mandarin S.R.L.',
           'Exp. Fantacci — BEAZLEY 3519, NUEVA POMPEYA (Calle 50 N 637-La Plata (L.1))', 'Pompeya',
           -34.652842, -58.4093048, null, 'copia de PPP_Geo beazley 3519|nueva pompeya v16.72', true, 1, 'manual'),
  -- 5. Gastronomia Gonzalez: PPP_Geo triunvirato av. 5463|villa urquiza
  ('2445', 'triunvirato av. 5463-v.urquiza|villa urquiza', 'Gastronomia Gonzalez SRL.', 'Triunvirato Av. 5463-V.Urquiza', 'Villa Urquiza',
           -34.5779008, -58.481073, null, 'copia de PPP_Geo triunvirato av. 5463|villa urquiza v16.72', true, 1, 'manual'),
  -- 6. Maravillas de Concepción: depósito Pergamino 3751 (PPP_Geo)
  ('2499', 'exp. mostto- pergamino — pergamino 3751- nave d- mod 90, soldati (rocamora 823- c. de uruguay)|soldati',
           'Maravillas De Concepcion SRL', 'Exp. Mostto- Pergamino — PERGAMINO 3751- NAVE D- MOD 90, SOLDATI (Rocamora 823- C. De Uruguay)', 'Soldati',
           -34.6684525, -58.4363995, null, 'copia de PPP_Geo pergamino 3751|soldati v16.72', true, 1, 'manual')
  -- 8. Del Plastic (Tabaré 1240, Nueva Pompeya): completar y descomentar cuando haya lat/lng
  -- ,('1996', 'exp. — taabre 1240 (rioja 627-cordoba)|pompeya', 'Del Plastic S.R.L ( E F )', 'Exp.  — Taabre 1240 (Rioja 627-Cordoba)', 'Pompeya',
  --          <LAT>, <LNG>, null, 'google_maps_dueño', true, 1, 'manual')
on conflict (cod, dir_key) do nothing;                                        -- espera 4 filas

-- 5. sacar a 2445 de las fallidas para que el cron no la siga contando (14/16 intentos): la manual ya está
delete from public."GV_Geo_Fallidas" where cod = '2445' and dir_key = 'triunvirato av. 5463-v.urquiza|villa urquiza';

-- verificación
select cod, dir_key, lat, lng, fuente from public."GV_Geo_Cliente"
 where (cod, dir_key) in (('801','los andes 1381 - e.echeverría cd|esteban echeverría'),
                          ('2447','exp. fantacci — beazley 3519, nueva pompeya (calle 50 n 637-la plata (l.1))|pompeya'),
                          ('2445','triunvirato av. 5463-v.urquiza|villa urquiza'),
                          ('2499','exp. mostto- pergamino — pergamino 3751- nave d- mod 90, soldati (rocamora 823- c. de uruguay)|soldati'));
select * from public."GV_Geo_Fallidas" where cod in ('2445','4036','1996','2444');

-- ---------------------------------------------------------------------------
-- ROLLBACK
-- ---------------------------------------------------------------------------
-- update public."GV_PPP_Prog_Override" set zona = null where np = '97889';   -- o borrar la fila si no existía:
-- delete from public."GV_PPP_Prog_Override" o where o.np = '97889' and not exists (select 1 from zz_backups."GV_Backup_prog_override_20260913" b where b.np = '97889');
-- vista: la misma de arriba con `p.zona` en vez del COALESCE; después `alter table public."GV_PPP_Prog_Override" drop column zona;`
-- delete from public."GV_Geo_Cliente" where (cod, dir_key) in (las 5 claves de arriba);
