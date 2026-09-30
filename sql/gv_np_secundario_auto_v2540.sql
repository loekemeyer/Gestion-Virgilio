-- ============================================================================
-- v25.40 (Thomas, 30/09/2026) — CORREGIR CÓDIGOS (secundario → principal) SIN UNA PERSONA
-- ⚠ Los marcadores internos dicen `v25.39-np-sec-auto` / `v25.39-np-cambio`: son la llave de
--   idempotencia con la que se aplicó (otra sesión se llevó la v25.39). No cambiarlos.
--
-- Pedido de Thomas: "Como ahora los pedidos nuevos se manejan primero solo desde Gestión Virgilio y
-- recién a lo último llegan a ISIS, ya no hay que hacer la corrección de manera manual.
-- Que la haga directamente el programa."
--
-- Antes: el panel 🔀 «Corregir códigos» avisaba que una NP pedía un SECUNDARIO sin stock
-- (333) y una persona cambiaba la NP en ISIS al PRINCIPAL (948E) y tocaba «✓ Ya lo cambié».
-- Hoy la NP web es de Gestión (`PPP_Web_Base`) y el Excel de ISIS se arma recién al
-- facturar, desde lo que se armó. Así que el cambio se hace en la NP misma y viaja solo a
-- picking, armado, remito y factura.
--
-- QUÉ SE CAMBIA, y es el mismo criterio del panel (no se inventa otro):
--   · NP web con una línea en código SECUNDARIO (`Equivalencias_Familia`);
--   · el stock del secundario, repartido en la cola de todas las NP que lo piden, NO le
--     llega (`vista_correcciones_pedido_rich.sec_cubre = false`) — el rojo del panel.
-- QUÉ NO SE TOCA:
--   · una tanda EMPEZADA (evento de un operario real): ahí sigue el panel manual;
--   · una NP ya armada o facturada;
--   · un par de empresa dudosa (838/839 sin empresa) o de otra empresa que la línea;
--   · si las cajas no dan ENTERAS en el principal. El UxB cambia en varios pares
--     (332 va de a 24 y 945E de a 12): se convierte por UNIDADES, y si 1 caja de 631 (12)
--     serían 0,5 de 631E (24), no se adivina: queda para el panel.
--   · La L se conserva (333L → 948EL): la L dice de qué góndola sale, no se saca nunca.
--
-- POR QUÉ UNA TABLA Y NO UN UPDATE SUELTO: `PPP_Web_Base` la reescribe cada 5 minutos la
-- Edge Function `gv-ppp-web-tandas-diarias` desde el pedido de la página (que sigue diciendo
-- 333), y `gv_ppp_web_base_podar` saca lo que el pedido ya no trae. Un UPDATE suelto se
-- deshacía en la corrida siguiente. `GV_NP_Cambio_Codigo` es el registro del cambio y la
-- Edge Function lo aplica al armar la foto (v44): el cambio queda.
--   Rollback de UN cambio: borrar su fila → la corrida siguiente vuelve a poner el secundario.
--
-- Interruptor: `PPP_Web_Config.np_sec_auto_activo` (sin fila o 0 = sólo simula).
-- Chequeo:     select * from public.gv_web_np_sec_auto(true);   -- qué cambiaría, sin tocar
--              select * from public."GV_NP_Cambio_Codigo" order by id desc;
-- ============================================================================

create table if not exists public."GV_NP_Cambio_Codigo" (
  id             bigserial primary key,
  empresa        text        not null,
  order_id       bigint      not null,
  np_idx         int         not null,
  np_label       text,
  tanda          text,
  cod_origen     text        not null,   -- como estaba en PPP_Web_Base (upper, con L si la tenía)
  cod_destino    text        not null,
  factor         numeric     not null default 1,   -- cajas_destino = cajas_origen × factor (uxb_sec / uxb_ppal)
  cajas_origen   numeric,
  cajas_destino  numeric,
  stock_sec      numeric,
  stock_ppal     numeric,
  motivo         text,
  creado_por     text        not null default 'sistema',
  creado_at      timestamptz not null default now(),
  unique (empresa, order_id, np_idx, cod_origen)
);
alter table public."GV_NP_Cambio_Codigo" enable row level security;
revoke insert, update, delete, truncate on public."GV_NP_Cambio_Codigo" from anon, authenticated;
-- lectura para el panel (datos de operación: NP, códigos y cajas; nada del cliente)
drop policy if exists gv_np_cambio_codigo_leer on public."GV_NP_Cambio_Codigo";
create policy gv_np_cambio_codigo_leer on public."GV_NP_Cambio_Codigo" for select to anon, authenticated using (true);

create or replace function public.gv_web_np_sec_auto(p_simular boolean default true, p_por text default 'sistema')
returns table(empresa text, order_id bigint, np_idx int, np_label text, tanda text,
              cod_origen text, cod_destino text, cajas_origen numeric, cajas_destino numeric,
              stock_sec numeric, stock_ppal numeric, accion text)
language plpgsql
security definer
set search_path to 'public'
as $fn$
#variable_conflict use_column
-- v25.39-np-sec-auto: cambia en la NP web el SECUNDARIO sin stock por el PRINCIPAL.
-- ⚠ Los CTE llevan prefijo _ns_ (pozo v19.56: un CTE con nombre de variable plpgsql explota al ejecutar).
declare
  _ns_r      record;
  _ns_activo numeric;
  _ns_sim    boolean := coalesce(p_simular, true);
  _ns_cd     numeric;
begin
  if not public.gv_es_supervisor_o_servicio() then
    raise exception 'Sólo supervisores o el sistema pueden corregir códigos de NP.';
  end if;
  select c.valor into _ns_activo from public."PPP_Web_Config" c where c.clave = 'np_sec_auto_activo';
  if coalesce(_ns_activo, 0) = 0 then _ns_sim := true; end if;

  for _ns_r in
    with _ns_b as (
      select b.empresa, b.order_id, b.np_idx, b.np_label, b.articulo, b.cajas,
             upper(btrim(b.articulo)) as art_up,
             upper(btrim(b.articulo)) ~ '[0-9E]L$' as con_l,
             regexp_replace(regexp_replace(upper(btrim(b.articulo)), '([0-9E])L$', '\1'), '^0+(?=.)', '') as art_norm
        from public."PPP_Web_Base" b
    ), _ns_c as (
      select _ns_b.*, ef.cod_principal, g.tanda as g_tanda,
             case when _ns_b.con_l or _ns_b.empresa = 'lk' then 'LK' else 'CH' end as emp_art,
             (select max(u.uxb) from public.vista_uxb_articulo u where upper(btrim(u.cod)) = _ns_b.art_norm) as uxb_sec,
             (select max(u.uxb) from public.vista_uxb_articulo u where upper(btrim(u.cod)) = upper(btrim(ef.cod_principal))) as uxb_ppal,
             v.stk_sec, v.stk_ppal
        from _ns_b
        join public."Equivalencias_Familia" ef on ef.cod_secundario = _ns_b.art_norm
        join public."PPP_Web_Programacion" g
          on g.empresa = _ns_b.empresa and g.order_id = _ns_b.order_id and g.np_idx = _ns_b.np_idx
        join public.vista_correcciones_pedido_rich v
          on btrim(v.np) = btrim(_ns_b.np_label) and upper(btrim(v.sec)) = _ns_b.art_up
       where v.sec_cubre = false
         and coalesce(btrim(g.tanda), '') <> ''
    )
    select c.empresa, c.order_id, c.np_idx, c.np_label, c.g_tanda, c.articulo, c.art_up, c.cajas,
           upper(btrim(c.cod_principal)) || case when c.con_l then 'L' else '' end as destino,
           c.uxb_sec, c.uxb_ppal, c.stk_sec, c.stk_ppal,
           case
             when upper(coalesce((select ef2.empresa from public."Equivalencias_Familia" ef2
                                   where ef2.cod_secundario = c.art_norm limit 1), '')) <> c.emp_art
               then 'no: la familia es de otra empresa o no tiene empresa'
             when exists (select 1 from public."Registros_Produccion_Virgilio" r
                           where upper(btrim(split_part(r.texto, '|', 1))) = upper(btrim(c.g_tanda))
                             and coalesce(btrim(r.legajo), '') not in ('0', '1'))
               then 'no: la tanda ya empezó (sigue el panel manual)'
             when exists (select 1 from public."Entregas_Virgilio" e where btrim(e.np) = btrim(c.np_label))
               then 'no: la NP ya tiene armado'
             when exists (select 1 from public."Facturacion_NP" f where btrim(f.np) = btrim(c.np_label))
               then 'no: la NP ya se facturó'
             when coalesce(c.uxb_sec, 0) <= 0 or coalesce(c.uxb_ppal, 0) <= 0
               then 'no: falta el UxB de uno de los dos códigos'
             when (c.cajas * c.uxb_sec / c.uxb_ppal) <> trunc(c.cajas * c.uxb_sec / c.uxb_ppal)
               then 'no: en el principal no da cajas enteras'
             else 'cambiar'
           end as veredicto
      from _ns_c c
     order by c.np_label, c.art_up
  loop
    empresa := _ns_r.empresa; order_id := _ns_r.order_id; np_idx := _ns_r.np_idx;
    np_label := _ns_r.np_label; tanda := _ns_r.g_tanda;
    cod_origen := _ns_r.art_up; cod_destino := _ns_r.destino; cajas_origen := _ns_r.cajas;
    _ns_cd := case when coalesce(_ns_r.uxb_ppal, 0) > 0
                   then round(_ns_r.cajas * _ns_r.uxb_sec / _ns_r.uxb_ppal, 4) end;
    cajas_destino := _ns_cd;
    stock_sec := _ns_r.stk_sec; stock_ppal := _ns_r.stk_ppal;

    if _ns_r.veredicto <> 'cambiar' then
      accion := _ns_r.veredicto;
    elsif _ns_sim then
      accion := 'cambiaría';
    else
      insert into public."GV_NP_Cambio_Codigo" as x
        (empresa, order_id, np_idx, np_label, tanda, cod_origen, cod_destino, factor,
         cajas_origen, cajas_destino, stock_sec, stock_ppal, motivo, creado_por)
      values (_ns_r.empresa, _ns_r.order_id, _ns_r.np_idx, _ns_r.np_label, _ns_r.g_tanda,
              _ns_r.art_up, _ns_r.destino, round(_ns_r.uxb_sec / _ns_r.uxb_ppal, 6),
              _ns_r.cajas, _ns_cd, _ns_r.stk_sec, _ns_r.stk_ppal,
              'el stock del secundario no le llega a esta NP', coalesce(p_por, 'sistema'))
      on conflict on constraint "GV_NP_Cambio_Codigo_empresa_order_id_np_idx_cod_origen_key" do update
        set cod_destino = excluded.cod_destino, factor = excluded.factor,
            cajas_origen = excluded.cajas_origen, cajas_destino = excluded.cajas_destino,
            tanda = excluded.tanda, stock_sec = excluded.stock_sec, stock_ppal = excluded.stock_ppal;

      -- la foto de picking: el principal SUMA (la NP puede traer ya el principal) y el secundario sale
      insert into public."PPP_Web_Base" as w (empresa, order_id, np_idx, np_label, articulo, cajas)
      values (_ns_r.empresa, _ns_r.order_id, _ns_r.np_idx, _ns_r.np_label, _ns_r.destino, _ns_cd)
      on conflict (empresa, order_id, np_idx, articulo) do update set cajas = w.cajas + excluded.cajas;
      delete from public."PPP_Web_Base" w
       where w.empresa = _ns_r.empresa and w.order_id = _ns_r.order_id and w.np_idx = _ns_r.np_idx
         and w.articulo = _ns_r.articulo;
      accion := 'cambiado';
    end if;
    return next;
  end loop;
end $fn$;

revoke all on function public.gv_web_np_sec_auto(boolean, text) from public, anon;
grant execute on function public.gv_web_np_sec_auto(boolean, text) to authenticated, service_role;

-- ── la red: ningún escritor "crudo" vuelve a meter el secundario ─────────────────────
-- Además de la Edge Function, reescriben la foto `pppGuardarWeb` (front) y
-- `gv_ppp_web_tanda_programar` (A Programar) con el código del pedido de la página. Si el
-- secundario volviera en una tanda ya EMPEZADA, el podado no lo saca (a propósito) y la NP
-- quedaría con los dos códigos: doble picking. Por eso, en la base:
--   (1) un trigger que descarta la fila del secundario si esa NP ya lo cambió;
--   (2) el podado reconoce que el principal ES la línea del secundario en esa NP.
create or replace function public.gv_ppp_web_base_np_cambio()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $tg$
-- v25.39-np-cambio: el secundario ya se cambió por el principal en esta NP → no vuelve.
begin
  if exists (select 1 from public."GV_NP_Cambio_Codigo" k
              where k.empresa = new.empresa and k.order_id = new.order_id and k.np_idx = new.np_idx
                and k.cod_origen in (upper(btrim(new.articulo)),
                                     regexp_replace(upper(btrim(new.articulo)), '([0-9E])L$', '\1'))
                and upper(btrim(k.cod_destino)) <> upper(btrim(new.articulo))) then
    return null;
  end if;
  return new;
end $tg$;

drop trigger if exists trg_gv_ppp_web_base_np_cambio on public."PPP_Web_Base";
create trigger trg_gv_ppp_web_base_np_cambio
  before insert or update on public."PPP_Web_Base"
  for each row execute function public.gv_ppp_web_base_np_cambio();

-- (2) el podado, sobre la definición VIVA (idempotente; frena si el texto no matchea)
do $p$
declare d text; n text;
begin
  d := pg_get_functiondef('public.gv_ppp_web_base_podar(text,jsonb,text)'::regprocedure);
  if d ~ 'v25\.39-np-cambio' then return; end if;
  n := replace(d,
    $o$and l.articulo = upper(btrim(b.articulo)));$o$,
    $r$and (l.articulo = upper(btrim(b.articulo))
                                                    -- v25.39-np-cambio: en esa NP el secundario ya es el principal
                                                    or exists (select 1 from public."GV_NP_Cambio_Codigo" k
                                                                where k.empresa = b.empresa and k.order_id = l.order_id
                                                                  and k.np_idx = l.np_idx
                                                                  and k.cod_origen in (l.articulo, regexp_replace(l.articulo, '([0-9E])L$', '\1'))
                                                                  and upper(btrim(k.cod_destino)) = upper(btrim(b.articulo)))));$r$);
  if n = d then raise exception 'gv_ppp_web_base_podar: el texto no matcheó, no se tocó nada'; end if;
  execute n;
end $p$;

-- interruptor (se prende con el "sí")
-- insert into public."PPP_Web_Config" (clave, valor, descripcion)
-- values ('np_sec_auto_activo', 1, 'v25.39: cambia solo en la NP web el secundario sin stock por el principal')
-- on conflict (clave) do update set valor = excluded.valor;

-- cron: 2 minutos después de cada corrida de la Edge Function (cron 73 = */5 9-23 UTC)
-- select cron.schedule('gv-np-sec-auto', '2-59/5 9-23 * * *',
--   $$select count(*) from public.gv_web_np_sec_auto(false)$$);
-- centinelas (se cargan con el "sí")
-- insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
--  ('gv_web_np_sec_auto','funcion','sec_cubre = false','cambia en la NP web el secundario sin stock por el principal; sólo tanda sin empezar','(a confirmar)','v25.39'),
--  ('gv_ppp_web_base_np_cambio','funcion','return null','el secundario ya cambiado no vuelve a la foto de picking','(a confirmar)','v25.39'),
--  ('gv_ppp_web_base_podar','funcion','GV_NP_Cambio_Codigo','el podado no saca el principal que reemplazó al secundario','(a confirmar)','v25.39');
-- Rollback: select cron.unschedule('gv-np-sec-auto');
--           update public."PPP_Web_Config" set valor = 0 where clave = 'np_sec_auto_activo';
