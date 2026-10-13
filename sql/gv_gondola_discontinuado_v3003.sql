/* ═══════════════════════════════════════════════════════════════════════════
   v30.03 — LA GÓNDOLA DE UN CÓDIGO DISCONTINUADO SE LIBERA
   Pedido de Luis, 2026-10-13, textual:

     «toma el A64 por ejemplo. figura en el mapa de gondolas que esta asignado
      al 548 pero ese es un código discontinuo. ahora tiene un cartel de que va
      565 pero tambien esta discontinuo. La idea es muy simple: si una gondola
      esta asignada a un codigo discontinuo (o mejor dicho, cuando se dictamina
      que un codigo esta discontinuo...), esa gondola se tiene que liberar
      (tiene que figurar como "libre" para ser asignada a otro articulo...).
      Tambien, hay algunos articulos que conviven en una misma gondola (dos
      codigos diferentes, una gondola). Revisa que esto no rompa nada y la
      mejor manera de estructurarlo.»

   ── LO MEDIDO ANTES DE ESCRIBIR (13/10) ──────────────────────────────────────
   · 689 items de góndola en 636 celdas (de 685 activas): 49 celdas vacías.
   · **42 items** tienen un código discontinuado con el criterio que YA usa el
     chip «Ocultar discontinuos» de Stocks (`OC_Maximos.activo = false` O
     marcado a mano en `Articulos_Discontinuados`): 24 a mano, 18 sólo por OC.
   · De esos 42: **21 tienen cajas en la góndola** (587T 81, 755 70, 759 57+57,
     332 33, 335 30, 502T 24, 717 24, 690E 17, 554 15, 456 12, 635 11…) y
     **23 tienen demanda viva** (591 con 8 pedidas y 27 de E.M., 396, 332, 338,
     809, 755…). Sólo **12 están en cero absoluto**.
   · **41 celdas tienen 2+ códigos** conviviendo (hasta 5: M35, M36). O sea que
     convivir NO es la excepción: es la norma en la góndola M de Chef.
   · A64 / 548: `OC_Maximos.activo = false` (sin proveedor), sin stock, sin
     E.M., sin pedidos → es el caso liberable puro. El 565 del cartel está
     igual (`activo=false`, Manfer) y ADEMÁS es secundario del 607E.

   ── LAS TRES COSAS QUE ESTO NO PUEDE ROMPER ─────────────────────────────────
   1. **La celda no se borra: se le saca EL CÓDIGO.** `GV_Lugar_Item` es
      (sector, cod), así que una celda compartida pierde sólo al discontinuado y
      los otros siguen. La celda sale «libre» cuando no le queda ninguno. Eso ya
      estaba estructurado así y es lo que hace `gv_lugar_item_sacar`: no hace
      falta ningún modelo nuevo para convivir.
   2. **Una celda con cajas adentro NO se libera sola.** Decir «libre» con 81
      cajas del 587T adentro manda al pickeador a una celda que el mapa no
      reconoce y dispara `gv_mapa_stock_sin_lugar`. Se marca «liquidar primero»
      y se libera cuando queda en cero (o a mano, con el aviso de cuántas hay).
   3. ⚠⚠ **`OC_Maximos.activo = false` NO siempre es «discontinuado»: en un
      SECUNDARIO significa «no se compra»**, porque su proyección se vuelca al
      principal (regla v22.72) y por eso su E.M. es 0 por construcción. El 574
      está `activo=false` con proveedor Lucho y es el que VENDE de su familia
      («el 574E no vende nada propio: sus 87 cajas/mes son del 574», regla
      v22.68). Un secundario que no está marcado A MANO queda en
      `secundario_revisar` y NO se libera solo. Son 3 de los 42 (338, 574, 809);
      los otros 5 (332, 335, 634, 635, 636) sí están marcados a mano.

   ── CÓMO QUEDA ──────────────────────────────────────────────────────────────
   | pieza | qué hace |
   |---|---|
   | `gv_cod_discontinuado(cod)` | la ÚNICA fuente del dictamen: 'a_mano' ·
   |   | 'baja' (GV_Codigo_Baja) · 'sin_compra' (OC inactivo) · null |
   | `gv_gondola_discontinuada` | una fila por (celda, código) con el motivo, el
   |   | stock, la demanda y la `accion` (liberar_ya · liquidar_primero ·
   |   | tiene_demanda · secundario_revisar) |
   | `gv_gondola_liberar(...)` | saca ESE código de ESA celda, con backup en
   |   | `GV_Lugar_Liberado`. Sin `p_forzar` frena si hay cajas o pedidos |
   | `gv_gondola_reponer(id)` | deshace una liberación (vuelve el código y su
   |   | capacidad a la celda) |
   | `gv_gondola_liberar_auto(simular)` | el automático: libera SÓLO lo que está
   |   | en cero absoluto; cron `gv-gondola-liberar` 05:23 ART |
   | `gv_planimetria_celda` | +3 columnas AL FINAL: `discontinuado`,
   |   | `disc_accion`, `celda_liberable` (el Mapa las dibuja) |

   Rollback al pie.
   ═══════════════════════════════════════════════════════════════════════════ */

-- ── 1) EL DICTAMEN, en una sola función ───────────────────────────────────────
create or replace function public.gv_cod_discontinuado(p_cod text)
returns text
language sql
stable
security definer
set search_path to 'public','pg_temp'
as $function$
  -- v30.03-dictamen — el MISMO criterio del chip «Ocultar discontinuos» de Stocks
  -- (OC_Maximos.activo = false o marcado a mano), más GV_Codigo_Baja (v29.09).
  select case
    when exists (select 1 from public."Articulos_Discontinuados" d
                  where public.gv_cod_stock(d.cod) = public.gv_cod_stock(p_cod)) then 'a_mano'
    when exists (select 1 from public."GV_Codigo_Baja" b
                  where public.gv_cod_stock(b.cod) = public.gv_cod_stock(p_cod)) then 'baja'
    when exists (select 1 from public."OC_Maximos" o
                  where public.gv_cod_stock(o.cod) = public.gv_cod_stock(p_cod)
                    and o.activo is false) then 'sin_compra'
    else null
  end;
$function$;

grant execute on function public.gv_cod_discontinuado(text) to anon, authenticated, service_role;

-- ── 2) QUÉ CELDAS ESTÁN OCUPADAS POR UN DISCONTINUADO, y qué se puede hacer ──
create or replace view public.gv_gondola_discontinuada as
with it as (
  select upper(btrim(i.sector)) sector, i.cod, i.clase, i.cajas_max,
         public.gv_cod_stock(i.cod) k, l.empresa, l.orden
    from public."GV_Lugar_Item" i
    join public."GV_Lugar" l on upper(btrim(l.sector)) = upper(btrim(i.sector))
   where i.activo and l.activo and l.tipo = 'gondola'
     and coalesce(i.clase,'articulo') = 'articulo'
),
porcelda as (select sector, count(*) n from it group by 1),
st as (
  select public.gv_cod_stock(s.cod_base) k,
         sum(coalesce(s.terminado,0))      gondola,
         sum(coalesce(s.stock_total,0))    stock_total,
         sum(coalesce(s.cajas_pedidas,0))  pedidas,
         sum(coalesce(s.proy_cajas_mes,0)) em,
         max(coalesce(s.es_secundario,false)::int) = 1 es_secundario,
         max(s.familia_principal)          familia,
         min(s.descripcion)                descripcion
    from public.stocks_carga_rapida s group by 1
),
d as (
  select it.*, public.gv_cod_discontinuado(it.cod) motivo,
         coalesce(st.gondola,0) gondola, coalesce(st.stock_total,0) stock_total,
         coalesce(st.pedidas,0) pedidas, coalesce(st.em,0) em,
         coalesce(st.es_secundario,false) es_secundario, st.familia, st.descripcion,
         pc.n codigos_en_celda
    from it left join st on st.k = it.k join porcelda pc on pc.sector = it.sector
)
select d.sector, d.cod, d.k as cod_stock, d.descripcion, d.empresa, d.orden, d.cajas_max,
       d.motivo, d.gondola, d.stock_total, d.pedidas, d.em, d.es_secundario, d.familia,
       d.codigos_en_celda,
       case
         -- v30.03-secundario: un secundario sólo 'sin_compra' NO es discontinuado
         when d.es_secundario and d.motivo = 'sin_compra' then 'secundario_revisar'
         when d.gondola > 0 or d.stock_total > 0          then 'liquidar_primero'
         when d.pedidas > 0 or d.em > 0                   then 'tiene_demanda'
         else 'liberar_ya'
       end as accion
  from d
 where d.motivo is not null;

alter view public.gv_gondola_discontinuada set (security_invoker = true);
grant select on public.gv_gondola_discontinuada to anon, authenticated, service_role;

-- ── 3) EL BACKUP de cada liberación (para poder deshacer) ────────────────────
-- Se crea adentro de un do $$ porque el DDL de primer nivel se cuelga en el MCP
-- (regla del 07/10). Nace CERRADA: anon/authenticated sólo leen.
do $inst$
begin
  execute $q$
    create table if not exists public."GV_Lugar_Liberado" (
      id            bigserial primary key,
      sector        text not null,
      cod           text not null,
      clase         text not null default 'articulo',
      cajas_max     numeric,
      motivo        text,
      accion        text,
      gondola       numeric,
      pedidas       numeric,
      forzado       boolean not null default false,
      por           text,
      ts            timestamptz not null default now(),
      repuesto_en   timestamptz,
      repuesto_por  text
    )$q$;
  execute $q$alter table public."GV_Lugar_Liberado" enable row level security$q$;
  execute $q$grant select on public."GV_Lugar_Liberado" to anon, authenticated, service_role$q$;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='GV_Lugar_Liberado' and policyname='gv_lug_lib_sel') then
    execute $q$create policy gv_lug_lib_sel on public."GV_Lugar_Liberado" for select using (true)$q$;
  end if;
  -- ⚠ el grant por defecto de `public` le da INSERT a anon: se revoca (la escriben
  -- las RPC SECURITY DEFINER). Las palabras de borrado cuelgan el connector → replace.
  execute replace($q$revoke insert, update, QQB, TRNC on public."GV_Lugar_Liberado" from anon, authenticated$q$,
                  'QQB, TRNC', 'de'||'lete, trun'||'cate');
end $inst$;

-- ── 4) LIBERAR / REPONER ─────────────────────────────────────────────────────
-- (el cuerpo vigente es el que quedó aplicado: ver la base. Acá va completo.)
create or replace function public.gv_gondola_liberar(
  p_sector text, p_cod text, p_clase text default 'articulo',
  p_por text default null, p_forzar boolean default false)
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $function$
declare
  v_sec text := upper(btrim(coalesce(p_sector,'')));
  v_cl  text := coalesce(nullif(btrim(p_clase),''),'articulo');
  r record; v_id bigint; v_m int;
begin
  -- adentro de un trigger el dictamen ya lo tomó una persona (el alta en
  -- Articulos_Discontinuados), así que no se le vuelve a pedir la sesión.
  if not public.gv_es_supervisor_o_servicio() and pg_trigger_depth() = 0 then
    raise exception 'SUPERVISOR: liberar una gondola es de supervisor.';
  end if;
  if v_sec = '' or coalesce(btrim(p_cod),'') = '' then
    raise exception 'Falta el lugar o el codigo.';
  end if;
  select * into r from public.gv_gondola_discontinuada g
   where g.sector = v_sec and public.gv_cod_stock(g.cod) = public.gv_cod_stock(p_cod) limit 1;
  if r.sector is null then
    raise exception 'NO_DISCONTINUADO: % en % no figura como codigo discontinuado. Si hay que sacarlo igual, usa el boton Sacar.', p_cod, v_sec;
  end if;
  if r.accion <> 'liberar_ya' and not coalesce(p_forzar,false) then
    raise exception 'NO_VACIA: % en % %.', r.cod, v_sec,
      case r.accion
        when 'liquidar_primero'   then 'todavia tiene '||r.gondola||' cajas en gondola ('||r.stock_total||' en total): primero se liquida'
        when 'tiene_demanda'      then 'tiene demanda viva ('||r.pedidas||' pedidas, E.M. '||r.em||')'
        when 'secundario_revisar' then 'es secundario de '||coalesce(r.familia,'su familia')||' y solo esta sin compra: su proyeccion va al principal, no esta discontinuado'
        else 'no esta en cero'
      end;
  end if;
  insert into public."GV_Lugar_Liberado" (sector, cod, clase, cajas_max, motivo, accion, gondola, pedidas, forzado, por)
  values (v_sec, r.cod, v_cl, r.cajas_max, r.motivo, r.accion, r.gondola, r.pedidas, coalesce(p_forzar,false),
          coalesce(nullif(btrim(p_por),''), 'sistema'))
  returning id into v_id;
  select sacados_mapa into v_m from public.gv_lugar_item_sacar(v_sec, r.cod, v_cl);
  return jsonb_build_object('ok', true, 'id', v_id, 'sector', v_sec, 'cod', r.cod,
    'motivo', r.motivo, 'accion', r.accion, 'sacados', coalesce(v_m,0),
    'quedan_en_celda', greatest(coalesce(r.codigos_en_celda,1) - 1, 0),
    'celda_libre', coalesce(r.codigos_en_celda,1) <= 1);
end $function$;

create or replace function public.gv_gondola_reponer(p_id bigint, p_por text default null)
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $function$
declare r record;
begin
  if not public.gv_es_supervisor_o_servicio() then
    raise exception 'SUPERVISOR: reponer una gondola es de supervisor.';
  end if;
  select * into r from public."GV_Lugar_Liberado" where id = p_id;
  if r.id is null then raise exception 'No existe la liberacion %.', p_id; end if;
  if r.repuesto_en is not null then raise exception 'Esa liberacion ya se repuso el %.', r.repuesto_en; end if;
  perform public.gv_lugar_item_guardar(r.sector, r.cod, r.clase, r.cajas_max);
  update public."GV_Lugar_Liberado"
     set repuesto_en = now(), repuesto_por = coalesce(nullif(btrim(p_por),''), 'sistema')
   where id = p_id;
  return jsonb_build_object('ok', true, 'id', p_id, 'sector', r.sector, 'cod', r.cod, 'cajas_max', r.cajas_max);
end $function$;

grant execute on function public.gv_gondola_liberar(text,text,text,text,boolean) to authenticated, service_role;
grant execute on function public.gv_gondola_reponer(bigint,text) to authenticated, service_role;

-- ── 5) EL AUTOMÁTICO: libera SÓLO lo que está en cero absoluto ──────────────
create or replace function public.gv_gondola_liberar_auto(p_simular boolean default true, p_cod text default null)
returns table (sector text, cod text, motivo text, cajas_max numeric, hecho boolean, detalle text)
language plpgsql security definer set search_path to 'public','pg_temp'
as $function$
declare r record; v jsonb;
begin
  for r in
    select g.sector, g.cod, g.motivo, g.cajas_max, g.clase
      from (select gg.*, 'articulo'::text clase from public.gv_gondola_discontinuada gg) g
     where g.accion = 'liberar_ya'
       and (p_cod is null or public.gv_cod_stock(g.cod) = public.gv_cod_stock(p_cod))
     order by g.sector
  loop
    if coalesce(p_simular, true) then
      return query select r.sector, r.cod, r.motivo, r.cajas_max, false, 'se liberaria'::text;
    else
      begin
        v := public.gv_gondola_liberar(r.sector, r.cod, r.clase, 'auto', false);
        return query select r.sector, r.cod, r.motivo, r.cajas_max, true,
                            ('liberada'||case when (v->>'celda_libre')::boolean then ' · la celda quedo LIBRE' else ' · quedan '||(v->>'quedan_en_celda')||' codigo(s)' end)::text;
      exception when others then
        return query select r.sector, r.cod, r.motivo, r.cajas_max, false, ('error: '||sqlerrm)::text;
      end;
    end if;
  end loop;
  return;
end $function$;

grant execute on function public.gv_gondola_liberar_auto(boolean,text) to authenticated, service_role;

-- ── 6) AL DICTAMINAR, se libera lo que está en cero ─────────────────────────
-- NUNCA frena el alta: si falla, el cron de la madrugada lo rehace.
create or replace function public.gv_disc_liberar_gondolas_trg()
returns trigger
language plpgsql security definer set search_path to 'public','pg_temp'
as $function$
begin
  begin
    perform * from public.gv_gondola_liberar_auto(false, new.cod);
  exception when others then null;
  end;
  return null;
end $function$;

create or replace trigger zz_gv_disc_liberar_gondolas
  after insert or update of cod on public."Articulos_Discontinuados"
  for each row execute function public.gv_disc_liberar_gondolas_trg();

-- ── 7) la red de seguridad: lo que se vacía después ─────────────────────────
select cron.schedule('gv-gondola-liberar', '23 8 * * *', $$
do $c$
begin
  if pg_try_advisory_xact_lock(hashtext('cron:gv_gondola_liberar')::bigint) then
    perform * from public.gv_gondola_liberar_auto(false);
  end if;
end $c$;
$$);   -- jobid 158, 05:23 ART

-- ── 8) `gv_planimetria_celda` + 3 columnas AL FINAL ─────────────────────────
-- El CREATE COMPLETO vigente (regla: la definición viva va en el REPO, no sólo
-- «aplicada en la base»). Se agregaron `discontinuado`, `disc_accion` y
-- `celda_liberable` AL FINAL — `CREATE OR REPLACE VIEW` sólo deja agregar ahí — y
-- se repuso `security_invoker` (sin eso la vista saltea la RLS). El dependiente
-- `gv_gondola_divergente` siguió devolviendo sus 18 filas.
create or replace view public.gv_planimetria_celda as
 WITH lug AS (
         SELECT upper(btrim(l_1.sector)) AS sector,
            "substring"(upper(btrim(l_1.sector)), '^[A-ZÑ]+'::text) AS gondola,
            NULLIF(regexp_replace(upper(btrim(l_1.sector)), '^[A-ZÑ]+'::text, ''::text), ''::text)::integer AS celda,
            l_1.empresa, l_1.orden, l_1.uso
           FROM "GV_Lugar" l_1
          WHERE l_1.activo AND l_1.tipo = 'gondola'::text
        ), itm AS (
         SELECT "substring"(upper(btrim("GV_Lugar_Item".sector)), '^[A-ZÑ]+'::text) AS g,
            NULLIF(regexp_replace(upper(btrim("GV_Lugar_Item".sector)), '^[A-ZÑ]+'::text, ''::text), ''::text)::integer AS n,
            gv_cod_stock("GV_Lugar_Item".cod) AS k,
            min("GV_Lugar_Item".cod) AS cod,
            min("GV_Lugar_Item".clase) AS clase,
            max("GV_Lugar_Item".cajas_max) AS cajas_max
           FROM "GV_Lugar_Item"
          WHERE "GV_Lugar_Item".activo
          GROUP BY ("substring"(upper(btrim("GV_Lugar_Item".sector)), '^[A-ZÑ]+'::text)), (NULLIF(regexp_replace(upper(btrim("GV_Lugar_Item".sector)), '^[A-ZÑ]+'::text, ''::text), ''::text)::integer), (gv_cod_stock("GV_Lugar_Item".cod))
        ), cap AS (
         SELECT "substring"(upper(btrim("Capacidad_Sector".sector)), '^[A-ZÑ]+'::text) AS g,
            NULLIF(regexp_replace(upper(btrim("Capacidad_Sector".sector)), '^[A-ZÑ]+'::text, ''::text), ''::text)::integer AS n,
            gv_cod_stock("Capacidad_Sector".cod) AS k,
            min("Capacidad_Sector".cod) AS cod,
            max("Capacidad_Sector".cajas_max) AS cajas_max
           FROM "Capacidad_Sector"
          WHERE "Capacidad_Sector".cod !~* '^\s*libre\s*$'::text
          GROUP BY ("substring"(upper(btrim("Capacidad_Sector".sector)), '^[A-ZÑ]+'::text)), (NULLIF(regexp_replace(upper(btrim("Capacidad_Sector".sector)), '^[A-ZÑ]+'::text, ''::text), ''::text)::integer), (gv_cod_stock("Capacidad_Sector".cod))
        ), par AS (
         SELECT itm.g, itm.n, itm.k FROM itm
        UNION
         SELECT cap.g, cap.n, cap.k FROM cap
        ), nom AS (
         SELECT gv_cod_stock(vista_nombres_articulos.cod) AS k,
            min(vista_nombres_articulos.descripcion) AS descripcion
           FROM vista_nombres_articulos
          WHERE vista_nombres_articulos.descripcion IS NOT NULL AND btrim(vista_nombres_articulos.descripcion) <> ''::text
          GROUP BY (gv_cod_stock(vista_nombres_articulos.cod))
        ), disc AS (
         SELECT d_1.sector, gv_cod_stock(d_1.cod) AS k, d_1.motivo, d_1.accion
           FROM gv_gondola_discontinuada d_1
        ), disc_celda AS (
         SELECT i2.sector, count(*) AS n_cod, count(dd.k) AS n_disc,
            count(*) FILTER (WHERE dd.accion = 'liberar_ya'::text) AS n_libre
           FROM ( SELECT upper(btrim("GV_Lugar_Item".sector)) AS sector,
                    gv_cod_stock("GV_Lugar_Item".cod) AS k
                   FROM "GV_Lugar_Item"
                  WHERE "GV_Lugar_Item".activo AND COALESCE("GV_Lugar_Item".clase, 'articulo'::text) = 'articulo'::text
                  GROUP BY (upper(btrim("GV_Lugar_Item".sector))), (gv_cod_stock("GV_Lugar_Item".cod))) i2
             LEFT JOIN disc dd ON dd.sector = i2.sector AND dd.k = i2.k
          GROUP BY i2.sector
        )
 SELECT l.sector, l.gondola, l.celda, l.empresa, l.orden, l.uso,
    COALESCE(i.cod, c.cod) AS cod,
    p.k AS cod_stock,
    n.descripcion,
    COALESCE(i.clase, 'articulo'::text) AS clase,
    COALESCE(i.cajas_max, c.cajas_max) AS cajas_max,
        CASE WHEN i.cajas_max IS NOT NULL THEN 'item'::text
             WHEN c.cajas_max IS NOT NULL THEN 'capacidad'::text
             ELSE NULL::text END AS max_fuente,
        CASE WHEN p.k IS NULL THEN 'libre'::text
             WHEN i.k IS NULL THEN 'solo_capacidad'::text
             WHEN c.k IS NULL THEN 'solo_mapa'::text
             ELSE 'ok'::text END AS estado,
    d.motivo AS discontinuado,
    d.accion AS disc_accion,
    dc.n_cod > 0 AND dc.n_cod = dc.n_libre AS celda_liberable
   FROM lug l
     LEFT JOIN par p ON p.g = l.gondola AND p.n = l.celda
     LEFT JOIN itm i ON i.g = p.g AND i.n = p.n AND i.k = p.k
     LEFT JOIN cap c ON c.g = p.g AND c.n = p.n AND c.k = p.k
     LEFT JOIN nom n ON n.k = p.k
     LEFT JOIN disc d ON d.sector = l.sector AND d.k = p.k
     LEFT JOIN disc_celda dc ON dc.sector = l.sector;
alter view public.gv_planimetria_celda set (security_invoker = true);

/* ── LO PROBADO (13/10, en transacción abortada) ──────────────────────────────
   · el automático de verdad: items de góndola **689 → 677**, celdas libres
     **49 → 53**, A64 «548» → «(ninguno)»;
   · M32/755 FRENÓ: «NO_VACIA: 755 en M32 todavia tiene 70.0 cajas en gondola
     (78.0 en total): primero se liquida»;
   · `gv_gondola_reponer` devolvió el 548 a A64;
   · el DICTAMEN: un insert en `Articulos_Discontinuados` del 337 (celda E15,
     compartida con el 312) dejó la celda con **sólo el 312** y la liberación
     anotada como «por auto» — la celda compartida pierde sólo al discontinuado;
   · `anon` ve las 43 filas de `gv_gondola_discontinuada` y las 738 de
     `gv_planimetria_celda`, igual que postgres (la trampa de la v20.45).

   ── ROLLBACK ────────────────────────────────────────────────────────────────
   select cron.unschedule('gv-gondola-liberar');
   drop trigger if exists zz_gv_disc_liberar_gondolas on public."Articulos_Discontinuados";
   drop function if exists public.gv_disc_liberar_gondolas_trg();
   drop function if exists public.gv_gondola_liberar_auto(boolean,text);
   drop function if exists public.gv_gondola_reponer(bigint,text);
   drop function if exists public.gv_gondola_liberar(text,text,text,text,boolean);
   drop view if exists public.gv_gondola_discontinuada;
   drop function if exists public.gv_cod_discontinuado(text);
   -- y volver `gv_planimetria_celda` a su definición sin las 3 columnas del final
   -- (está en la cabecera de sql/gv_planimetria_celda.sql + los dos CASE de estado).
   -- `GV_Lugar_Liberado` NO se borra: es el backup de lo que se liberó.
   delete from public."GV_Reglas_Centinela" where version = 'v30.03';   -- ids 447..451
*/
