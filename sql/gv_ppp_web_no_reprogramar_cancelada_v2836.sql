-- v28.36 (07/10/2026) — un pedido CANCELADO no vuelve a tomar tanda POR NINGÚN CAMINO.
-- La v28.35 frenó sólo A Programar (gv_ppp_web_tanda_agregar). Esto lo frena en la tabla madre,
-- así cubre también el armador, reusar, mover y cualquier escritura futura.
-- Sólo frena cuando la NP ENTRA a una tanda (no tenía): renombrar una tanda existente no se toca.
-- Probado en transacción abortada: cancelada que entra -> CANCELADO · renombre -> pasa · sana -> pasa.
-- Centinela id 358. Aplicado el 07/10.
create or replace function public.gv_ppp_web_no_reprogramar_cancelada()
 returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $f$
declare v_c record;
begin
  -- v28.36-cancelada
  if coalesce(nullif(btrim(new.tanda),''),'') = '' then return new; end if;
  if tg_op = 'UPDATE' and coalesce(nullif(btrim(old.tanda),''),'') <> '' then return new; end if;
  select * into v_c from public."GV_PPP_Web_NP_Cancelada" c
   where c.empresa = new.empresa and c.order_id = new.order_id and c.np_idx = new.np_idx;
  if found then
    raise exception 'CANCELADO: % se canceló el % (%). Un pedido cancelado no se vuelve a programar.',
      v_c.np_label, to_char(v_c.creado_at at time zone 'America/Argentina/Buenos_Aires','DD/MM HH24:MI'),
      coalesce(v_c.motivo,'sin motivo') using errcode = 'P0001';
  end if;
  return new;
end $f$;
create or replace trigger gv_ppp_web_no_reprogramar_cancelada
  before insert or update of tanda on public."PPP_Web_Programacion"
  for each row execute function public.gv_ppp_web_no_reprogramar_cancelada();
-- Rollback: alter table public."PPP_Web_Programacion" disable trigger gv_ppp_web_no_reprogramar_cancelada;
