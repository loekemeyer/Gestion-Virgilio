-- v22.75 (Luis, 25/09): Capacidad_Sector deja de ser TABLA y pasa a ser VISTA sobre GV_Lugar_Item.
-- Una sola fuente para "qué va en cada celda y cuántas cajas entran": GV_Lugar_Item.
-- Antes: 3 escrituras del front (Importar, Borrar todo, dpSaveCap) + el espejo de
-- gv_lugar_item_guardar/sacar, y las dos tablas se desincronizaban (654 celdas sin capacidad en el mapa).
--
-- Paso previo (hecho con el sí de Luis, 25/09): se copió la capacidad a GV_Lugar_Item (670 filas),
-- normalizando los sectores mal escritos (J1->J01, C-08->C08...). Backups:
--   zz_backups."GV_Backup_CapacidadSector_20260925_unif"  (742 filas)
--   zz_backups."GV_Backup_LugarItem_20260925_unif"        (796 filas)
-- Diferencia medida en la suma de capacidad por código: sólo 828 (-45, fila C-08 errónea: el relevamiento
-- del 11/09 dice C08 = 539E) y 865E (-60, su celda L57 está inactiva en el mapa; L57 tiene 865ED).
--
-- La tabla vieja queda como public."Capacidad_Sector_legacy" (sin escritura) para el rollback.
--
-- ROLLBACK (una transacción):
--   drop view public."Capacidad_Sector" cascade;          -- ojo: se lleva los 13 dependientes
--   alter table public."Capacidad_Sector_legacy" rename to "Capacidad_Sector";
--   -- y recrear los 13 dependientes con el mismo bloque de captura/recreación de abajo.
-- El bloque DO de abajo es el que se corrió; captura las definiciones VIVAS en el momento.
do $swap$
declare
  r record; v_n int := 0; v_res text; g record; i text;
  v_objs text[] := array[]::text[];
begin
  create temp table _dep on commit drop as
  with recursive dep as (
    select c.oid, c.relname::text rel, c.relkind, 1 lvl from pg_class c where c.oid = 'public."Capacidad_Sector"'::regclass
    union
    select c.oid, c.relname::text, c.relkind, dep.lvl + 1 from dep
      join pg_depend d on d.refobjid = dep.oid join pg_rewrite rw on rw.oid = d.objid
      join pg_class c on c.oid = rw.ev_class and c.oid <> dep.oid)
  select rel, relkind, max(lvl) lvl from dep where lvl > 1 group by rel, relkind;

  create temp table _def on commit drop as
  select d.rel, d.relkind, d.lvl, pg_get_viewdef(c.oid, true) def, c.reloptions opts,
         obj_description(c.oid, 'pg_class') cmt,
         array(select indexdef from pg_indexes where schemaname='public' and tablename=d.rel) idx,
         array(select format('grant %s on public.%I to %s', a.privilege_type, d.rel,
                  case when a.grantee = 0 then 'public' else quote_ident(pg_get_userbyid(a.grantee)) end)
                from aclexplode(c.relacl) a where a.grantee <> c.relowner) grants
    from _dep d join pg_class c on c.relname = d.rel and c.relnamespace = 'public'::regnamespace;

  -- 1) la tabla vieja queda al costado, sin escritura
  alter table public."Capacidad_Sector" rename to "Capacidad_Sector_legacy";
  revoke insert, update, delete, truncate on public."Capacidad_Sector_legacy" from anon, authenticated;

  -- 2) la vista, sobre la fuente canónica
  create view public."Capacidad_Sector" with (security_invoker = true) as
  select abs(hashtextextended(i.sector || '|' || i.cod, 0))::bigint as id,
         i.sector, i.cod, i.cajas_max, i.created_at, l.empresa
    from public."GV_Lugar_Item" i
    join public."GV_Lugar" l on l.sector = i.sector
   where coalesce(i.activo, true) and i.clase = 'articulo' and i.cajas_max is not null;
  comment on view public."Capacidad_Sector" is
    'v22.75: VISTA sobre GV_Lugar_Item (la fuente canónica de góndola). Escribir por gv_lugar_item_guardar / gv_lugar_item_sacar. La tabla vieja es Capacidad_Sector_legacy.';
  grant select on public."Capacidad_Sector" to anon, authenticated;
  -- sin DELETE a propósito: «Borrar toda la capacidad» (id=gt.0) ya no puede vaciar nada.
  grant insert, update on public."Capacidad_Sector" to authenticated;

  -- 3) dependientes: se tiran y se recrean con su definición VIVA (ahora resuelven a la vista)
  for r in select * from _def order by lvl desc loop
    if r.relkind = 'm' then execute format('drop materialized view if exists public.%I cascade', r.rel);
    else execute format('drop view if exists public.%I cascade', r.rel); end if;
  end loop;
  for r in select * from _def order by lvl, rel loop
    if r.relkind = 'm' then
      execute format('create materialized view public.%I %s as %s', r.rel,
        case when r.opts is not null then 'with (' || array_to_string(r.opts, ',') || ')' else '' end, r.def);
      foreach i in array r.idx loop execute i; end loop;
    else
      execute format('create view public.%I %s as %s', r.rel,
        case when r.opts is not null then 'with (' || array_to_string(r.opts, ',') || ')' else '' end, r.def);
    end if;
    foreach i in array r.grants loop execute i; end loop;
    if r.cmt is not null then
      execute format('comment on %s public.%I is %L', case when r.relkind='m' then 'materialized view' else 'view' end, r.rel, r.cmt);
    end if;
    v_n := v_n + 1; v_objs := v_objs || r.rel;
  end loop;


  -- 4) las dos RPC del editor dejan de escribir el espejo (ahora es vista sobre su misma tabla)
  declare d text; d2 text;
  begin
    d := pg_get_functiondef('public.gv_lugar_item_guardar(text,text,text,numeric)'::regprocedure);
    d2 := regexp_replace(d, 'delete from public\."Capacidad_Sector"\s+where upper\(btrim\(sector\)\) = v_key and upper\(btrim\(cod\)\) = ''LIBRE'';', '-- v22.75: sin espejo LIBRE (Capacidad_Sector es vista).');
    d2 := regexp_replace(d2, 'if p_cajas_max is null then\s+delete from public\."Capacidad_Sector".*?end if;', '-- v22.75: Capacidad_Sector es VISTA sobre GV_Lugar_Item: el espejo ya no se escribe.');
    if d2 = d or d2 ~ 'Capacidad_Sector"\s+\(' or d2 ~ 'delete from public\."Capacidad_Sector"' then
      raise exception 'gv_lugar_item_guardar: el texto no matcheó, no se toca';
    end if;
    execute d2;
    d := pg_get_functiondef('public.gv_lugar_item_sacar(text,text,text)'::regprocedure);
    d2 := regexp_replace(d, 'delete from public\."Capacidad_Sector"\s+where upper\(btrim\(sector\)\) = v_key\s+and cod = v_cod;\s+get diagnostics v_c = row_count;',
          '-- v22.75: Capacidad_Sector es VISTA sobre GV_Lugar_Item: lo que sale del mapa sale de la capacidad.' || chr(10) || '  v_c := v_m;');
    if d2 = d or d2 ~ 'delete from public\."Capacidad_Sector"' then
      raise exception 'gv_lugar_item_sacar: el texto no matcheó, no se toca';
    end if;
    execute d2;
  end;

  -- 5) escribir en la vista (front viejo / Producción) = escribir en GV_Lugar_Item por la RPC,
  --    que valida que el lugar exista en GV_Lugar (un "A-62" se rechaza).
  execute $f$
  create or replace function public.gv_capacidad_sector_escribir() returns trigger
  language plpgsql set search_path = public as $b$
  begin
    if tg_op = 'UPDATE' and (old.sector is distinct from new.sector or old.cod is distinct from new.cod) then
      raise exception 'Capacidad_Sector es una vista: para mover un código de celda usá el Mapa de góndolas.';
    end if;
    perform public.gv_lugar_item_guardar(new.sector, new.cod, 'articulo', new.cajas_max);
    return new;
  end $b$ $f$;
  create trigger gv_capacidad_sector_escribir instead of insert or update on public."Capacidad_Sector"
    for each row execute function public.gv_capacidad_sector_escribir();

  select string_agg(format('%s:%s', rel, lvl), ' ') into v_res from _def;
  raise notice 'recreados %: %', v_n, v_res;

end $swap$;
