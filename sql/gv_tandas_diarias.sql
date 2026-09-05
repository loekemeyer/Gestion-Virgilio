-- ══════════════════════════════════════════════════════════════════════════
-- Armado automático de tandas al comienzo de cada día hábil · 2026-09-04
-- Corre en VIRGILIO (hrxfctzncixxqmpfhskv)
-- ══════════════════════════════════════════════════════════════════════════
-- QUÉ RESUELVE
-- ──────────────────────────────────────────────────────────────────────────
-- `ppp_web_armar_tandas` ya existía y estaba probada, pero **no la llamaba
-- nadie**: 0 referencias en `index.html`, 0 crons. Por eso `PPP_Web_Programacion`
-- tenía 0 filas con 350 NP ya numeradas — la cadena se cortaba justo ahí.
--
-- Lo que pidió el dueño: *"para el comienzo de cada día (lunes a viernes no
-- feriado) tiene que elegir las tandas a armar a ese día"*.
--
-- Este archivo trae lo que faltaba del lado de la BASE. El disparador en sí es
-- la Edge Function `gv-ppp-web-tandas-diarias` + su cron (ver el final).
--
-- ──────────────────────────────────────────────────────────────────────────
-- ⚠⚠ NADA DE ESTO TOCA PRODUCCIÓN VIRGILIO
-- ──────────────────────────────────────────────────────────────────────────
-- Verificado con el grep obligatorio contra `loekemeyer/produccion-virgilio`
-- (HEAD a7b3368) el 2026-09-04:
--
--   ppp_web_armar_tandas ........ 0    PPP_Web_Programacion ... 0
--   PPP_Web_Config .............. 0    ppp_web_proxima_letra .. 0
--   gv_zona_de_barrio ........... 0    planify.feriados ....... 1  (sólo lectura)
--   Zonas_Barrios .............. 18    (sólo lectura, no se escribe)
--
-- Todo lo que se CREA acá es nuevo y con prefijo (`gv_*`, `GV_*`). De lo
-- compartido sólo se LEE: `Zonas_Barrios` y `planify.feriados`. No hay un
-- `create or replace` sobre nada ajeno, ni un trigger sobre tabla compartida, ni
-- un INSERT contra `PPP_Programacion_Diaria`.
--
-- **`ppp_web_armar_tandas` NO se modifica**, aunque sea nuestra y el grep dé 0.
-- Se pensó agregarle el salto de feriados a la fecha de entrega, y no hace falta:
-- si el job sólo corre en día hábil y `dias_hasta_entrega = 0`, la entrega cae en
-- día hábil por construcción. Recién si ese parámetro pasa a > 0 habría que
-- mirarlo — queda anotado abajo, no hecho.
-- ══════════════════════════════════════════════════════════════════════════


-- ── 1 · ¿Es día hábil? ────────────────────────────────────────────────────
-- Lunes a viernes y que no sea feriado. Los feriados salen de `planify.feriados`,
-- que ya mantiene al día el cron `planify_sync_feriados` (35 filas al 2026-09-04,
-- de 2026-01-01 a 2027-12-25, 21 futuros). Se LEE, no se toca.
--
-- SECURITY DEFINER porque `planify` no está abierto a `authenticated`; la función
-- devuelve un booleano y nada más, así que no filtra nada.
create or replace function public.gv_es_dia_habil(p_fecha date default current_date)
returns boolean
language sql
stable
security definer
set search_path = public, planify
as $function$
  select extract(dow from p_fecha) not in (0, 6)
     and not exists (select 1 from planify.feriados f where f.fecha = p_fecha);
$function$;

comment on function public.gv_es_dia_habil(date) is
  'Día hábil = lunes a viernes y no feriado (planify.feriados). Lo usa el armado automático de tandas.';

revoke all on function public.gv_es_dia_habil(date) from public;
grant execute on function public.gv_es_dia_habil(date) to anon, authenticated, service_role;


-- ── 2 · La zona, del lado del servidor ────────────────────────────────────
-- Hasta hoy la zona se resolvía SÓLO en el front (`pwebZonaSugerida` +
-- `pwebLocalidad` + `pwebBarrioDe`). Un job que corre a las 00:01 no tiene front,
-- así que la regla tiene que existir en el backend — que además es donde manda
-- el protocolo del CLAUDE.md: *la lógica de negocio va en el backend y el front
-- puede duplicarla como optimización de UX, nunca al revés*.
--
-- Es la MISMA cascada que hace el front, sin inventar nada:
--   zona_expreso → localidad → parsear la dirección por el último guión
-- y después el diccionario compartido. `zona_expreso` guarda el BARRIO del punto
-- de entrega (el depósito del expreso, para el interior), no la zona, pese al
-- nombre de la columna.

-- 2.a El barrio que sale de una sucursal: "Bragado 5742 - Mataderos" → "Mataderos".
--     Corta por el ÚLTIMO separador y acepta las tres rayas que aparecen en el
--     padrón (-, —, –). Sin exigir espacios: el padrón real no los respeta
--     ("1737-Palermo", "2579- Constitucion").
-- El front hace: i = lastIndexOf(sep); return (i > 0 ? t.slice(i+1) : t).trim()
--   · sin separador           → la cadena entera
--   · separador en la pos. 0  → la cadena entera   (i > 0 es falso)
--   · separador al final      → cadena VACÍA       (slice(i+1) = "")
-- ⚠ La primera versión usaba `rpos > 1` y se equivocaba en los dos últimos casos.
--   `rpos` es la posición desde la DERECHA. Probado contra 13 casos, los 4 bordes
--   incluidos.
create or replace function public.gv_ppp_web_barrio_de(p_sucursal text)
returns text
language sql
immutable
as $function$
  with t as (select btrim(coalesce(p_sucursal, '')) as s),
       p as (select s, length(s) as len,
                    greatest(strpos(reverse(s), '-'),
                             strpos(reverse(s), '—'),
                             strpos(reverse(s), '–')) as rpos
               from t)
  select case
           when s = ''       then ''
           when s ~* 'retir' then 'Retira'
           when rpos = 0     then s        -- sin separador
           when rpos = len   then s        -- separador en el primer caracter
           else btrim(right(s, rpos - 1))  -- rpos = 1 (separador al final) → ''
         end
    from p;
$function$;

comment on function public.gv_ppp_web_barrio_de(text) is
  'Barrio a partir de la sucursal de entrega, cortando por el último guión. Espejo backend de pwebBarrioDe() del front.';

-- 2.b La cascada completa → la zona.
create or replace function public.gv_ppp_web_zona(
  p_zona_expreso text default null,
  p_localidad    text default null,
  p_direccion    text default null)
returns text
language sql
stable
as $function$
  with b as (
    select coalesce(nullif(btrim(coalesce(p_zona_expreso,'')), ''),
                    nullif(btrim(coalesce(p_localidad,'')),    ''),
                    public.gv_ppp_web_barrio_de(p_direccion)) as barrio
  )
  select case
           when coalesce(barrio,'') = '' then null
           when barrio ~* 'retir'        then 'Retira'
           else public.gv_zona_de_barrio(barrio)
         end
    from b;
$function$;

comment on function public.gv_ppp_web_zona(text, text, text) is
  'Zona de un pedido web: zona_expreso → localidad → parseo de la dirección, y después Zonas_Barrios (+ override GV_). Espejo backend de pwebZonaSugerida() del front.';

-- 2.c La misma cuenta, en lote. La Edge Function resuelve 350+ NP por corrida:
--     una llamada por fila serían cientos de round trips.
create or replace function public.gv_ppp_web_zona_lote(p_filas jsonb)
returns table (r_idx int, r_zona text)
language sql
stable
as $function$
  select (x.ord - 1)::int,
         public.gv_ppp_web_zona(x.v->>'ze', x.v->>'loc', x.v->>'dir')
    from jsonb_array_elements(coalesce(p_filas, '[]'::jsonb)) with ordinality as x(v, ord);
$function$;

comment on function public.gv_ppp_web_zona_lote(jsonb) is
  'gv_ppp_web_zona aplicada a un lote. Entrada: [{ze,loc,dir}, ...]. Salida: (índice base 0, zona).';

revoke all on function public.gv_ppp_web_barrio_de(text) from public;
revoke all on function public.gv_ppp_web_zona(text, text, text) from public;
revoke all on function public.gv_ppp_web_zona_lote(jsonb) from public;
grant execute on function public.gv_ppp_web_barrio_de(text)        to anon, authenticated, service_role;
grant execute on function public.gv_ppp_web_zona(text, text, text) to anon, authenticated, service_role;
grant execute on function public.gv_ppp_web_zona_lote(jsonb)       to authenticated, service_role;


-- ── 2.d Agrupación de zonas ───────────────────────────────────────────────
-- Regla del dueño 2026-09-04: *"por zona: 2 y 3 pueden juntarse. 6 con 7. Todas
-- las demás por separado"*. Devuelve la CLAVE con la que se agrupa al armar: dos
-- zonas con la misma clave pueden compartir tanda.
create or replace function public.gv_ppp_web_grupo_zona(p_zona text)
returns text
language sql
immutable
as $function$
  select case
           when coalesce(btrim(p_zona),'') = '' then null
           when (regexp_match(p_zona, '^Zona\s*([0-9]+)'))[1] in ('2','3') then 'Zonas 2+3'
           when (regexp_match(p_zona, '^Zona\s*([0-9]+)'))[1] in ('6','7') then 'Zonas 6+7'
           else btrim(p_zona)
         end;
$function$;

comment on function public.gv_ppp_web_grupo_zona(text) is
  'Clave de agrupación de zonas para armar tandas: 2+3 juntas, 6+7 juntas, el resto sola.';
revoke all on function public.gv_ppp_web_grupo_zona(text) from public;
grant execute on function public.gv_ppp_web_grupo_zona(text) to anon, authenticated, service_role;


-- ── 2.e Clientes con regla propia ─────────────────────────────────────────
-- Tabla, no lista hardcodeada: el dueño va a agregar y sacar clientes de acá sin
-- que haya que tocar una función.
--   'solo'        → siempre tanda propia, no se junta con nadie
--   'prioritario' → no puede esperar en la cola; se programa dentro de la semana
create table if not exists public."GV_Clientes_Reglas" (
  cod_cliente text not null,
  empresa     text not null default 'lk',
  regla       text not null,
  nombre      text,
  nota        text,
  creado_en   timestamptz not null default now(),
  primary key (cod_cliente, empresa, regla),
  constraint gv_clientes_reglas_regla_chk   check (regla in ('solo','prioritario')),
  constraint gv_clientes_reglas_empresa_chk check (empresa in ('lk','chef'))
);

alter table public."GV_Clientes_Reglas" enable row level security;
revoke all on public."GV_Clientes_Reglas" from anon, authenticated;
drop policy if exists gv_clientes_reglas_select on public."GV_Clientes_Reglas";
create policy gv_clientes_reglas_select on public."GV_Clientes_Reglas"
  for select to authenticated using (true);
drop policy if exists gv_clientes_reglas_write on public."GV_Clientes_Reglas";
create policy gv_clientes_reglas_write on public."GV_Clientes_Reglas"
  for all to authenticated
  using      ((auth.jwt() ->> 'email') = any (array['loekemeyer.n8n@gmail.com','loekemeyer.logistica@gmail.com','comexloekemeyer@gmail.com']))
  with check ((auth.jwt() ->> 'email') = any (array['loekemeyer.n8n@gmail.com','loekemeyer.logistica@gmail.com','comexloekemeyer@gmail.com']));
grant select on public."GV_Clientes_Reglas" to authenticated;
grant insert, update, delete on public."GV_Clientes_Reglas" to authenticated;

-- Códigos VERIFICADOS contra `public.customers` de LK el 2026-09-04, no tipeados
-- de memoria: el dueño los nombró como "extralim", "dist gm", "osa" y "horcada".
insert into public."GV_Clientes_Reglas" (cod_cliente, empresa, regla, nombre, nota) values
  ('4114','lk','solo',        'Extralimp S.A.',                'Regla del dueño 2026-09-04: va solo.'),
  ('4080','lk','solo',        'Distribuidora GM S.R.L.',       'Regla del dueño 2026-09-04: va solo.'),
  ('2533','lk','prioritario', 'Osa Distribuidora SRLChemelo',  'Regla del dueño 2026-09-04: se programa sí o sí dentro de la semana.'),
  ('85',  'lk','prioritario', 'Horcada Marcelo Horcada Gustav','Regla del dueño 2026-09-04: se programa sí o sí dentro de la semana.')
on conflict do nothing;

-- ⚠ FALTA UNO. El dueño nombró "torres filigas" y **no existe en ningún padrón**:
--   ni en `customers` de LK ni en `chef_padron`. Los candidatos son
--   `Torres Y Liva S.A Cif` (LK 288 / CH 271) y `Torres Juan Luis` (LK 2266).
--   No se cargó ninguno: meter el cliente equivocado en una regla de prioridad es
--   peor que no tener la regla.


-- ── 3 · Bitácora de las corridas ──────────────────────────────────────────
-- Un job que corre solo a las 00:01 y no deja rastro es un job que nadie puede
-- auditar. Acá queda qué hizo cada corrida, incluidas las que NO hicieron nada
-- (fin de semana, feriado) — que son las que uno quiere poder explicar cuando
-- una mañana no hay tandas.
create table if not exists public."GV_Tandas_Auto_Log" (
  id              bigint generated always as identity primary key,
  corrida_en      timestamptz not null default now(),
  fecha_objetivo  date        not null,
  estado          text        not null,   -- 'ok' | 'salteada' | 'error'
  motivo          text,                   -- por qué se salteó, o el error
  np_leidas       int  not null default 0,
  np_programadas  int  not null default 0,
  tandas          int  not null default 0,
  ms              int,
  detalle         jsonb,                  -- por empresa: tandas, m³, zonas
  constraint gv_tandas_auto_log_estado_chk check (estado in ('ok','salteada','error'))
);

create index if not exists gv_tandas_auto_log_fecha_idx
  on public."GV_Tandas_Auto_Log" (fecha_objetivo desc, corrida_en desc);

alter table public."GV_Tandas_Auto_Log" enable row level security;
revoke all on public."GV_Tandas_Auto_Log" from anon, authenticated;

-- Lectura sólo para los supervisores (los mismos tres de PPP_Web_Config).
-- La escribe la Edge Function con service_role, que saltea RLS.
drop policy if exists gv_tandas_auto_log_select on public."GV_Tandas_Auto_Log";
create policy gv_tandas_auto_log_select on public."GV_Tandas_Auto_Log"
  for select to authenticated
  using ((auth.jwt() ->> 'email') = any (array[
    'loekemeyer.n8n@gmail.com','loekemeyer.logistica@gmail.com','comexloekemeyer@gmail.com']));
grant select on public."GV_Tandas_Auto_Log" to authenticated;


-- ── 4 · Un parámetro más ──────────────────────────────────────────────────
-- La ventana que el job le pide a LK/Chef. El front usa 30 días
-- (`PWEB_VENTANA_DIAS`); acá queda configurable sin tocar código.
-- INSERT-only (`do nothing`): si ya existe, manda lo que haya elegido una persona.
insert into public."PPP_Web_Config" (clave, valor, descripcion) values
  ('ventana_dias', 30,
   'Días hacia atrás que el armado automático le pide a LK/Chef. Espejo de PWEB_VENTANA_DIAS del front.')
on conflict (clave) do nothing;


-- ══════════════════════════════════════════════════════════════════════════
-- CÓMO SE DISPARA
-- ══════════════════════════════════════════════════════════════════════════
-- La Edge Function `gv-ppp-web-tandas-diarias` (código en
-- `supabase/functions/gv-ppp-web-tandas-diarias/index.ts`) hace, en orden:
--
--   1. `gv_es_dia_habil(hoy)` → si es sábado, domingo o feriado, loguea
--      'salteada' y corta. **El día lo mira en hora argentina**, no en UTC.
--   2. Lee LK (`v_pedidos_web_np`) y Chef (RPC `get_pedidos_web_np_chef`) del
--      proyecto de LK, con la ventana de `PPP_Web_Config.ventana_dias`.
--   3. `ppp_web_np_asignar` → numera lo que todavía no tiene número.
--   4. `ppp_web_resync`     → pone al día lo YA programado que cambió anoche.
--   5. `gv_ppp_web_zona_lote` → resuelve la zona de cada NP.
--   6. `ppp_web_armar_tandas` → arma las tandas del día con lo que quedó sin tanda.
--   7. `PPP_Web_Base` → la FOTO de artículos que después pickea el operario.
--      ⚠ `ppp_web_armar_tandas` NO la escribe: el front la escribe aparte, en
--      `pwebGuardarProg`. Sin este paso la tanda queda programada y el operario
--      la abre VACÍA — el propio front tiene ese error escrito a mano.
--   8. Escribe una fila en `GV_Tandas_Auto_Log`.
--
-- La función va con `verify_jwt = true`; el cron le manda la service key, que
-- lee de `lecturacvs.app_secrets` para que no quede literal en `cron.job`.
--
-- Cron APLICADO el 2026-09-04 (jobid 71). 00:01 de Argentina = 03:01 UTC; el
-- rango 1-5 es de más, porque el chequeo de día hábil está adentro de la función
-- y además cubre los feriados, que el cron no sabe:
--
--   select cron.schedule('gv-ppp-web-tandas-diarias', '1 3 * * 1-5', $cron$
--     select net.http_post(
--       url     := 'https://hrxfctzncixxqmpfhskv.supabase.co/functions/v1/gv-ppp-web-tandas-diarias',
--       headers := jsonb_build_object(
--                    'Content-Type', 'application/json',
--                    'Authorization', 'Bearer ' || (select v from lecturacvs.app_secrets
--                                                    where k = 'SUPABASE_SERVICE_ROLE_KEY')),
--       body    := '{}'::jsonb)
--   $cron$);
--
-- Para probar a mano: `?forzar=1` corre aunque sea sábado o feriado, `?dry=1`
-- lee y resuelve zonas sin escribir nada, y `?fecha=YYYY-MM-DD` fija el día.

-- ⚠⚠ EL CRON ESTÁ APAGADO (`active = false`), por decisión del dueño el
--    2026-09-04. Existe con toda su definición y 0 corridas; no dispara.
--    Se apagó, no se borró, para no perder la definición.
--    Prender:  select cron.alter_job((select jobid from cron.job
--                where jobname='gv-ppp-web-tandas-diarias'), active := true);
--    Apagar:   lo mismo con active := false.
--
-- ⚠ SECRETO QUE HAY QUE CARGAR A MANO (sin esto la función no arranca):
--   `GV_LK_SERVICE_KEY` = service_role key del proyecto **LK**
--   (`kwkclwhmoygunqmlegrg`), en Edge Functions → Secrets del proyecto Virgilio.
--   Hace falta porque `v_pedidos_web_np` y `get_pedidos_web_np_chef` piden
--   `authenticated` — con la anon key de LK dan 401, y así tiene que seguir:
--   esas dos traen razón social, dirección y detalle de pedidos.
--
-- ══════════════════════════════════════════════════════════════════════════
-- PROBADO CON DATOS REALES (2026-09-04, transacción revertida)
-- ══════════════════════════════════════════════════════════════════════════
-- 32 NP reales de LK (pedidos 1312-1344) por toda la cadena. 31 programadas en
-- 13 tandas; la única que quedó afuera es la única sin zona. Las reglas se
-- cumplen sobre datos de verdad, no sobre casos inventados:
--
--   E02A  Súper    1 cli · 1 NP · 4,560 m³   una tanda por cliente
--   E04A  Zona 2   1 cli · 2 NP · 1,375 m³   pasa el tope, pero es UN cliente
--                                            → no se parte
--   E03A  Zona 1   1 cli · 1 NP · 1,330 m³   ídem
--   E03D  Zona 1   4 cli · 7 NP · 0,643 m³   junta chicos bajo 1 m³
--   E01A  Retira   2 cli · 2 NP · 0,075 m³   Retira se junta como una zona más
--
-- Y además: ninguna tanda mezcla zonas, las NP de un mismo pedido viajan juntas
-- (un cliente con 5 NP en dos sucursales de la misma zona quedó en UNA tanda), y
-- los códigos arrancan en E porque Producción va por D.
--
-- La zona del backend contra 30 días de pedidos reales de LK: **340 de 355 NP
-- (95,8%)**. Las 15 restantes son del interior sin `zona_expreso` cargado en el
-- padrón —Santa Cruz, Aguilares, Concepción del Uruguay, Río Cuarto— más una
-- fila basura. No es el diccionario: es el padrón de LK.
--
-- Verificado después de la prueba: `PPP_Web_Programacion` volvió a 0 filas,
-- `PPP_Programacion_Diaria` sigue en 182 y no tiene ni una NP web.
--
-- ══════════════════════════════════════════════════════════════════════════
-- LO QUE SALIÓ MAL EN LA PRIMERA CORRIDA REAL (2026-09-04)
-- ══════════════════════════════════════════════════════════════════════════
-- Tres cosas, las tres encontradas por la prueba y no por leer el código:
--
-- 1. **Chef llegaba sin zona: 31 de 38 NP.** No era el diccionario. La RPC de
--    Chef no devolvía `zona_expreso` ni `localidad`, así que la zona caía al
--    parseo de la dirección, que para Chef casi nunca resuelve.
--    ⚠ Esto **ya estaba escrito** en `docs/HANDOFF-PIPELINE-VENTAS.md` desde el
--    principio ("el fallback existe para Retira, etiquetas sueltas y Chef, cuya
--    RPC todavía no trae estas columnas") y no se tomó como pendiente. Era, de
--    hecho, la tarea con la que arrancó la sesión: arreglar la localidad.
--    Arreglado en `gv_pedidos_web_np_chef`, cruzando `chef_customers` +
--    `chef_customer_delivery_addresses` con el MISMO criterio que usa
--    `v_pedidos_web` para LK. Medido: 38 de 38 con zona.
--
-- 2. **Ese arreglo hizo timeout (57014).** Las tablas de Chef son foreign
--    tables: con el lateral adentro del foreign scan hacía un round trip por
--    fila. Se traen con `as materialized` — son chicas (762 / 710 / 762 y 26
--    pedidos en 30 días). Es el mismo truco que ya usaba `v_pedidos_web_np`.
--
-- 3. **`pg_net` corta a los 5 segundos** y la corrida real pasa de eso. Se le
--    pasó `timeout_milliseconds := 120000` y lo ignoró igual. Si el cron
--    esperara, registraría un timeout todos los días y el trabajo podría quedar
--    cortado a la mitad, con escrituras parciales. Por eso la Edge Function
--    ahora **contesta al instante y sigue trabajando con `EdgeRuntime.waitUntil`**;
--    el resultado se mira en `GV_Tandas_Auto_Log`. Con `?dry=1` o `?esperar=1`
--    sí espera, que es como se prueba a mano.
--    Verificado end-to-end con `?fecha=<un domingo>`: HTTP 200 inmediato
--    (`{"ok":true,"encolada":true}`), el log quedó escrito con estado
--    'salteada' en 148 ms, y 0 tandas creadas.
--
-- ══════════════════════════════════════════════════════════════════════════
-- UN SOLO CONTRATO PARA LAS DOS PÁGINAS
-- ══════════════════════════════════════════════════════════════════════════
-- `gv_pedidos_web_np_lk` y `gv_pedidos_web_np_chef` devuelven **las mismas 24
-- columnas, mismo nombre, mismo tipo y mismo orden** (verificado columna por
-- columna). Antes no: al wrapper de LK le faltaban `condicion_pago_code`,
-- `numero_oc`, `provincia` y `arts`.
--
-- De esos, sólo `condicion_pago_code` viaja de verdad a ISIS — está en el
-- `sheets_payload` de los 220 de 220 pedidos de LK de 30 días. **`numero_oc` NO**:
-- está vacío en el 100% de LK y no es parte del formato de ISIS; se devuelve sólo
-- para que las dos funciones tengan las mismas columnas.
--
-- `fecha_entrega_pactada` (nueva): el **turno del súper**, para cuando las páginas
-- lo manden. Hoy sale NULL en las dos (0 de 399 pedidos), pero se lee del
-- `sheets_payload`, así que el día que agreguen el campo empieza a llegar solo,
-- sin tocar el backend.
-- ⚠ NO es lo mismo que `PPP_Web_Programacion.fecha_entrega`: esa la DEFINE la
--   tanda (el día en que se arma). Ésta viene pactada de antemano y de afuera.
--   Por eso el nombre distinto.
--
-- ══════════════════════════════════════════════════════════════════════════
-- AUDITORÍA DE INDEPENDENCIA CONTRA PRODUCCIÓN (2026-09-04)
-- ══════════════════════════════════════════════════════════════════════════
-- El dueño pidió confirmar que las dos apps siguen sin pisarse. Medido:
--
--   26 objetos nuevos o tocados hoy, grep en su repo (HEAD a7b3368) ... 0 refs
--   triggers nuestros sobre tablas que usa Producción ................. 0
--   `create or replace` sobre algo suyo ............................... 0
--   crons nuevos ...................................................... 1, con prefijo
--   `PPP_Programacion_Diaria` ......................................... 182 filas, intacta
--   NP web coladas en la PPP de ISIS .................................. 0
--
-- ── El código de tanda NO los cruza ───────────────────────────────────────
-- Producción está en la letra D (61 tandas, entregas del 02/09 al 28/10) y los
-- códigos no los genera la base: los escribe una persona en el Google Sheet y
-- los trae `sync_ppp_pull_server_side.sql`. Gestión tomaría E.
--
-- Si algún día los códigos coincidieran, **Producción no se entera**: su código
-- no conoce `PPP_Web_Programacion` (0 referencias). El único afectado sería el
-- monitor de GESTIÓN, que a propósito muestra las dos PPP en una sola pantalla
-- (v12.69) agrupando por código de tanda. Es un problema interno nuestro y sólo
-- durante la transición: cuando Gestión reemplace a Producción va a haber una
-- sola fuente y va a seguir la codificación histórica.
--
-- ── La exposición a `anon` es la que ya tiene Producción ──────────────────
-- `PPP_Web_Programacion` es legible por `anon` con `using (true)`. Se planteó
-- cerrarlo y el dueño resolvió dejarlo, porque **es exactamente lo que ya hace
-- Producción**: `PPP_Programacion_Diaria`, `PPP_Base_Pedidos`, `Entregas_Virgilio`
-- y `Facturacion_NP` tienen la misma policy `SELECT / true` para `anon`, y el
-- front las lee con la anon key. No es una superficie nueva.
--
-- ══════════════════════════════════════════════════════════════════════════
-- EL JOB NO PODÍA NUMERAR: `auth.uid()` con service_role es NULL (2026-09-04)
-- ══════════════════════════════════════════════════════════════════════════
-- Se descubrió corriendo el disparador de verdad, no leyendo el código:
--
--   GV_Tandas_Auto_Log id 2 · estado 'error'
--   lk:   ppp_web_np_asignar: HTTP 400 "Se necesita sesión para asignar
--         números de NP."
--   chef: ppp_web_np_asignar: HTTP 400 (idem)
--
-- `ppp_web_np_asignar` arranca con `if auth.uid() is null then raise`. Ese
-- candado tiene sentido para el FRONT (un supervisor logueado), pero el job
-- entra con la service key y ahí `auth.uid()` es NULL — igual que el cron, que
-- usa la misma credencial. O sea: **habría fallado todas las noches**, sin
-- numerar ni una NP y por lo tanto sin armar ni una tanda. Es el mismo bicho que
-- ya nos había comido con la RPC de Chef.
--
-- Chequeadas las otras cuatro funciones de la cadena: `ppp_web_resync`,
-- `ppp_web_armar_tandas`, `ppp_web_proxima_letra` y `gv_ppp_web_zona_lote` no
-- tienen el gate. Era una sola.
--
-- ARREGLO: el candado pasa a ser el GRANT, que además es lo auditable.
-- `gv_ppp_web_np_asignar` tiene la lógica y **la original delega en ella**, así
-- que la numeración vive en UN solo lugar y no puede driftear. El front no
-- cambia en nada: sigue entrando por `ppp_web_np_asignar` y sigue exigiendo
-- sesión.

-- El interruptor: hoy la NP la manda ISIS y Gestion NO numera nada.
insert into public."PPP_Web_Config" (clave, valor, descripcion)
values ('numeracion_activa', 0,
        '0 = Gestion NO asigna numeros de NP. Hoy la NP la manda ISIS a la hoja de calculos y la usa Produccion. Se prende (=1) el dia que Gestion tome control: ahi numera los pedidos pendientes y los que vayan cayendo.')
on conflict (clave) do nothing;

create or replace function public.gv_ppp_web_np_asignar(p_empresa text, p_pares jsonb)
returns table(r_order_id bigint, r_np_idx integer, r_np integer)
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_next integer;
begin
  -- ⚠ Hasta que Gestion reemplace a Produccion, la NP la manda ISIS y Gestion
  --   no numera NADA. Sin este candado la pantalla de la PPP Web numeraba sola
  --   todo lo que mostraba con solo abrirla: asi aparecieron 357 NP de prueba
  --   los dias 3 y 4 de septiembre de 2026.
  if coalesce((select valor from public."PPP_Web_Config" where clave = 'numeracion_activa'), 0) <> 1 then
    raise exception 'Numeración de NP APAGADA (PPP_Web_Config.numeracion_activa = 0). Se prende el día que Gestión tome control de Producción.';
  end if;

  -- Serializa por empresa: el job y una pantalla abierta no pueden sacar el
  -- mismo numero. Se libera sola al terminar la transaccion.
  perform pg_advisory_xact_lock(hashtext('ppp_web_np:' || p_empresa));

  select greatest(
           coalesce((select max(n.np) from public."PPP_Web_NP" n where n.empresa = p_empresa), 0) + 1,
           coalesce((select s.desde from public."PPP_Web_NP_Seed" s where s.empresa = p_empresa), 1)
         )
    into v_next;

  with pedir as (
    select (x->>'order_id')::bigint as oid, (x->>'np_idx')::int as idx
    from jsonb_array_elements(p_pares) x
  ),
  nuevos as (
    select p.oid, p.idx,
           row_number() over (order by p.oid, p.idx) - 1 as offset_rn
    from pedir p
    where not exists (
      select 1 from public."PPP_Web_NP" n
       where n.empresa = p_empresa and n.order_id = p.oid and n.np_idx = p.idx)
  )
  insert into public."PPP_Web_NP" (empresa, np, order_id, np_idx)
  select p_empresa, v_next + nu.offset_rn::int, nu.oid, nu.idx
  from nuevos nu
  on conflict (empresa, order_id, np_idx) do nothing;

  return query
    with pedir as (
      select (x->>'order_id')::bigint as oid, (x->>'np_idx')::int as idx
      from jsonb_array_elements(p_pares) x
    )
    select n.order_id, n.np_idx, n.np
      from public."PPP_Web_NP" n
      join pedir p on p.oid = n.order_id and p.idx = n.np_idx
     where n.empresa = p_empresa;
end
$function$;

-- El candado. `anon` no la alcanza ni con la key publica; `authenticated`
-- tampoco: el front entra por la de abajo, que le pide sesion.
revoke all on function public.gv_ppp_web_np_asignar(text, jsonb) from public, anon, authenticated;
grant execute on function public.gv_ppp_web_np_asignar(text, jsonb) to service_role;

-- La puerta del FRONT: mismo gate de sesion de siempre, pero delega.
create or replace function public.ppp_web_np_asignar(p_empresa text, p_pares jsonb)
returns table(r_order_id bigint, r_np_idx integer, r_np integer)
language plpgsql security definer set search_path to 'public'
as $function$
begin
  if auth.uid() is null then
    raise exception 'Se necesita sesión para asignar números de NP.';
  end if;
  return query select * from public.gv_ppp_web_np_asignar(p_empresa, p_pares);
end
$function$;

-- ══════════════════════════════════════════════════════════════════════════
-- ⚠⚠⚠  LA NUMERACIÓN ARRANCA EL DÍA QUE GESTIÓN TOME CONTROL, NO ANTES
-- ══════════════════════════════════════════════════════════════════════════
-- Regla del dueño (2026-09-04): *"actualmente Producción Virgilio usa las NP
-- que manda ISIS a la hoja de cálculos. Cuando Gestión Virgilio tome control,
-- va a asignarle la numeración nuestra a los pedidos que estén pendientes y a
-- los que vayan cayendo. Recién ahí que empiece"*.
--
-- Por eso `numeracion_activa = 0` y las DOS puertas cortan.
--
-- POR QUÉ HACÍA FALTA UN INTERRUPTOR Y NO ALCANZABA CON BORRAR: la pantalla de
-- la PPP Web llama a `pwebNumerar()` al abrirse y numera TODO lo que muestra,
-- sola, sin que nadie apriete nada. Así aparecieron 357 NP de LK (1343..1699)
-- los días 3 y 4 de septiembre, sólo por abrir la pantalla mientras
-- trabajábamos. Borrarlas sin apagar el grifo las traía de vuelta a la próxima.
-- Verificado que no eran pedidos de Producción: 0 en `PPP_Programacion_Diaria`,
-- 0 en `Facturacion_NP`, 0 en `Registros_Produccion_Virgilio`. Backup en
-- `sql/backups/backup_PPP_Web_NP_20260904.sql` y tabla vaciada (0 filas).
--
-- EL DÍA DEL CAMBIO son DOS líneas, no una:
--
--   update public."PPP_Web_Config" set valor_texto = '' where clave = 'tanda_prefijo';
--   update public."PPP_Web_Config" set valor       = 1  where clave = 'numeracion_activa';
--
-- De qué número arranca ya está decidido (dueño, 2026-09-04): **de 00001, las
-- dos empresas**. `PPP_Web_NP_Seed` = lk 1 · chef 1, así que el primer pedido
-- que numere Gestión va a ser `LK 00001` / `CH 00001`.
--
--   select * from public."PPP_Web_NP_Seed";   -- lk 1 · chef 1
--
-- El 1343 que tenía LK antes era arbitrario (se había elegido para que se
-- pareciera al número de pedido de la página) y se descartó. No hay choque
-- posible con Producción: sus NP son de 5 dígitos y arrancan en 44361.
--
-- Probado el 2026-09-04, las dos puertas:
--   gv_ppp_web_np_asignar (job)   → cortó por el interruptor
--   ppp_web_np_asignar (front)    → cortó por el interruptor TAMBIÉN con sesión
--                                   viva (`set local request.jwt.claims`), o sea
--                                   no queda tapado por el gate de sesión
--   PPP_Web_NP quedó en 0 filas · PPP_Programacion_Diaria intacta en 182
--
-- ══════════════════════════════════════════════════════════════════════════
-- La ETIQUETA de la NP · fuente de verdad
-- ══════════════════════════════════════════════════════════════════════════
-- "LK 0001" / "CH 0001": prefijo de empresa + espacio + CUATRO digitos.
-- (2026-09-05, dueño: "que tengan 4 digitos los de pagina". Hasta ese dia eran 5;
--  se cambio antes de numerar el primero: PPP_Web_NP tenia 0 filas.)
-- El front (`pwebNpLabel`) y la Edge Function (`npLabel`) la duplican SOLO como
-- optimizacion de UX. Si cambia el formato, se cambia PRIMERO aca.
create or replace function public.gv_ppp_web_np_label(p_empresa text, p_np integer)
returns text language sql immutable as $function$
  select case when lower(coalesce(p_empresa,'')) in ('chef','ch') then 'CH' else 'LK' end
      || ' '
      -- 2026-09-05 (dueño): CUATRO digitos, no cinco. "LK 0001".
      -- lpad TRUNCA si el texto ya es mas largo que el ancho: lpad('12345',4,'0')
      -- devuelve '1234'. Con la guarda, pasado 9999 la etiqueta simplemente
      -- crece (LK 10000) en vez de repetir un numero que ya existe.
      || case when length(p_np::text) >= 4 then p_np::text
              else lpad(p_np::text, 4, '0') end;
$function$;

grant execute on function public.gv_ppp_web_np_label(text, integer) to anon, authenticated, service_role;

-- Probado el 2026-09-05, las tres implementaciones dan lo mismo
-- (backend, front y Edge Function), incluido el borde que truncaba:
--   lk/1 → LK 0001 · chef/1 → CH 0001 · lk/357 → LK 0357 · lk/12345 → LK 12345

-- ── La lógica de numeración, para que no haya que leerla del cuerpo ────────
--   · un número por (empresa, order_id, np_idx) — un pedido web se puede
--     partir en varias NP, y cada parte lleva la suya
--   · correlativo POR EMPRESA desde el seed de `PPP_Web_NP_Seed`:
--     LK 1343 (donde quedó la numeración a mano), Chef 1
--   · idempotente: pedir dos veces el mismo par devuelve el mismo número y no
--     inserta nada (`on conflict do nothing`)
--   · serializado con advisory lock por empresa: el job y dos pantallas
--     abiertas no pueden sacar el mismo número
--   · la NP viaja ETIQUETADA ("LK 1343"), no pelada: `empresaDeNp` resuelve la
--     empresa por el número (>90000 = LK) y una NP web de 4 dígitos caería en
--     Chef, mandando a buscar un pedido de Loekemeyer al sector equivocado
--
-- Medido el 2026-09-04, no supuesto (con la numeración todavía prendida, antes
-- de apagarla y vaciar la tabla — o sea: la lógica quedó probada, lo que no
-- corre hoy es el permiso para usarla):
--   · LK: 357 asignadas, 1343 → 1699, **0 duplicados y 0 huecos**
--   · Chef: 0 asignadas todavía
--   · sin choque con Producción: sus NP numéricas arrancan en 44361 y en el
--     rango 1..2000 hay 0
--   · llamada como el job (`set local role service_role`, `auth.uid()` NULL)
--     sobre pares que ya tenían número → devolvió 1343,1344,1345 y no escribió
--     una fila
--   · matriz de permisos:
--       anon           gv_ NO · original NO
--       authenticated  gv_ NO · original SÍ   (el front, con sesión)
--       service_role   gv_ SÍ · original SÍ   (el job)
--
-- ── Y un bicho del disparador que salió del mismo error ───────────────────
-- La prueba se lanzó con `{"dry":true}` en el BODY, pero la función leía los
-- flags SÓLO del query string. No dio error: los ignoró en silencio y corrió
-- por el camino REAL creyendo uno que era una prueba. No llegó a escribir nada
-- (murió en la numeración), pero el próximo caso podía no tener esa suerte.
-- Ahora `flag()` mira query Y body. Un flag de seguridad que se ignora sin
-- avisar es peor que no tenerlo.

-- ══════════════════════════════════════════════════════════════════════════
-- CONTROLES
-- ══════════════════════════════════════════════════════════════════════════
--   -- Las corridas de la última semana:
--   select corrida_en, fecha_objetivo, estado, motivo, np_leidas, np_programadas, tandas, ms
--     from public."GV_Tandas_Auto_Log" order by id desc limit 20;
--
--   -- Las tandas armadas para hoy:
--   select tanda, zona, count(*) np, count(distinct cod_cliente) clientes,
--          round(sum(m3),3) m3
--     from public."PPP_Web_Programacion" where fecha_entrega = current_date
--    group by 1,2 order by 1;
--
--   -- Producción intacta: ninguna NP web se coló en la PPP de ISIS (tiene que dar 0):
--   select count(*) from public."PPP_Programacion_Diaria" where np ~* '^(LK|CH) ';
--
--   -- La zona del backend y la del front tienen que coincidir (tiene que dar 0):
--   select count(*) from public."PPP_Web_Programacion" p
--    where p.barrio is not null
--      and p.zona is distinct from public.gv_ppp_web_zona(p.barrio, null, null);
--
-- ══════════════════════════════════════════════════════════════════════════
-- PENDIENTE (anotado, no hecho)
-- ══════════════════════════════════════════════════════════════════════════
-- · `ppp_web_armar_tandas` corre la fecha de entrega al lunes si cae fin de
--   semana, pero **no saltea feriados**. Hoy da igual (`dias_hasta_entrega = 0`
--   y el job sólo corre en día hábil). Si ese parámetro pasa a > 0, la entrega
--   puede caer en feriado y ahí sí hay que meterle `gv_es_dia_habil`.
-- · Retira / Súper / Expo: Súper ya sale una tanda por cliente y Retira se junta
--   como una zona más. **Expo no tiene evidencia histórica** (0 tandas en 120
--   días) y hoy se trata como una zona más. Sin definir.
-- ══════════════════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════════════════
-- SOLO ZONA 1 Y ZONA 2 SE PROGRAMAN SOLAS · 2026-09-04
-- ══════════════════════════════════════════════════════════════════════════
-- Regla del dueño: *"para el armado de tandas y programación, que sólo los
-- pedidos de zona 1 y zona 2 sean automáticamente programados, el resto tienen
-- que ser programados manualmente"*.
--
-- Va por config y no hardcodeado, para que sumar una zona sea un UPDATE:
--
--   update public."PPP_Web_Config" set valor_texto = '1,2,3'
--    where clave = 'zonas_automaticas';
--
-- Lo que queda afuera NO se pierde ni se marca de ninguna forma: simplemente no
-- recibe tanda, o sea ni siquiera entra a `PPP_Web_Programacion`. Así es como ya
-- se ve un pedido pendiente en la pantalla de la PPP Web, y cada corrida los
-- vuelve a mirar — el día que se agregue la zona a la lista entran solos.

insert into public."PPP_Web_Config" (clave, valor, valor_texto, descripcion)
values ('zonas_automaticas', null, '1,2',
        'Numeros de zona que el armado automatico programa SOLO. El resto (zonas 3+, Retira, Super, Expo, y cualquier cosa sin zona) queda SIN tanda, esperando que una persona la programe a mano. Vacio = ninguna zona automatica. Regla del dueno, 2026-09-04.')
on conflict (clave) do nothing;

-- Separado de `ppp_web_armar_tandas` para poder probarlo suelto y para que el
-- front pueda pintar distinto lo que va a mano.
create or replace function public.gv_ppp_web_zona_automatica(p_zona text)
returns boolean language sql stable as $function$
  select coalesce(
    (regexp_match(coalesce(p_zona,''), '^\s*Zona\s*([0-9]+)'))[1] = any (
      select btrim(z) from unnest(string_to_array(
        coalesce((select valor_texto from public."PPP_Web_Config" where clave='zonas_automaticas'), ''),
        ',')) z
      where btrim(z) <> ''
    ), false);
$function$;

grant execute on function public.gv_ppp_web_zona_automatica(text) to anon, authenticated, service_role;

-- ── Probado el 2026-09-04 ──────────────────────────────────────────────────
-- El helper, contra los valores de zona que existen de verdad:
--   Zona 1 → sí · Zona 2 → sí · Zona1 (sin espacio) → sí
--   Zona 3 · Zona 6 · Zona 7 · Zona 10 · Retira · Super · Expo · (sin zona)
--   · '' · null → NO
--   ⚠ `Zona 10` da NO, no se confunde con la 1: el capture group toma '10'.
--
-- El armado entero, con 8 pedidos de todas las zonas (filas de mentira, borradas
-- después; `PPP_Web_Programacion` volvió a 0 y Producción quedó en 182):
--   Zona 1  ×2 clientes → GV-01A  (0,550 m³)   ← programados
--   Zona 2  ×1 cliente  → GV-02A  (0,400 m³)   ← programado
--   Zona 3 · Zona 6 · Zona 10 · Retira · Super → SIN fila en PPP_Web_Programacion
--
-- Es decir: los 5 que van a mano no quedaron a medias ni con tanda vacía, no
-- existen en la programación. Y las zonas 1 y 2 fueron a tandas SEPARADAS, que es
-- la regla de siempre (sólo se juntan los pares definidos: 2+3 y 6+7).
--
-- ⚠ PENDIENTE, hablado: cómo se programan a mano. Hoy la pantalla de la PPP Web
--   ya los muestra sin tanda y un supervisor puede programarlos ahí, pero no hay
--   nada que los DESTAQUE como "estos van a mano". Falta definirlo.
