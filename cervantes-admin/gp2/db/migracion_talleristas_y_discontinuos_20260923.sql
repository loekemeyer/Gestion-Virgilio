-- ============================================================================
-- GP2 · Cambios de talleristas finales y discontinuos  (2026-09-23)
-- Pedido del usuario en sesion de Claude. TODO en una transaccion.
-- ============================================================================
begin;

-- ---------------------------------------------------------------- 0) BACKUPS
create table zz_backups."GP2_Backup_Articulo_20260923" as
  select * from "GP2".articulo
   where codigo in ('338','618','070','591','761','818');
alter table zz_backups."GP2_Backup_Articulo_20260923" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GP2_Backup_Articulo_20260923" from anon, authenticated;

create table zz_backups."GP2_Backup_ArtProvAt_20260923" as
  select * from "GP2".articulo_prov_at
   where cod_art in ('338','618','070','591','761','818');
alter table zz_backups."GP2_Backup_ArtProvAt_20260923" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GP2_Backup_ArtProvAt_20260923" from anon, authenticated;

create table zz_backups."GP2_Backup_Ruta_20260923" as
  select r.* from "GP2".ruta r join "GP2".articulo a on a.id = r.articulo_id
   where a.codigo in ('123','355','789','222','910','280','709','908',
                      '557','558','654','658','659','758','759','762','763','769');
alter table zz_backups."GP2_Backup_Ruta_20260923" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GP2_Backup_Ruta_20260923" from anon, authenticated;

create table zz_backups."GP2_Backup_RutaPaso_20260923" as
  select rp.* from "GP2".ruta_paso rp
   join "GP2".ruta r on r.id = rp.ruta_id
   join "GP2".articulo a on a.id = r.articulo_id
   where a.codigo in ('123','355','789','222','910','280','709','908',
                      '557','558','654','658','659','758','759','762','763','769');
alter table zz_backups."GP2_Backup_RutaPaso_20260923" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GP2_Backup_RutaPaso_20260923" from anon, authenticated;

-- ------------------------------------------------- 1) DISCONTINUOS (6 codigos)
update "GP2".articulo set discontinuado = true
 where codigo in ('338','618','070','591','761','818');

-- y se apaga la asignacion al proveedor de articulo terminado, para que no
-- aparezca en Recepcion / Envios de prov AT (5 filas; el 818 no tiene)
update "GP2".articulo_prov_at set activo = false
 where cod_art in ('338','618','070','591','761','818');

-- ----------------------------------- 2) 709 y 908 -> ALEX ESCALANTE (tall. 2)
update "GP2".ruta_paso rp set tallerista_id = 2
  from "GP2".ruta r, "GP2".articulo a, "GP2".componente cs
 where r.id = rp.ruta_id and a.id = r.articulo_id and cs.id = rp.comp_salida_id
   and cs.sector_id = 12 and rp.tipo_paso = 'tallerista'
   and a.codigo in ('709','908');

-- --------------------------------------------- 3) 280 -> FABRICA (tall. 3)
update "GP2".ruta_paso rp set tallerista_id = 3
  from "GP2".ruta r, "GP2".articulo a, "GP2".componente cs
 where r.id = rp.ruta_id and a.id = r.articulo_id and cs.id = rp.comp_salida_id
   and cs.sector_id = 12 and rp.tipo_paso = 'tallerista'
   and a.codigo = '280';

-- ------------------------- 4) BOMBILLAS Y CEPILLOS -> BLIST-PACK SA (tall. 14)
-- (555 y 764 ya estaban en Blist-Pack: no se tocan)
update "GP2".ruta_paso rp set tallerista_id = 14
  from "GP2".ruta r, "GP2".articulo a, "GP2".componente cs
 where r.id = rp.ruta_id and a.id = r.articulo_id and cs.id = rp.comp_salida_id
   and cs.sector_id = 12 and rp.tipo_paso = 'tallerista'
   and a.codigo in ('557','558','654','658','659','758','759','762','763','769');

-- ------------------------------------- 5) 222 y 910 -> SOLO PINTOS (prov AT 10)
-- se borran las rutas de Maspoli (prov AT 6). La ruta de Pintos con el mismo
-- insumo ya existe, asi que no se reasigna: se elimina la duplicada.
delete from "GP2".ruta_paso rp
 using "GP2".ruta r, "GP2".articulo a
 where r.id = rp.ruta_id and a.id = r.articulo_id and a.codigo in ('222','910')
   and exists (select 1 from "GP2".ruta_paso x
                where x.ruta_id = r.id and x.tipo_paso = 'proveedor_at' and x.proveedor_at_id = 6);

delete from "GP2".ruta r
 using "GP2".articulo a
 where a.id = r.articulo_id and a.codigo in ('222','910')
   and not exists (select 1 from "GP2".ruta_paso x where x.ruta_id = r.id);

-- ----------- 6) RUTAS DUPLICADAS PARA EL SEGUNDO TALLERISTA (123, 355, 789)
-- convencion GP2: una ruta por tallerista cuando mas de uno hace el mismo paso.
do $mig$
declare
  v_par record;
  v_ruta record;
  v_nueva bigint;
begin
  for v_par in
    select * from (values ('123', 5, 1),      -- Lucho            -> + Garcia
                          ('355',11, 4),      -- Pettofrezza Raf. -> + German
                          ('789',11, 4)) t(cod, tall_viejo, tall_nuevo)
  loop
    for v_ruta in
      select r.id, r.nombre, r.articulo_id
        from "GP2".ruta r join "GP2".articulo a on a.id = r.articulo_id
       where a.codigo = v_par.cod
         and exists (select 1 from "GP2".ruta_paso rp
                      join "GP2".componente cs on cs.id = rp.comp_salida_id and cs.sector_id = 12
                     where rp.ruta_id = r.id and rp.tipo_paso = 'tallerista'
                       and rp.tallerista_id = v_par.tall_viejo)
    loop
      insert into "GP2".ruta (nombre, articulo_id)
      values (coalesce(v_ruta.nombre, 'Ruta art '||v_par.cod) || ' ('
              || (select nombre from "GP2".tallerista where id = v_par.tall_nuevo) || ')',
              v_ruta.articulo_id)
      returning id into v_nueva;

      insert into "GP2".ruta_paso
        (ruta_id, orden, tipo_paso, matriz_id, proveedor_id, tallerista_id,
         comp_entrada_id, comp_salida_id, cantidad, proveedor_at_id)
      select v_nueva, rp.orden, rp.tipo_paso, rp.matriz_id, rp.proveedor_id,
             case when rp.tipo_paso = 'tallerista' and rp.tallerista_id = v_par.tall_viejo
                  then v_par.tall_nuevo else rp.tallerista_id end,
             rp.comp_entrada_id, rp.comp_salida_id, rp.cantidad, rp.proveedor_at_id
        from "GP2".ruta_paso rp
       where rp.ruta_id = v_ruta.id;
    end loop;
  end loop;
end $mig$;

-- ------------------------------------------------- 7) REPARTO 50 / 50
-- reparto_guardar valida que los dos hagan el paso segun las rutas (por eso va
-- despues del punto 6) y recalcula los maximos de cada tallerista.
select "GP2".reparto_guardar(
         (select id from "GP2".articulo where codigo = '123'),
         (select c.id from "GP2".componente c where c.codigo = '123' and c.sector_id = 12),
         '[{"tallerista_id":1,"pct":50},{"tallerista_id":5,"pct":50}]'::jsonb);

select "GP2".reparto_guardar(
         (select id from "GP2".articulo where codigo = '355'),
         (select c.id from "GP2".componente c where c.codigo = '355' and c.sector_id = 12),
         '[{"tallerista_id":11,"pct":50},{"tallerista_id":4,"pct":50}]'::jsonb);

select "GP2".reparto_guardar(
         (select id from "GP2".articulo where codigo = '789'),
         (select c.id from "GP2".componente c where c.codigo = '789' and c.sector_id = 12),
         '[{"tallerista_id":11,"pct":50},{"tallerista_id":4,"pct":50}]'::jsonb);

commit;

-- ============================================================================
-- VERIFICACION (despues del commit)
-- ============================================================================
-- quien entrega cada uno ahora:
select a.codigo, coalesce(a.discontinuado,false) discontinuado,
       string_agg(distinct coalesce(t.nombre, p.nombre), ' + ') entrega,
       string_agg(distinct rt.pct::text || '%', ' / ') reparto
  from "GP2".articulo a
  left join "GP2".ruta r on r.articulo_id = a.id
  left join "GP2".ruta_paso rp on rp.ruta_id = r.id
  left join "GP2".componente cs on cs.id = rp.comp_salida_id and cs.sector_id = 12
  left join "GP2".tallerista t on t.id = rp.tallerista_id and cs.id is not null
  left join "GP2".proveedor_at p on p.id = rp.proveedor_at_id and cs.id is not null
  left join "GP2".reparto_tallerista rt on rt.articulo_id = a.id and rt.tallerista_id = rp.tallerista_id
 where a.codigo in ('338','618','070','591','761','818','709','908','123','355','789',
                    '222','910','280','555','557','558','654','658','659','758','759',
                    '762','763','764','769')
 group by 1,2 order by 1;

-- ============================================================================
-- APLICADO el 2026-09-23. Ademas de lo de arriba, para que lo discontinuado NO
-- SE VEA (usuario: "lo discontinuado no quiero seguir viendolo en el programa"):
--
--   despiece_verif_bundle : filtro en el bloque 'art' y en rutas_full
--   preavisos_bundle      : filtro en las 3 ramas del CTE z
--
-- Las dos se parchearon sobre pg_get_functiondef (idempotente, con raise si el
-- texto no matchea) y quedaron volcadas en db/funciones_GP2.sql. El front:
-- Programa/Programa.html no ofrece discontinuados y se fue el rotulo.
--
-- LO QUE NO SE TOCO A PROPOSITO:
--   * movimientos_bundle y programa_bundle siguen mandando TODOS los articulos
--     con el flag 'disc': el que decide que se ve es la pantalla.
--   * el ABM de Articulos los sigue mostrando (es donde se los des-discontinua).
--   * GP2.contraparte_alias: el alias CARLOS apunta al tallerista 9 (Carlos
--     Aguirre) y en Virgilio "Carlos" es Alex Escalante. Esta MAL y queda
--     reportado; corregirlo es escribir datos y lo autoriza el dueno.
-- ============================================================================
