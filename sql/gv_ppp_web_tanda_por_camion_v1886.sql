/* ============================================================================
   La tanda de un cliente se parte por CAMIÓN.  (v18.86, pedido de Luis 2026-09-16)

   ── El caso ─────────────────────────────────────────────────────────────────
   D69F del 21/09 se armó sola el 16/09 a las 08:05 con esto adentro:

     LK 0028  Laza Ariel        Ituzaingó   Zona 5 - GBA Oeste
     LK 0032  Gonzalez Pellegr. Ciudadela   Zona 5 - GBA Oeste
     LK 0109  Jazquel SRL       Ciudadela   Zona 5 - GBA Oeste
     LK 0110..0117 Jazquel SRL  Balvanera / Once   **Zona 2 - CABA Centro**

   Jazquel (cód 3814) hizo NUEVE pedidos, uno por sucursal (order_id 1455-1463).
   Las ocho de CABA Centro se fueron a una tanda de GBA Oeste porque la regla que
   junta los pedidos de un cliente miraba SÓLO cliente + día.

   ── La definición de Luis ───────────────────────────────────────────────────
   *"Claro que se parte en zonas distintas (si un mismo cliente pide para una
   sucursal que tiene en Tucumán y otra en Río Negro, ¿lo pondrías en el mismo
   camión?). Se factura diferente también, es uno de los criterios justamente
   para parsear qué factura correspondía con qué pedido (la zona)."*

   ── El corte es el CAMIÓN, no el número de zona ─────────────────────────────
   La pregunta de Luis es literalmente *"¿lo pondrías en el mismo camión?"*, así
   que el criterio es la etiqueta de camión —`gv_ppp_web_camion`: Capital ·
   GBA Sur · GBA Oeste · GBA Norte—, la misma con la que `gv_ppp_web_camion_del_dia`
   decide a qué camión entra una tanda nueva. Cortar por número de zona sería más
   fino que el reparto real y fragmentaría Capital: hoy una tanda de CABA mezcla
   Zona 1+2 o 2+3 a propósito, por cercanía de sectores, y va en el mismo camión.

   Medido sobre TODO `PPP_Web_Programacion` (no sólo la semana): con el corte por
   camión hay **una sola** tanda mezclada en la historia, D69F — el caso que Luis
   reportó. Con el corte por número de zona salían tres, y las otras dos (E03G
   Zona 1+2, E01D Zona 2+3) están bien como están.

   ── Cómo convive con la regla de Thomas ─────────────────────────────────────
   Thomas (2026-09-11): *"nunca si hay +1 pedido de un cliente puede ir separado
   en la PPP … salvo los súper"*. Las dos reglas conviven sin chocar:

       el DÍA sigue siendo uno solo por cliente  ·  la TANDA se parte por camión

   O sea: Jazquel entrega todo el mismo día, pero lo de Balvanera/Once va en el
   camión de Capital y lo de Ciudadela en el de GBA Oeste. Que es como sale el
   reparto de verdad, y como se factura.

   ⚠ Cuando las dos reglas SÍ chocan —hay que juntar un cliente en un día y en ese
   día no existe ningún camión de su etiqueta— gana la de Luis: la NP **no se
   mueve**. Mezclar camiones rompe el reparto Y la facturación; quedar partido en
   dos días se ve y se arregla a mano (`gv_ppp_cliente_dos_dias`, y el pase lo
   devuelve en `r_motivo`). Antes se la mandaba igual a la tanda que hubiera.

   ── Los CUATRO lugares que asignaban tanda por cliente ──────────────────────
   1. `gv_ppp_web_tanda_abierta_cliente` — la base. Ahora recibe la zona.
   2. `gv_ppp_web_armar_pendientes`, pase (a1) — le pasa la zona del pedido.
   3. `gv_ppp_web_juntar_clientes` y el trigger `gv_web_cliente_un_solo_dia` —
      resuelven la tanda destino por la zona de CADA NP, no una para todas.
   4. `ppp_web_armar_tandas` — **por acá entró D69F**, no por (a1). Agrupaba
      `group by cliente` y tomaba `min(camion)`. Ver el bloque (5b).

   ⚠ Los tres primeros no alcanzaban. Se creyó que sí hasta que se probó de punta
   a punta: una corrida real del armador con tres NP de Jazquel (dos de CABA
   Centro, una de Ciudadela), dentro de una transacción abortada, las metió a las
   tres en la misma tanda. Arreglar (1)-(3) sin (4) habría dejado el bug vivo.
   **Un cambio de regla de armado no está probado hasta que se corre el armador.**

   ── Ciudadela NO queda exenta, a propósito ──────────────────────────────────
   El panel de errores del front exime a Ciudadela de "ruta mezclada" (está pegada
   a la fábrica y camino a Zona 1 por la autopista, regla del dueño). Acá NO: es
   Zona 5 → camión GBA Oeste y se parte como cualquier otra. Partir de más nunca
   rompe un reparto; juntar de más sí. Si el dueño quiere que Ciudadela pueda
   viajar con Capital, el lugar es `gv_ppp_web_camion` y vale para todos.

   ── Verificación (medida el 16/09) ──────────────────────────────────────────
   · Barrido de 30 días sobre todos los pares (empresa, cod, día, zona) con tanda:
     la respuesta de `gv_ppp_web_tanda_abierta_cliente` cambia en **2 filas de
     cientos**, y las dos son Jazquel/D69F (que al estar ya mezclada deja de
     recibir NP nuevas, que es lo correcto). Todo lo demás contesta igual.
   · Osa 2533 el 09/09 sigue dando NULL → la tanda de ISIS no es candidata, la
     regla v14.12 quedó intacta.
   · Corrida real del armador (transacción abortada): las dos NP de CABA Centro
     fueron a E12R (Capital) y la de Ciudadela a E20A (GBA Oeste), **el mismo
     día**. Antes del arreglo las tres caían en E12R.
   · `gv_ppp_web_juntar_clientes('lk')` corre sin error y no mueve nada.

   ⚠ El DROP + CREATE va en la misma transacción que los llamadores: un
   `create or replace` con un parámetro más deja DOS funciones (3 y 4 args) y la
   llamada de 3 sigue resolviendo a la vieja — el bug queda vivo y en silencio.

   ── Lo que este archivo NO hace ─────────────────────────────────────────────
   No toca las 8 NP de Jazquel que YA están en D69F. Es dato real de una tanda
   programada: se reporta y lo mueve un supervisor (protocolo de CLAUDE.md). El
   centinela `gv_ppp_tanda_camion_mezclado` la muestra hasta que eso pase.
   ============================================================================ */

begin;

-- ── 1) La base: la tanda abierta del cliente, ese día, DE ESE CAMIÓN ────────
drop function if exists public.gv_ppp_web_tanda_abierta_cliente(text, text, date);

create function public.gv_ppp_web_tanda_abierta_cliente(
  p_empresa text, p_cod text, p_fecha date, p_zona text
) returns text
language sql
stable
set search_path to 'public'
as $function$
  -- v14.12 — ¿el cliente ya tiene ese día una tanda WEB a la que sumarse?
  --
  -- REGLA DEL DUEÑO (07/09): "solo va en tanda nueva si mezcla lo que es pedido
  -- isis y pedido web". El corte es el ORIGEN, no "¿ya se tocó?". Por eso acá
  -- SOLO se miran las tandas de PPP_Web_Programacion: si el cliente sólo tiene
  -- tanda de ISIS, devuelve NULL y el armado abre tanda nueva (caso Osa 2533 del
  -- 09/09: E09A es de ISIS, así que LK 0024 fue a E09B).
  --
  -- v18.86 (Luis) — Y ADEMÁS DEL MISMO CAMIÓN. Un cliente con sucursales en
  -- zonas que van en camiones distintos se parte: no viajan juntas y no se
  -- facturan juntas. Una tanda es candidata sólo si TODAS sus NP son del camión
  -- pedido; si ya está mezclada, no se le suma nada más.
  --
  -- Se mantiene el guard de "sin empezar": sumarle algo a una tanda ya pickeada
  -- rompe el picking, sea del origen que sea.
  with cam as (
    select public.gv_ppp_web_camion(p_zona, null) as c
     where coalesce(p_zona, '') ~ '^\s*Zona\s*[0-9]+'
  ),
  cand as (
    select upper(btrim(w.tanda)) as tanda, public.gv_ppp_web_camion(w.zona, null) as c
      from public."PPP_Web_Programacion" w
     where w.empresa = p_empresa
       and btrim(coalesce(w.cod_cliente, '')) = btrim(coalesce(p_cod, ''))
       and w.fecha_entrega = p_fecha
       and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
       and coalesce(w.zona, '') ~ '^\s*Zona\s*[0-9]+'
  ),
  -- una tanda entra sólo si TODAS sus NP son del camión pedido. Sin zona
  -- reconocible (no hay fila en `cam`) se vuelve a la regla vieja: cualquiera.
  mismo_camion as (
    select c.tanda
      from cand c
      left join cam on true
     group by c.tanda, cam.c
    having cam.c is null
        or count(*) filter (where c.c is distinct from cam.c) = 0
  )
  select min(m.tanda) from mismo_camion m
   where not exists (
     -- "tocada" = tiene algún evento de operario. El código de tanda aparece en
     -- el `texto` en formatos mezclados (solo, `np|tanda`, `np|lios|tanda|…`),
     -- así que se miran los 3 tramos.
     select 1 from public."Registros_Produccion_Virgilio" r
      where r.opcion in ('EP','TP','AP','TAP')
        and (   upper(btrim(split_part(r.texto, '|', 1))) = m.tanda
             or upper(btrim(split_part(r.texto, '|', 2))) = m.tanda
             or upper(btrim(split_part(r.texto, '|', 3))) = m.tanda)
   );
$function$;

revoke all on function public.gv_ppp_web_tanda_abierta_cliente(text, text, date, text) from public;
grant execute on function public.gv_ppp_web_tanda_abierta_cliente(text, text, date, text)
  to anon, authenticated, service_role;

comment on function public.gv_ppp_web_tanda_abierta_cliente(text, text, date, text) is
  'Tanda web sin empezar del cliente ese día Y DE ESE CAMIÓN (v18.86). Un cliente con '
  'sucursales que van en camiones distintos se parte en tandas distintas: no viajan '
  'juntas y no se facturan juntas. NULL = abrir tanda nueva.';

-- ── 2) A qué tanda de ESE día va una NP que se está mudando ─────────────────
create or replace function public.gv_ppp_web_tanda_destino(
  p_empresa text, p_cod text, p_fecha date, p_zona text
) returns text
language sql
stable
set search_path to 'public'
as $function$
  -- v18.86 — la usan el candado de "un cliente, un día" (gv_ppp_web_juntar_clientes
  -- y el trigger gv_web_cliente_un_solo_dia) para saber a qué tanda del día destino
  -- entra CADA NP. Dos intentos, en este orden:
  --   1) la tanda del cliente ese día, de ese camión, SIN empezar;
  --   2) si todas las de ese camión ya se empezaron, la del cliente ese día igual:
  --      el día ya está decidido y la NP tiene que caer en alguna. (Es el mismo
  --      fallback que había antes de v18.86, ahora acotado al camión.)
  -- NULL = en ese día no hay ninguna tanda del cliente de ese camión. Quien llama
  -- NO la mueve: mezclar camiones es peor que dejarla partida en dos días.
  select coalesce(
    public.gv_ppp_web_tanda_abierta_cliente(p_empresa, p_cod, p_fecha, p_zona),
    (select min(t.tanda) from (
        select upper(btrim(w.tanda)) as tanda
          from public."PPP_Web_Programacion" w
          left join lateral (select public.gv_ppp_web_camion(p_zona, null) as c
                              where coalesce(p_zona, '') ~ '^\s*Zona\s*[0-9]+') cam on true
         where w.empresa = p_empresa
           and btrim(coalesce(w.cod_cliente, '')) = btrim(coalesce(p_cod, ''))
           and w.fecha_entrega = p_fecha
           and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
           and coalesce(w.zona, '') ~ '^\s*Zona\s*[0-9]+'
         group by upper(btrim(w.tanda)), cam.c
        having cam.c is null
            or count(*) filter (where public.gv_ppp_web_camion(w.zona, null)
                                   is distinct from cam.c) = 0
      ) t)
  );
$function$;

revoke all on function public.gv_ppp_web_tanda_destino(text, text, date, text) from public;
grant execute on function public.gv_ppp_web_tanda_destino(text, text, date, text)
  to anon, authenticated, service_role;

comment on function public.gv_ppp_web_tanda_destino(text, text, date, text) is
  'A qué tanda de ese día va una NP del cliente, respetando su camión (v18.86). '
  'NULL = no hay tanda de ese camión ese día → no mover la NP.';

-- ── 3) El candado "un cliente, un día": la tanda destino es por NP ──────────
create or replace function public.gv_ppp_web_juntar_clientes(p_empresa text default null::text)
 returns table(r_empresa text, r_cod text, r_razon_social text, r_a_dia date, r_np_movidas integer, r_motivo text)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  c        record;
  v_dias   date[];
  v_fijos  date[];
  v_target date;
  v_n      int;
  v_queda  int;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor o el servicio pueden juntar clientes.' using errcode='42501';
  end if;

  -- REGLA DEL DUENO (2026-09-11): "nunca si hay +1 pedido de un cliente puede ir separado en la
  -- PPP ... salvo los super". Esta pasada corre al final de cada armado automatico y junta las NP
  -- WEB de un cliente que quedaron en dias distintos. El dia que gana:
  --   1) si UNA de sus tandas ya la empezo un operario (gv_ppp_tanda_tocada) -> ese dia, porque
  --      esa no se puede mover sin romper el picking;
  --   2) si ninguna -> el dia MAS TEMPRANO (dueno: "buscar para atras, no para adelante": la regla
  --      adelanta, nunca demora);
  --   3) si DOS dias distintos ya estan empezados -> no se toca y se informa (queda para la alerta).
  -- Las NP se suman a la tanda web abierta del cliente ese dia; si no hay, a la de la NP que ya
  -- esta ahi. Super / Retira / Expo y el padron de cadenas quedan afuera. Solo mira lo web: un
  -- cliente partido entre una NP de ISIS y una web lo muestra gv_ppp_cliente_dos_dias.
  --
  -- v18.86 (Luis) -- LA TANDA DESTINO SE RESUELVE POR NP, NO UNA PARA TODAS. Un cliente con
  -- sucursales en camiones distintos (Capital y GBA Oeste, por ejemplo) entrega el mismo dia
  -- pero en camiones distintos. Si en el dia destino no hay tanda de su camion, esa NP NO se
  -- mueve: mezclar camiones rompe el reparto y la facturacion. Se informa en r_motivo.
  for c in
    select w.empresa, btrim(w.cod_cliente) as cod, max(w.razon_social) as rs
      from public."PPP_Web_Programacion" w
     where (p_empresa is null or w.empresa = lower(p_empresa))
       and coalesce(nullif(btrim(w.tanda),''),'') <> ''
       and w.fecha_entrega is not null and w.fecha_entrega >= current_date
       and coalesce(w.zona,'') ~ '^\s*Zona\s*[0-9]+' and not exists (select 1 from public."GV_PPP_Web_Diferido" d where d.empresa = w.empresa and d.order_id = w.order_id and d.np_idx = w.np_idx)
       and nullif(btrim(coalesce(w.cod_cliente,'')),'') is not null
       and not exists (select 1 from public.cobranzas_cliente_cadena cc
                        where btrim(cc.cod_cliente) = btrim(w.cod_cliente)
                          and lower(cc.empresa) in (lower(w.empresa),
                                case lower(w.empresa) when 'chef' then 'ch' when 'ch' then 'chef' else lower(w.empresa) end))
     group by w.empresa, btrim(w.cod_cliente)
    having count(distinct w.fecha_entrega) > 1
  loop
    select array_agg(distinct w.fecha_entrega order by w.fecha_entrega),
           array_agg(distinct w.fecha_entrega order by w.fecha_entrega) filter (where public.gv_ppp_tanda_tocada(w.tanda))
      into v_dias, v_fijos
      from public."PPP_Web_Programacion" w
     where w.empresa = c.empresa and btrim(coalesce(w.cod_cliente,'')) = c.cod
       and coalesce(nullif(btrim(w.tanda),''),'') <> ''
       and w.fecha_entrega >= current_date
       and coalesce(w.zona,'') ~ '^\s*Zona\s*[0-9]+' and not exists (select 1 from public."GV_PPP_Web_Diferido" d where d.empresa = w.empresa and d.order_id = w.order_id and d.np_idx = w.np_idx);

    if coalesce(cardinality(v_fijos),0) > 1 then
      r_empresa := c.empresa; r_cod := c.cod; r_razon_social := c.rs; r_a_dia := null; r_np_movidas := 0;
      r_motivo := 'dos dias ya empezados (' || array_to_string(v_fijos, ', ') || '): no se puede juntar';
      return next;
      continue;
    end if;

    v_target := coalesce(v_fijos[1], v_dias[1]);

    -- v18.86: las que se quedan porque en el dia destino no hay camion de su etiqueta
    select count(*) into v_queda
      from public."PPP_Web_Programacion" w
     where w.empresa = c.empresa and btrim(coalesce(w.cod_cliente,'')) = c.cod
       and coalesce(nullif(btrim(w.tanda),''),'') <> ''
       and w.fecha_entrega >= current_date
       and w.fecha_entrega <> v_target
       and coalesce(w.zona,'') ~ '^\s*Zona\s*[0-9]+' and not exists (select 1 from public."GV_PPP_Web_Diferido" d where d.empresa = w.empresa and d.order_id = w.order_id and d.np_idx = w.np_idx)
       and public.gv_ppp_web_tanda_destino(c.empresa, c.cod, v_target, w.zona) is null;

    update public."PPP_Web_Programacion" w
       set fecha_entrega = v_target,
           tanda = public.gv_ppp_web_tanda_destino(c.empresa, c.cod, v_target, w.zona),
           actualizado_at = now()
     where w.empresa = c.empresa and btrim(coalesce(w.cod_cliente,'')) = c.cod
       and coalesce(nullif(btrim(w.tanda),''),'') <> ''
       and w.fecha_entrega >= current_date
       and w.fecha_entrega <> v_target
       and coalesce(w.zona,'') ~ '^\s*Zona\s*[0-9]+' and not exists (select 1 from public."GV_PPP_Web_Diferido" d where d.empresa = w.empresa and d.order_id = w.order_id and d.np_idx = w.np_idx)
       and public.gv_ppp_web_tanda_destino(c.empresa, c.cod, v_target, w.zona) is not null;
    get diagnostics v_n = row_count;

    r_empresa := c.empresa; r_cod := c.cod; r_razon_social := c.rs; r_a_dia := v_target; r_np_movidas := v_n;
    r_motivo := case when v_fijos[1] is not null then 'al dia ya empezado' else 'al dia mas temprano' end
             || case when v_queda > 0
                     then ' (' || v_queda || ' NP se quedan: no hay camion de su zona ese dia)'
                     else '' end;
    return next;
  end loop;
  return;
end;
$function$;

-- ── 4) El mismo candado, en caliente: el trigger ────────────────────────────
create or replace function public.gv_web_cliente_un_solo_dia()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  r        record;
  v_tanda  text;
  v_movidas int := 0;
  v_quedan  int := 0;
begin
  -- una sola vuelta: el propio UPDATE de abajo vuelve a disparar el trigger
  if pg_trigger_depth() > 1 then return null; end if;
  if NEW.fecha_entrega is null or coalesce(nullif(btrim(NEW.tanda),''),'') = '' then return null; end if;
  if NEW.fecha_entrega < current_date then return null; end if;

  -- REGLA DEL DUENO (2026-09-11): "nunca, si hay +1 pedido de un cliente, puede ir separado en
  -- la PPP" ... "salvo los super". Un super entrega a sucursales distintas en dias distintos a
  -- proposito, asi que queda afuera: por zona (Super / Retira / Expo) o por estar en el padron
  -- de cadenas (cobranzas_cliente_cadena, el mismo que usa Cuarentena).
  if coalesce(NEW.zona,'') ~* 'super|retira|expo' then return null; end if;
  if exists (select 1 from public.cobranzas_cliente_cadena cc
              where btrim(cc.cod_cliente) = btrim(coalesce(NEW.cod_cliente,''))
                and lower(cc.empresa) in (lower(NEW.empresa),
                      case lower(NEW.empresa) when 'chef' then 'ch' when 'ch' then 'chef' else lower(NEW.empresa) end))
  then return null; end if;

  for r in
    select w.order_id, w.np_idx, w.np, w.tanda, w.fecha_entrega, w.zona
      from public."PPP_Web_Programacion" w
     where w.empresa = NEW.empresa
       and btrim(coalesce(w.cod_cliente,'')) = btrim(coalesce(NEW.cod_cliente,''))
       and (w.order_id, w.np_idx) is distinct from (NEW.order_id, NEW.np_idx)
       and coalesce(nullif(btrim(w.tanda),''),'') <> ''
       and w.fecha_entrega is not null
       and w.fecha_entrega >= current_date
       and w.fecha_entrega <> NEW.fecha_entrega
       and coalesce(w.zona,'') !~* 'super|retira|expo'
  loop
    -- si la otra ya se pickeo, moverla romperia el picking: no se separa NI se mueve, se avisa.
    if public.gv_ppp_tanda_tocada(r.tanda) then
      raise exception 'No se puede: % ya tiene otro pedido en la tanda % del % y esa tanda ya se empezo a trabajar. Los pedidos de un cliente no pueden salir en dias distintos.',
        coalesce(NEW.razon_social, NEW.cod_cliente), r.tanda, to_char(r.fecha_entrega, 'DD/MM')
        using errcode = 'raise_exception';
    end if;
    -- v18.86 (Luis): la tanda destino es la del CAMION de ESA NP, no la de NEW. Si en el dia
    -- de NEW no hay ninguna tanda del cliente de ese camion, la NP se queda donde esta:
    -- mezclar Capital con GBA Oeste rompe el reparto y la facturacion, y eso pesa mas que
    -- tenerlo partido en dos dias (que ademas se ve en gv_ppp_cliente_dos_dias).
    v_tanda := public.gv_ppp_web_tanda_destino(NEW.empresa, NEW.cod_cliente, NEW.fecha_entrega, r.zona);
    if v_tanda is null then v_quedan := v_quedan + 1; continue; end if;
    update public."PPP_Web_Programacion"
       set fecha_entrega = NEW.fecha_entrega, tanda = v_tanda, actualizado_at = now()
     where empresa = NEW.empresa and order_id = r.order_id and np_idx = r.np_idx;
    v_movidas := v_movidas + 1;
  end loop;

  if v_movidas > 0 then
    raise notice 'gv_web_cliente_un_solo_dia: % NP de % se movieron al % para no separarlas',
      v_movidas, coalesce(NEW.razon_social, NEW.cod_cliente), NEW.fecha_entrega;
  end if;
  if v_quedan > 0 then
    raise notice 'gv_web_cliente_un_solo_dia: % NP de % se quedan en su dia: el % no hay camion de su zona',
      v_quedan, coalesce(NEW.razon_social, NEW.cod_cliente), NEW.fecha_entrega;
  end if;
  return null;
end;
$function$;

-- ── 5) El pase (a1) del armador le pasa la zona del pedido ──────────────────
-- Es POR DONDE ENTRO D69F: (a1) resuelve "la tanda que el cliente ya tiene ese dia"
-- y hasta hoy no miraba a donde va el camion.
--
-- Se hace con reemplazo de texto sobre pg_get_functiondef y no copiando la funcion
-- entera (son ~200 lineas de plpgsql con 6 pases): copiarla para cambiar un
-- argumento es el modo de introducir un error de transcripcion. El guard de abajo
-- exige que el reemplazo haya ocurrido EXACTAMENTE una vez; si no, aborta la
-- transaccion entera y no queda nada a medias.
do $do$
declare
  v_def text;
  v_old text := 'public.gv_ppp_web_tanda_abierta_cliente(p_empresa, x->>''cod'', dc.d)';
  v_new text := 'public.gv_ppp_web_tanda_abierta_cliente(p_empresa, x->>''cod'', dc.d, x->>''zona'')';
  v_n   int;
begin
  v_def := pg_get_functiondef('public.gv_ppp_web_armar_pendientes(text,date,jsonb,jsonb)'::regprocedure);
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_n <> 1 then
    raise exception 'gv_ppp_web_armar_pendientes: esperaba 1 llamada de 3 argumentos en el pase (a1) y encontre %. No se toco nada.', v_n;
  end if;
  execute replace(v_def, v_old, v_new);
end
$do$;

-- ── 5b) LA CAUSA DE VERDAD: ppp_web_armar_tandas agrupaba por CLIENTE ───────
-- El pase (a1) resultó no ser por donde entró D69F. Se probó de punta a punta (una
-- corrida real de gv_ppp_web_armar_pendientes con tres NP de Jazquel —dos de CABA
-- Centro y una de Ciudadela— dentro de una transacción abortada) y las TRES caían
-- en la misma tanda. El armador las junta acá:
--
--   for r_cli in select cliente, …, min(camion) as camion, min(sector) as sector
--                  from _sin_tanda group by cliente …
--
-- **group by cliente**, y de ahí `min(camion)`. Las 9 NP de Jazquel son un solo
-- grupo y el camión que gana es el alfabéticamente menor: 'Capital' < 'GBA Oeste'.
-- Todo el resto de la función ya está bien: `_open` sólo reusa tandas del MISMO
-- camión (v18.28) y `_cam` numera por camión. Lo único mal era la clave del grupo.
--
-- El arreglo es **agrupar por (cliente, camion)** y acotar a ese camión las tres
-- consultas que reparten las NP del grupo (_asig, _open_stops y el chequeo de
-- compatibilidad). Un cliente puede quedar con dos tandas el mismo día: es
-- justamente lo que se quiere, porque son dos camiones.
--
-- Va por reemplazo de texto con guard por la misma razón que (a1): son ~200 líneas
-- de plpgsql y lo que cambia son cinco fragmentos de una línea. Si alguno no
-- aparece exactamente una vez, aborta y no toca nada.
do $do$
declare
  v_def text;
  v_n   int;
  pares text[][] := array[
    ['             min(camion) as camion, min(sector) as sector',
     '             camion, min(sector) as sector'],
    ['       group by cliente
       order by min(camion) collate "C", min(sector) collate "C", sum(m3) desc, cliente',
     '       group by cliente, camion
       order by camion collate "C", min(sector) collate "C", sum(m3) desc, cliente'],
    ['                   join _sin_tanda s on s.cliente = r_cli.cliente',
     '                   join _sin_tanda s on s.cliente = r_cli.cliente and s.camion = r_cli.camion'],
    ['      select s.order_id, s.np_idx, v_code from _sin_tanda s where s.cliente = r_cli.cliente;',
     '      select s.order_id, s.np_idx, v_code from _sin_tanda s where s.cliente = r_cli.cliente and s.camion = r_cli.camion;'],
    ['      select v_code, s.zona, s.sector, s.bnorm from _sin_tanda s where s.cliente = r_cli.cliente;',
     '      select v_code, s.zona, s.sector, s.bnorm from _sin_tanda s where s.cliente = r_cli.cliente and s.camion = r_cli.camion;']
  ];
  i int;
begin
  v_def := pg_get_functiondef('public.ppp_web_armar_tandas(text,date,jsonb,text[],boolean)'::regprocedure);
  for i in 1 .. array_length(pares, 1) loop
    v_n := (length(v_def) - length(replace(v_def, pares[i][1], ''))) / length(pares[i][1]);
    if v_n <> 1 then
      raise exception 'ppp_web_armar_tandas: el fragmento % aparece % veces (esperaba 1). No se toco nada.', i, v_n;
    end if;
    v_def := replace(v_def, pares[i][1], pares[i][2]);
  end loop;
  execute v_def;
end
$do$;
-- ⚠ Este bloque NO es idempotente, y está bien así: re-ejecutarlo no encuentra el
-- fragmento viejo, levanta la excepción y no toca nada.
-- ⚠ Sólo toca la rama `v_sect` (sectores_activos = 1, que es como corre hoy). La rama
-- vieja de "grupo de zona" agrupa por `grupo`, que es más grueso que el camión; si
-- alguna vez se vuelve a `sectores_activos = 0` hay que revisarla.

-- ── 6) Centinela: tandas con dos camiones adentro ───────────────────────────
-- Mismo espiritu que gv_ppp_super_mezclado: vacia = todo bien. Cubre tambien lo
-- que se arma a mano (un GV_PPP_Prog_Override o un arrastre en "A Programar" se
-- saltean las funciones de arriba). Al 16/09 devuelve una sola fila: D69F.
create or replace view public.gv_ppp_tanda_camion_mezclado
with (security_invoker = true) as
select w.fecha_entrega                                        as fecha,
       upper(btrim(w.tanda))                                  as tanda,
       count(*)::int                                          as nps,
       count(distinct btrim(w.cod_cliente))::int              as clientes,
       string_agg(distinct public.gv_ppp_web_camion(w.zona, null), ' + ')  as camiones,
       string_agg(distinct coalesce(w.zona, '(sin zona)'), ' + ')          as zonas
  from public."PPP_Web_Programacion" w
 where coalesce(nullif(btrim(w.tanda), ''), '') <> ''
   and coalesce(w.zona, '') ~ '^\s*Zona\s*[0-9]+'
 group by w.fecha_entrega, upper(btrim(w.tanda))
having count(distinct public.gv_ppp_web_camion(w.zona, null)) > 1;

grant select on public.gv_ppp_tanda_camion_mezclado to anon, authenticated, service_role;

comment on view public.gv_ppp_tanda_camion_mezclado is
  'Tandas web con NP de mas de un camion adentro (v18.86, Luis). Vacia = todo bien. '
  'El camion sale de gv_ppp_web_camion: Capital / GBA Sur / GBA Oeste / GBA Norte.';

commit;
