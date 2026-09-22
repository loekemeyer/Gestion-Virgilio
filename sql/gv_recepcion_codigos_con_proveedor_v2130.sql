-- ============================================================================
-- v21.30 — RECEPCIÓN: que todo código con proveedor figure en el módulo de operarios
-- Pedido de Luis (2026-09-22): "fijate de todos los productos que tengan un proveedor
-- y que no figuren en el modulo de operarios para recibirlos. ajustalos a todos."
--
-- ✅ APLICADO el 2026-09-22 con el OK de Luis. Backup: zz_backups."GV_Backup_ArtXTall_20260922"
--    (335 filas). Resultado real: INSERT 40 · 335 -> 375. Verificado como `anon`.
--
-- MEDICIÓN (22/09). El universo son los 238 códigos activos de OC_Maximos con
-- proveedor. Lo que el operario ve al elegir a ese proveedor sale de DOS lugares:
--
--   tipo 'tallerista' -> "Articulos Virgilio X Tallerista" por Cod_Tallerista + Linea
--   tipo 'prov_at'    -> vista_articulos_prov_at por proveedor + linea
--
-- y el nombre del proveedor de OC_Maximos se resuelve contra la entidad con
-- gv_prov_match (el mismo matcher del resto del sistema: "Martin C" = Martin,
-- "Carlos E" = Carlos, "Pettofrezza" = Rafael, "Blistpack" = Blist-Pack).
--
--   ⚠ Un barrido por NOMBRE crudo da 91 códigos "a nombre de otro" que NO son un
--     problema: son esos alias. El barrido que vale usa gv_prov_match.
--
-- Resultado: faltan 49 (código, línea). De ésos:
--   · 42  se pueden dar de alta con el dato que ya está en la base   <- este archivo
--   ·  5  son de Blist-Pack línea CH y NO se pueden: "Codigos X Tallerista" no tiene
--         la fila CH de Blist-Pack, así que el operario no tiene código que elegir.
--         Falta ese dato -> lo define Luis (758, 762, 763, 764, 769).
--   ·  1  era 581T (Martin, LK): no tenia Uni_x_Caja en ninguna tabla y la columna es
--         NOT NULL. Luis lo dicto (18), pero despues dijo que es DISCONTINUO -> no entra.
--
-- ⚠ LAS TRES CORRECCIONES DE LUIS (22/09), que son lo que baja 43 a 40:
--   · 231, 232, 233 (palos de amasar) -> "los hace log fabr", NO Tierra Nativa. Van bajo
--     Log/ Fabr. El dato no lo desmiente: esos 3 codigos tienen CERO entregas registradas,
--     asi que nunca se recibieron a nombre de nadie. (El 55215, Palo de Amasar 40, SI es de
--     Tierra Nativa: 208 cajas el 26/08. Son cosas distintas.)
--   · 582E y 119 -> "no se fabrica, se importa listo para la venta (descuenta de racks)".
--     Un importado no se recibe por el modulo de talleristas: NO entran.
--   · 581T -> "es discontinuo realmente, si no genera OC no me jode". Medido: `total = 0`
--     en vista_generador_oc, asi que hoy NO genera OC. NO entra.
--   ·  1  es 193 (Kuffo, prov_at) -> bloque B, es otra cosa.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) BACKUP (protocolo). La clave real de la tabla es `id` (identity, única).
-- ----------------------------------------------------------------------------
create table zz_backups."GV_Backup_ArtXTall_20260922" as
  select * from public."Articulos Virgilio X Tallerista";
alter table zz_backups."GV_Backup_ArtXTall_20260922" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GV_Backup_ArtXTall_20260922"
  from anon, authenticated;

-- ----------------------------------------------------------------------------
-- A) ALTA de los 40. Es ADITIVO: sólo INSERT, ningún update ni delete.
--    El SELECT se recalcula al correr, así que no puede desfasarse de la medición.
--    Desc  <- la que ya tenga ese código en la tabla, si no OC_Maximos.descripcion,
--             si no stocks_carga_rapida.descripcion, si no el código pelado.
--    UxB   <- la que ya tenga ese código en la tabla, si no vista_uxb_articulo, si no
--             Sin UxB no se inserta: la columna es NOT NULL.
-- ----------------------------------------------------------------------------
insert into public."Articulos Virgilio X Tallerista"
       ("Linea", "Cod_Art", "Desc", "Tallerista", "Uni_x_Caja", "Cod_Tallerista")
with ocm as (
  select btrim(cod) cod, btrim(proveedor) prov,
         upper(btrim(coalesce(nullif(linea,''),'LK'))) linea,
         btrim(coalesce(descripcion,'')) desc_, public.gv_norm_prov_keys(proveedor) k
    from public."OC_Maximos"
   where activo and nullif(btrim(proveedor),'') is not null),
ct as (
  select btrim("Nombre") nombre, upper(btrim("Linea")) linea, btrim("Codigo") codigo,
         public.gv_norm_prov_keys("Nombre") k
    from public."Codigos X Tallerista"
   where nullif(btrim("Codigo"),'') is not null),
yaesta as (
  select distinct btrim("Cod_Art") cod, btrim("Cod_Tallerista") tcod,
         upper(btrim(coalesce("Linea",''))) linea
    from public."Articulos Virgilio X Tallerista"),
-- Correcciones dictadas por Luis (22/09). Al agregar otra, va aca y en ningun otro lado.
excluir(cod) as (values ('582E'), ('119'), ('581T')),   -- importados y discontinuo
prov_override(cod, prov) as (values ('231','Log/ Fabr'), ('232','Log/ Fabr'), ('233','Log/ Fabr'))
select o.linea, o.cod,
       coalesce(
         nullif((select max(x."Desc") from public."Articulos Virgilio X Tallerista" x
                  where btrim(x."Cod_Art") = o.cod), ''),
         nullif(o.desc_, ''),
         nullif((select max(s.descripcion) from public.stocks_carga_rapida s
                  where btrim(s.cod_base) = o.cod), ''),
         o.cod) as "Desc",
       c.nombre,
       (select coalesce(
          (select max(x."Uni_x_Caja") from public."Articulos Virgilio X Tallerista" x
            where btrim(x."Cod_Art") = o.cod),
          (select round(u.uxb)::int from public.vista_uxb_articulo u
            where btrim(u.cod) = o.cod))) as "Uni_x_Caja",
       c.codigo
  from ocm o
  join ct c on c.linea = o.linea and (
        case when exists (select 1 from prov_override v where v.cod = o.cod)
             then public.gv_prov_match(
                    public.gv_norm_prov_keys((select v.prov from prov_override v where v.cod = o.cod)),
                    c.k)
             else public.gv_prov_match(o.k, c.k) end)
 where not exists (select 1 from excluir e where e.cod = o.cod)
   and not exists (select 1 from yaesta a
                    where a.cod = o.cod and a.tcod = c.codigo and a.linea = o.linea)
   and coalesce(
         (select max(x."Uni_x_Caja") from public."Articulos Virgilio X Tallerista" x
           where btrim(x."Cod_Art") = o.cod),
         (select round(u.uxb)::int from public.vista_uxb_articulo u
           where btrim(u.cod) = o.cod)) is not null;
-- APLICADO: INSERT 0 40 (Log/ Fabr LK 20 · Log/ Fabr CH 11 · Blist-Pack 5 · Martin 2 ·
--            Garcia CH 1 · Pedernera 1). Verificado como anon: el boton de Log/ Fabr LK
--            muestra 207, 229, 231, 232, 233, 234.

-- ----------------------------------------------------------------------------
-- B) 193 (Tostador Enlozado, Kuffo) — NO es un alta: es la LÍNEA de la vista.
--
--    vista_articulos_prov_at saca `linea` de un LATERAL contra
--    "Articulos Virgilio X Tallerista" (LIMIT 1). O sea: la línea de un artículo de
--    prov AT la decide una tabla de TALLERISTAS, que no tiene nada que ver. El 193 no
--    está ahí, así que sale con linea = '' y el `.eq("linea","LK")` del celular no lo
--    encuentra nunca. Es el ÚNICO de los 87 (medido: 86 con una línea, 0 ambiguos).
--
--    ⚠ NO se arregla metiéndole una fila de tallerista al 193: eso lo haría aparecer
--      además en la grilla de ese tallerista, que es justo lo contrario de lo pedido.
--    El arreglo es el fallback a OC_Maximos.linea dentro de la vista.
--    (reloptions ANTES: verificar con
--       select relname, reloptions from pg_class where oid='public.vista_articulos_prov_at'::regclass;)
-- ----------------------------------------------------------------------------
create or replace view public.vista_articulos_prov_at as
 select distinct on (a."Cod_Art", a."Proveedor")
        a."Proveedor"   as proveedor,
        a."Cod_Art"     as cod_art,
        a."Descripcion" as descripcion,
        coalesce(nullif(t."Linea", ''),
                 nullif(upper(btrim(m.linea)), ''),      -- v21.30: fallback
                 '')::character varying as linea
   from "Articulos x Prov AT" a
   left join lateral (
        select "Articulos Virgilio X Tallerista"."Linea"
          from "Articulos Virgilio X Tallerista"
         where "Articulos Virgilio X Tallerista"."Cod_Art"::text = a."Cod_Art"
         limit 1) t on true
   left join lateral (
        select o.linea
          from public."OC_Maximos" o
         where btrim(o.cod) = btrim(a."Cod_Art") and o.activo
         limit 1) m on true
  where a."Activo" = true
  order by a."Cod_Art", a."Proveedor";

-- la opción NO la conserva `create or replace view`: va siempre.
alter view public.vista_articulos_prov_at set (security_invoker = true);

-- ----------------------------------------------------------------------------
-- VERIFICACIÓN (tiene que dar 0 filas, salvo lo que queda pendiente de dato)
-- ----------------------------------------------------------------------------
with ocm as (
  select btrim(cod) cod, btrim(proveedor) prov,
         upper(btrim(coalesce(nullif(linea,''),'LK'))) linea,
         public.gv_norm_prov_keys(proveedor) k
    from public."OC_Maximos" where activo and nullif(btrim(proveedor),'') is not null),
ent as (select tipo, nombre, cod_lk, cod_ch, public.gv_norm_prov_keys(nombre) k
          from public.vista_entidades_recepcion),
ve as (select distinct btrim(cod_art) cod, btrim(proveedor) prov,
              upper(btrim(coalesce(linea,''))) linea from public.vista_articulos_prov_at),
at as (select distinct btrim("Cod_Art") cod, btrim("Cod_Tallerista") tcod,
              upper(btrim(coalesce("Linea",''))) linea
         from public."Articulos Virgilio X Tallerista")
select o.cod, o.linea, o.prov
  from ocm o
 where not exists (
   select 1 from ent e where public.gv_prov_match(o.k, e.k) and (
     case when e.tipo = 'prov_at'
            then exists (select 1 from ve v
                          where v.cod = o.cod and lower(v.prov) = lower(e.nombre)
                            and v.linea = o.linea)
          else exists (select 1 from at a
                        where a.cod = o.cod
                          and a.tcod = (case when o.linea='CH' then e.cod_ch else e.cod_lk end)
                          and a.linea = o.linea) end))
 order by 3, 2, 1;
-- DESPUES DE APLICAR: 11 filas, y las 11 estan explicadas.
--   · 758 762 763 764 769  CH  Blistpack   -> falta el codigo CH de Blist-Pack (abierto)
--   · 582E · 119                           -> importados, no se reciben por talleristas
--   · 581T                                 -> discontinuo
--   · 231 · 232 · 233                      -> ⚠ el operario YA los ve bien (botón Log/ Fabr).
--     Salen listados porque `OC_Maximos.proveedor` todavia dice **Tierra Nativa** y el
--     barrido compara contra la config. El arreglo es la config, y es OTRA escritura:
--     hoy esos 3 generan OC a Tierra Nativa por 5 + 7 + 5 = 17 cajas (todo por pedidos;
--     proy 0, cap 0, stock 0). SQL propuesto, pendiente del "si" de Luis:
--
--       create table zz_backups."GV_Backup_OCMaximos_palos_20260922" as
--         select * from public."OC_Maximos" where btrim(cod) in ('231','232','233');
--       alter table zz_backups."GV_Backup_OCMaximos_palos_20260922" enable row level security;
--       update public."OC_Maximos" set proveedor = 'Log/ Fabr'
--        where btrim(cod) in ('231','232','233');
--   758 / 762 / 763 / 764 / 769  CH  Blistpack  -> falta el código CH de Blist-Pack.
--   Luis, 22/09: "nose". Y el dato tampoco esta en la operacion: de las 21 entregas de
--   Blist-Pack (03/02 al 21/09) NINGUNA es de la linea CH -- son 500, 506, 510, 557 y 558,
--   todos LK. O sea que esos 5 codigos de bombillas nunca se recibieron a su nombre.
--   NO se inventa un codigo: queda abierto hasta que el dueño lo diga.

-- ----------------------------------------------------------------------------
-- ROLLBACK
-- ----------------------------------------------------------------------------
-- delete from public."Articulos Virgilio X Tallerista" t
--  where not exists (select 1 from zz_backups."GV_Backup_ArtXTall_20260922" b where b.id = t.id);
-- y la vista, volviendo a la definición sin el segundo LATERAL (+ security_invoker).
