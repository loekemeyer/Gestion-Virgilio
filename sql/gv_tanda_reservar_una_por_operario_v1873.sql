/* v18.73 — UNA TANDA ABIERTA POR OPERARIO Y FASE, garantizado en el backend.

   Pedido de Luis (16/09): "que una vez que alguien agarra una tanda para armado o pickeado
   no se pueda agarrar otra vez al mismo tiempo hasta que no quede anulada o pase a la
   siguiente etapa" — y después, explícito: "ningún operario puede arrancar a pickear una
   tanda si ya tiene una abierta (y lo mismo con armado)".

   QUÉ HABÍA (y por qué no alcanzaba)
   ----------------------------------
   La v18.65 cerró "dos operarios en LA MISMA tanda": el lock es por (tanda, fase) y gana el
   primero. Eso está bien y no se toca.

   Lo que NO estaba cerrado es el caso inverso: UN operario con DOS tandas abiertas. Eso
   vivía sólo en el front (`send()`, guardas v5.26 / idea 5138) y era un `confirm()`:
   "Aceptar = arrancar igual". O sea que la tanda vieja quedaba sin cerrar A PROPÓSITO, con
   un toque. Y encima el guard se apoya en `getLegajoState`, que es localStorage: si el
   celular perdió el estado (app actualizada, otro equipo, cache limpiada) no avisaba nada.

   No es teórico. Medido el 16/09 09:05 sobre `GV_Tandas_Lock`: había un legajo con DOS
   filas 'tomada' en la misma fase. Un minuto después ya era una sola — o sea que pasa, se
   resuelve solo a veces, y nadie se entera. Es el mismo mecanismo que dejó E11B colgada
   (leg 237: AP 11:15, arrancó E01C 13:44) y el que dejó abiertos el picking de E25A y el
   armado de E23A del 15/09.

   POR QUÉ EN EL BACKEND
   ---------------------
   Es una regla de negocio sobre datos persistidos, así que va acá (protocolo del CLAUDE.md).
   El front la duplica como UX — avisa antes de gastar el viaje — pero el que manda es éste.

   LA VENTANA DE 3 DÍAS NO ES DECORATIVA: es lo que evita la trampa
   ---------------------------------------------------------------
   Un bloqueo duro sin escape es peor que el problema. Si a un operario le quedó un picking
   abierto de hace un mes, bloquearlo lo deja sin poder trabajar y sin forma de destrabarse:
   `gv_anular_picking_virgilio` sólo anula dentro de 3 días, así que ni anulando sale.
   Entonces el bloqueo se aplica SÓLO mientras la tanda vieja se pueda anular de verdad —
   los mismos 3 días. Más viejo que eso no es "trabajo en curso", es basura, y no puede
   frenar a nadie.

   Resultado: si te bloquea, SIEMPRE tenés la salida a un toque ("Anular picking" / "No la
   armo yo"), que es lo que el mensaje del front dice textualmente.

   ROLLBACK
   --------
   Volver a la v18.65: borrar el bloque marcado «v18.73» de abajo y re-aplicar. La versión
   vieja está en `sql/gv_tandas_lock_v1865.sql`.
*/

create or replace function public.gv_tanda_reservar(
  p_tanda text, p_fase text, p_legajo text, p_nombre text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  t text := upper(btrim(coalesce(p_tanda,'')));
  f text := lower(btrim(coalesce(p_fase,'')));
  l text := btrim(coalesce(p_legajo,''));
  r public."GV_Tandas_Lock";
  o public."GV_Tandas_Lock";
begin
  if t = '' or f not in ('picking','armado') then
    return jsonb_build_object('ok', false, 'motivo', 'datos_invalidos');
  end if;
  if public.es_legajo_test(l) then
    return jsonb_build_object('ok', true, 'motivo', 'prueba');
  end if;

  /* ---- v18.73: ¿este operario ya tiene OTRA tanda abierta en esta fase? ----
     Va ANTES del insert: si contestamos que no, no queremos haber creado el lock nuevo.
     `tanda <> t` deja pasar el re-toque sobre la propia (lo resuelve el camino 'propia').
     El filtro de 3 días es el que garantiza que lo que bloquea se puede destrabar. */
  if l <> '' then
    select * into o
      from public."GV_Tandas_Lock"
     where fase = f
       and estado = 'tomada'
       and legajo = l
       and tanda <> t
       and ts >= now() - interval '3 days'
     order by ts
     limit 1;
    if found then
      return jsonb_build_object('ok', false, 'motivo', 'otra_tanda_abierta',
        'tanda_abierta', o.tanda, 'legajo', o.legajo, 'nombre', o.nombre,
        'estado', o.estado, 'desde', o.ts);
    end if;
  end if;
  /* ---- fin v18.73 ---- */

  insert into public."GV_Tandas_Lock" (tanda, fase, legajo, nombre, estado)
  values (t, f, nullif(l,''), nullif(btrim(coalesce(p_nombre,'')),''), 'tomada')
  on conflict (tanda, fase) do nothing;

  select * into r from public."GV_Tandas_Lock" where tanda = t and fase = f;

  if r.estado = 'completada' then
    return jsonb_build_object('ok', false, 'motivo', 'ya_completada',
      'legajo', r.legajo, 'nombre', r.nombre, 'estado', r.estado, 'desde', r.ts_estado);
  end if;
  if coalesce(r.legajo,'') = l or public.es_legajo_test(coalesce(r.legajo,'')) then
    return jsonb_build_object('ok', true, 'motivo', 'propia',
      'legajo', r.legajo, 'nombre', r.nombre, 'estado', r.estado, 'desde', r.ts);
  end if;
  return jsonb_build_object('ok', false, 'motivo', 'tomada',
    'legajo', r.legajo, 'nombre', r.nombre, 'estado', r.estado, 'desde', r.ts);
end $function$;
