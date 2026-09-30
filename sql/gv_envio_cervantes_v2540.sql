-- =====================================================================================
-- v25.40 (Thomas, 30/09, D4): lo que CERVANTES le manda a Virgilio llega como aviso Sí / No
-- donde Virgilio recibe. Es la regla general GP2 <-> GV al revés de la v25.37.
--
--   frontera : "GP2".envio_virgilio (la escribe GP2.enviar_a_virgilio desde la tablet de Cervantes)
--   Sí       : public.gv_envio_cervantes_confirmar(ids, ref, cods, por) — DESPUÉS de que la carga
--              normal de Virgilio grabó (Recepción Log/ Fabr para los terminados, Recibir Insumos
--              para insumos / SC / SP). Sin atajos al stock: el Sí sólo cierra el aviso.
--   No       : public.gv_envio_cervantes_denegar(id, motivo, por) — pasa la fila a 'denegado' y
--              nada más. La reacción es de GP2 (trigger fn_envio_virgilio_denegado: le devuelve
--              el stock a Cervantes) y se ve en la tablet «⛔ Denegado por Virgilio».
--
-- El código de Virgilio de cada envío (cod_gv) NO se adivina:
--   terminado        -> el código del artículo (GP2 y GV usan el mismo: 058, 718, 941E…)
--   insumo / SC / SP -> 1) el que se usó la última vez que se recibió esa MISMA pieza (gv_cod del
--                       último envío confirmado), si todavía existe en public."Insumos";
--                       2) el vínculo de GP2.importado_virgilio_componente, si es uno solo;
--                       3) nada -> la pantalla lo recibe como insumo nuevo (TMP-…) y el Sí guarda
--                       ese código en gv_cod, así el próximo envío ya lo propone.
-- Las tres las ejecuta anon: los operarios de Virgilio entran con sesión anónima.
-- =====================================================================================

create or replace function public.gv_envios_cervantes_pendientes()
 returns table(id bigint, creado_en timestamptz, creado_por text, grupo text, cod_gp2 text, descripcion text,
               cantidad numeric, unidad text, cajas numeric, articulos_por_caja numeric,
               cod_gv text, empresa text, cod_origen text)
 language sql stable security definer set search_path to 'public'
as $function$
  select e.id, e.creado_en, e.creado_por, e.grupo, e.codigo, e.descripcion, e.cantidad, e.unidad,
         e.cajas, e.articulos_por_caja,
         case when e.grupo = 'terminado' then e.codigo else r.cod end,
         case when e.grupo = 'terminado' then public.gv_empresa_de_articulo(e.codigo) end,
         case when e.grupo = 'terminado' then 'articulo' else r.origen end
    from "GP2".envio_virgilio e
    left join lateral (
      select x.cod, x.origen from (
        (select p.gv_cod as cod, 'anterior'::text as origen, 1 as prio
           from "GP2".envio_virgilio p
          where p.componente_id = e.componente_id and p.estado = 'confirmado' and p.gv_cod is not null
            and exists (select 1 from public."Insumos" i where upper(btrim(i.cod)) = upper(btrim(p.gv_cod)))
          order by p.confirmado_en desc nulls last limit 1)
        union all
        (select m.cod_virgilio, 'vinculo'::text, 2
           from "GP2".importado_virgilio_componente m
          where m.componente_id = e.componente_id
            and (select count(*) from "GP2".importado_virgilio_componente m2 where m2.componente_id = e.componente_id) = 1)
      ) x order by x.prio limit 1
    ) r on e.grupo <> 'terminado'
   where e.estado = 'pendiente'
   order by e.creado_en, e.id;
$function$;
comment on function public.gv_envios_cervantes_pendientes() is
  'v25.40 (D4): lo que Cervantes mandó a Virgilio y espera su Sí / No. cod_gv = con qué código se recibe acá (no se adivina: ver sql/gv_envio_cervantes_v2540.sql).';

create or replace function public.gv_envio_cervantes_confirmar(p_ids bigint[], p_ref text default null,
                                                               p_cods jsonb default null, p_por text default null)
 returns jsonb
 language plpgsql security definer set search_path to 'public'
as $function$
declare v_por text := coalesce(nullif(lower(nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'email'), ''),
                               nullif(btrim(p_por), ''), 'virgilio');
        n int; v_ya int;
begin
  if p_ids is null or cardinality(p_ids) = 0 then return jsonb_build_object('ok', true, 'confirmados', 0); end if;
  -- idempotente: lo que ya se confirmó (reintento de la cola del celular) no se toca
  update "GP2".envio_virgilio e
     set estado = 'confirmado', confirmado_en = now(), confirmado_por = v_por,
         gv_ref = nullif(btrim(coalesce(p_ref, '')), ''),
         gv_cod = coalesce(nullif(btrim(p_cods ->> e.id::text), ''), e.gv_cod,
                           case when e.grupo = 'terminado' then e.codigo end)
   where e.id = any(p_ids) and e.estado = 'pendiente';
  get diagnostics n = row_count;
  select count(*) into v_ya from "GP2".envio_virgilio where id = any(p_ids) and estado <> 'pendiente';
  return jsonb_build_object('ok', true, 'confirmados', n, 'cerrados', v_ya);
end $function$;
comment on function public.gv_envio_cervantes_confirmar(bigint[], text, jsonb, text) is
  'v25.40 (D4): Sí de Virgilio. Se llama DESPUÉS de grabar la recepción normal; sólo cierra el aviso y guarda con qué código entró (gv_cod). Idempotente.';

create or replace function public.gv_envio_cervantes_denegar(p_id bigint, p_motivo text default null, p_por text default null)
 returns jsonb
 language plpgsql security definer set search_path to 'public'
as $function$
declare v_por text := coalesce(nullif(lower(nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'email'), ''),
                               nullif(btrim(p_por), ''), 'virgilio');
        r record;
begin
  update "GP2".envio_virgilio
     set estado = 'denegado', denegado_en = now(), denegado_por = v_por,
         denegado_motivo = nullif(btrim(coalesce(p_motivo, '')), '')
   where id = p_id and estado = 'pendiente'
  returning id, estado, revertido_en, revertido_error into r;
  if r.id is null then
    select id, estado, revertido_en, revertido_error into r from "GP2".envio_virgilio where id = p_id;
    if r.id is null then raise exception 'El envío % de Cervantes no existe', p_id; end if;
    return jsonb_build_object('ok', r.estado = 'denegado', 'ya', true, 'estado', r.estado);
  end if;
  -- el stock lo devuelve GP2 (trigger fn_envio_virgilio_denegado); si no pudo, queda a la vista allá
  return jsonb_build_object('ok', true, 'revertido', r.revertido_en is not null, 'error', r.revertido_error);
end $function$;
comment on function public.gv_envio_cervantes_denegar(bigint, text, text) is
  'v25.40 (D4): No de Virgilio. Sólo pasa la fila a denegado; el stock se lo devuelve a Cervantes el trigger de GP2.';

revoke all on function public.gv_envios_cervantes_pendientes() from public;
revoke all on function public.gv_envio_cervantes_confirmar(bigint[], text, jsonb, text) from public;
revoke all on function public.gv_envio_cervantes_denegar(bigint, text, text) from public;
grant execute on function public.gv_envios_cervantes_pendientes() to anon, authenticated;
grant execute on function public.gv_envio_cervantes_confirmar(bigint[], text, jsonb, text) to anon, authenticated;
grant execute on function public.gv_envio_cervantes_denegar(bigint, text, text) to anon, authenticated;

-- centinelas: el Sí y el No sólo tocan lo PENDIENTE (si se pierde, un reintento pisa un denegado)
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select * from (values
  ('gv_envio_cervantes_confirmar', 'funcion', 'e\.estado = ''pendiente''',
   'D4: el Sí de Virgilio sólo confirma lo pendiente (un reintento no pisa un denegado)', 'Thomas', 'v25.40'),
  ('gv_envio_cervantes_denegar', 'funcion', 'estado = ''pendiente''',
   'D4: el No de Virgilio sólo deniega lo pendiente (lo confirmado ya entró al stock de acá)', 'Thomas', 'v25.40')
) v(objeto, clase, patron, regla, quien_pidio, version)
where not exists (select 1 from public."GV_Reglas_Centinela" c where c.objeto = v.objeto and c.patron = v.patron);

-- Rollback:
--   drop function if exists public.gv_envios_cervantes_pendientes();
--   drop function if exists public.gv_envio_cervantes_confirmar(bigint[], text, jsonb, text);
--   drop function if exists public.gv_envio_cervantes_denegar(bigint, text, text);
--   delete from public."GV_Reglas_Centinela" where version = 'v25.40' and objeto like 'gv_envio_cervantes_%';
