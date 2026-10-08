-- v28.59 (Luis, 08/10/2026): «Corregir códigos de NPs» deja de ser manual — el botón sale del front.
-- "podemos hacer el automatizado y sacar el icono del front ya que manual no iria más"
--
-- El automático (gv_web_np_sec_auto, cron 119, v25.40) ya cambia el SECUNDARIO sin stock por el
-- PRINCIPAL en la NP web. Lo que dejaba "para el panel manual" (tanda empezada, cajas que no dan
-- enteras en el principal, familia de otra empresa, sin UxB) ahora NO va a ningún panel: el
-- secundario sale como FALTANTE. Una NP web se factura desde lo armado, así que no hay nada que
-- cambiar a mano en ISIS (el «✓ Ya lo cambié» del panel sólo servía para las NP de ISIS, que ya no entran).
--
-- Aplicado sobre pg_get_functiondef (idempotente, marcador v28.59-sec-resto):
--   * textos del veredicto: '(el secundario queda faltante)' en vez de '(sigue el panel manual)';
--   * columna GV_NP_Cambio_Codigo.cajas_resto + variable _ns_resto y el trigger gv_ppp_web_base_np_cambio
--     que respeta un resto > 0. Hoy SIEMPRE es 0 (sólo se convierte cuando da cajas enteras): queda
--     preparado para convertir la parte entera de un pedido impar (631 de a 12 → 631E de a 24) el día
--     que la Edge Function gv-ppp-web-tandas-diarias convierta (cajas − cajas_resto). Ver D en el chat.

alter table public."GV_NP_Cambio_Codigo" add column if not exists cajas_resto numeric;

create or replace function public.gv_ppp_web_base_np_cambio()
returns trigger language plpgsql security definer set search_path to 'public'
as $f$
-- v25.39-np-cambio: el secundario ya se cambió por el principal en esta NP → no vuelve.
-- v28.59-sec-resto: si quedó un RESTO que no daba caja entera del principal, la línea del secundario queda en ese resto.
declare v_resto numeric; v_n int;
begin
  select count(*), max(k.cajas_resto) into v_n, v_resto
    from public."GV_NP_Cambio_Codigo" k
   where k.empresa = new.empresa and k.order_id = new.order_id and k.np_idx = new.np_idx
     and k.cod_origen in (upper(btrim(new.articulo)),
                          regexp_replace(upper(btrim(new.articulo)), '([0-9E])L$', '\1'))
     and upper(btrim(k.cod_destino)) <> upper(btrim(new.articulo));
  if v_n > 0 then
    if coalesce(v_resto, 0) > 0 then new.cajas := v_resto; return new; end if;
    return null;
  end if;
  return new;
end $f$;
-- ⚠ NO escribir este trigger con "select true, max(...)": un agregado sin filas devuelve UNA fila y
--   el trigger descartaba TODA alta de PPP_Web_Base (pasó ~2 min el 08/10 al aplicarlo; se corrigió con count(*)).
