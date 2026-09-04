-- ══════════════════════════════════════════════════════════════════════════
-- Solapa "A PROGRAMAR" de la PPP · armado manual de tandas · 2026-09-04
-- Corre en VIRGILIO (hrxfctzncixxqmpfhskv)
-- ══════════════════════════════════════════════════════════════════════════
-- El front que pidió el dueño (boceto a mano):
--
--   ┌─ NPs ──────┐   ┌─ Tanda ────┐   ┌─ Calendario ──────────┐
--   │ tarjeta ▾  │   │  F57A      │   │  ◀  Sep 2026  ▶       │
--   │ tarjeta ▾  │ → │            │ → │  Do Lu Ma Mi Ju Vi Sá │
--   │ tarjeta ▾  │   │  m³: 0,55  │   │   ○  ○  ○  ○  ○  ○  ○ │
--   └────────────┘   └────────────┘   └───────────────────────┘
--
-- Cada tarjeta de NP muestra número · zona · fecha de entrada · m³, y se expande
-- para ver los productos. Se ARRASTRA a una tanda. La tanda va sumando m³. Un
-- botón "+" crea otra tanda vacía. Al final se suelta la tanda en un día del
-- calendario y queda programada.
--
-- ──────────────────────────────────────────────────────────────────────────
-- EL PROBLEMA DE FONDO
-- ──────────────────────────────────────────────────────────────────────────
-- Hoy una tanda SOLO existe cuando ya está escrita en `PPP_Web_Programacion` con
-- su código. Ese front necesita una tanda que exista MIENTRAS se arma: sin fecha
-- y sin que la vea nadie del depósito. Ese estado no existía. Todo lo de abajo
-- sale de ahí.
--
-- ⚠ POR QUÉ TABLAS PROPIAS Y NO `fecha_entrega = null`
--   `mergeMonitorPppWeb` (index.html) lee `PPP_Web_Programacion` filtrando SÓLO
--   `tanda=not.is.null`. Un borrador guardado ahí caería en el celular del
--   operario apenas se arrastra la primera NP. Con tablas propias el riesgo es
--   cero y no cambia NADA aguas abajo.
--
-- ⚠⚠ NO TOCA PRODUCCIÓN VIRGILIO. Todo lo que se crea acá es nuevo y con
--    prefijo. De lo compartido sólo se LEE (`PPP_Programacion_Diaria`, para no
--    repetir un código de tanda).
-- ══════════════════════════════════════════════════════════════════════════


-- ── 1 · Las dos tablas ────────────────────────────────────────────────────
create table if not exists public."PPP_Web_Tandas" (
  empresa        text not null,
  codigo         text not null,
  estado         text not null default 'borrador'
                 check (estado in ('borrador','programada','descartada')),
  fecha_entrega  date,
  creado_por     text,
  creado_at      timestamptz not null default now(),
  programada_por text,
  programada_at  timestamptz,
  primary key (empresa, codigo)
);
-- El código es único en TODO el sistema, no por empresa: es lo que tipea el
-- operario en el celular, y ahí no hay empresa que lo desambigüe.
create unique index if not exists ppp_web_tandas_codigo_uk on public."PPP_Web_Tandas" (codigo);
create index if not exists ppp_web_tandas_estado_idx on public."PPP_Web_Tandas" (estado);

create table if not exists public."PPP_Web_Tanda_Items" (
  empresa      text    not null,
  codigo       text    not null,
  order_id     bigint  not null,
  np_idx       integer not null,
  -- FOTO, para que la caja del medio sume m³ y dibuje la tarjeta sin ir a LK en
  -- cada arrastre. Se refresca al recargar la lista.
  np           integer,
  cod_cliente  text,
  razon_social text,
  zona         text,
  m3           numeric,
  m3_parcial   boolean not null default false,
  lineas       integer,
  cajas        numeric,
  fecha_recep  date,
  agregado_por text,
  agregado_at  timestamptz not null default now(),
  primary key (empresa, codigo, order_id, np_idx),
  foreign key (empresa, codigo) references public."PPP_Web_Tandas" (empresa, codigo) on delete cascade
);
-- ⚠ Una NP no puede estar en DOS tandas. Dos supervisores armando al mismo
--   tiempo no se pisan el mismo pedido.
create unique index if not exists ppp_web_tanda_items_np_uk
  on public."PPP_Web_Tanda_Items" (empresa, order_id, np_idx);

-- RLS: misma reja que el resto del módulo — lee cualquiera, escriben los tres
-- mails de supervisor.
alter table public."PPP_Web_Tandas"      enable row level security;
alter table public."PPP_Web_Tanda_Items" enable row level security;
-- (políticas y grants: ver docs/SUPABASE-GESTION-VIRGILIO.md §3.j)


-- ── 2 · El código de tanda ────────────────────────────────────────────────
-- ⚠ BUG QUE ESTO ARREGLA: `ppp_web_proxima_letra()` sólo miraba las dos tablas
--   de programación. Un código reservado en un borrador era invisible, así que
--   el job automático podía emitir EL MISMO CÓDIGO. Ahora mira los borradores, y
--   además las dos vías (manual y automática) consultan `gv_ppp_web_codigo_tomado`
--   antes de emitir.
create or replace function public.gv_ppp_web_codigo_tomado(p_codigo text)
returns boolean language sql stable as $function$
  select exists (select 1 from public."PPP_Programacion_Diaria" where tanda = p_codigo)
      or exists (select 1 from public."PPP_Web_Programacion"    where tanda = p_codigo)
      or exists (select 1 from public."PPP_Web_Tandas"          where codigo = p_codigo
                                                                  and estado <> 'descartada');
$function$;

-- Misma FORMA que las automáticas (PREFIJO + NN + LETRA) para que el operario no
-- note diferencia y para que `ppp_web_proxima_letra` la sepa leer con el prefijo
-- vacío. ⚠ Acá el NN es un CONTADOR, no el índice de zona: una tanda manual
-- arranca vacía, así que todavía no tiene zona cuando recibe el código.
-- (cuerpo: gv_ppp_web_tanda_codigo_nuevo, ver la base)


-- ── 3 · Los avisos: el badge al lado del código ───────────────────────────
-- ⚠ NO BLOQUEAN. Regla del dueño: *"que no bloqueen de momento, que pongan un
--   símbolo badge de que hay algo que normalmente estaría mal al lado del
--   nombre/número de tanda"*. El supervisor programa a mano justo porque el
--   criterio es suyo; el sistema marca, no decide.
--
--   pedido_partido    alta   un pedido entra a medias (red de seguridad, §3.bis)
--   zonas_mezcladas   alta   mezcla grupos de zona distintos
--   sin_zona          alta   hay NP sin zona resuelta
--   cliente_va_solo   alta   Extralim / Dist GM compartiendo tanda
--   super_mezclado    alta   Súper va una tanda por cliente
--   pasa_tope_mezcla  media  junta clientes y pasa los 0,80 m³
--
-- La mezcla de EMPRESAS no está en la lista a propósito: `empresa` es parte de la
-- clave de la tanda, así que LK y CH no se pueden mezclar ni queriendo. Esa regla
-- la garantiza la estructura, no un chequeo.
-- (cuerpo: gv_ppp_web_tanda_avisos + vista gv_ppp_web_tandas_abiertas)


-- ── 3.bis · LA UNIDAD DE ARRASTRE ES EL PEDIDO, NO LA NP ──────────────────
-- La columna de la izquierda lista PEDIDOS (un order_id por tarjeta), no NP
-- sueltas. Se arrastra el pedido ENTERO. La NP se numera al programar (§5), y el
-- corte en bloques ya viene hecho de arriba.
--
-- Lo dejo escrito porque en el camino se discutio al reves y la conclusion del
-- dueno es la que vale: *"si me arrastro el pedido entero de un cliente a la
-- tanda, ahi se le asigna nota de pedido y ahi se parte; de todas formas un
-- pedido de un mismo cliente no se puede partir en diferentes tandas"*.
--
-- EL CORTE EN 18/15 YA EXISTIA, rio arriba, en la vista `v_pedidos_web_np` de LK:
-- `cap` = 18 lineas para LK y 15 para Chef, `n_tramos = ceil(lineas/cap)`, y las
-- lineas se reparten en SERPENTINA (ordenadas por m3 y yendo y viniendo) para que
-- los bloques queden parejos en volumen. No se toco: es de LK.
--
-- LO QUE SI FALTABA: la vista calculaba `n_tramos` y NO LO DEVOLVIA. Sin ese dato
-- la tarjeta del pedido no puede decir "esto va a salir en 3 NP", que es
-- informacion que el supervisor necesita para decidir. Ahora sale:
--   · `gv_pedidos_web_np_lk` y `gv_pedidos_web_np_chef` devuelven `np_total`.
--     (Agregar una columna al RETURNS TABLE obliga a DROP + CREATE; son nuestras
--     y el cron esta apagado.)
--   · `np_total` viaja hasta `PPP_Web_Tanda_Items` y `PPP_Web_Programacion`.
--   · `gv_ppp_web_tanda_agregar` acepta UNA NP o un ARRAY: el front manda el
--     pedido entero de una sola llamada.
--
-- Cuanto pesa esto, medido el 2026-09-04 sobre 30 dias reales:
--   LK    242 de 364 NP (66%) son de pedidos partidos . 99 de 221 pedidos . hasta 6 bloques
--   Chef   23 de  38 NP (60%) . 11 pedidos
-- O sea el pedido partido es la norma, no la excepcion.
--
-- ── RED DE SEGURIDAD: el aviso `pedido_partido` ───────────────────────────
-- Con la unidad de arrastre en el pedido, partirlo entre tandas no deberia poder
-- pasar. El aviso queda igual, como red: salta si una tanda termina con menos
-- bloques de los que tiene el pedido, y dice donde estan los otros
-- (`gv_ppp_web_pedido_bloques`). Cuesta nada y cubre el dia que el front mande un
-- pedido a medias, o que aparezca un bloque nuevo despues (ver los AGREGADOS en
-- docs/SUPABASE-GESTION-VIRGILIO.md 3.h).
--
-- ── 4 · Las acciones ──────────────────────────────────────────────────────
--   gv_ppp_web_tanda_nueva(empresa, por)              el botón "+"
--   gv_ppp_web_tanda_agregar(empresa, cod, np, por)   arrastrar adentro
--   gv_ppp_web_tanda_sacar(empresa, cod, oid, idx)    arrastrar afuera
--   gv_ppp_web_tanda_descartar(empresa, cod)          tirar el borrador
--   gv_ppp_web_tanda_programar(...)                   soltar en el calendario
--   gv_ppp_web_calendario(desde, hasta)               los circulitos
--
-- `_agregar` NO valida reglas de negocio, a propósito (ver §3). Lo único que sí
-- frena es lo que rompería el sistema: una NP en dos tandas, o una tanda cerrada.


-- ── 5 · Programar = el commit ─────────────────────────────────────────────
-- Único punto donde el borrador se vuelve real. TODO en una transacción: o queda
-- la tanda entera con su foto de artículos, o no queda nada. Sin eso se podría
-- programar una tanda que al operario le llega VACÍA (el propio front tiene ese
-- error escrito a mano).
--
-- `p_items` son los artículos, que viven en LK y Virgilio no puede consultar: los
-- manda el front, que ya los tiene cargados para el detalle expandible.
--   [{"order_id":1,"np_idx":1,"items":[{"art":"027","cajas":4}, ...]}, ...]
-- Se suman por código: el carrito puede repetir un artículo y el picking cuenta
-- cajas por código, no renglones. (Probado: 8 + 2 del art 027 → 10.)
--
-- ⚠⚠ LA NP SE NUMERA ACÁ, Y RECIÉN ACÁ.
--   Salió de la prueba: `PPP_Web_Base.np_label` es NOT NULL y la etiqueta se arma
--   con el número, así que sin numerar el operario no puede ni abrir la tanda.
--   Y es el momento CORRECTO: una NP se numera cuando la tanda se programa, que
--   es cuando el pedido se vuelve real para el depósito — no al abrir una
--   pantalla, que es lo que hacía `pwebNumerar()` y por lo que aparecieron 357 NP
--   de prueba el 3 y 4 de septiembre.
--   Como llama a `gv_ppp_web_np_asignar`, hereda su interruptor: HOY, con la
--   numeración apagada, programar corta con el mensaje correcto
--   ("Numeración de NP APAGADA…"). O sea este módulo no se puede usar de verdad
--   hasta que se prenda la numeración. Es una decisión, no un bug.
--
-- Va SECURITY DEFINER porque `gv_ppp_web_np_asignar` está granteada sólo a
-- `service_role`; el candado de esto es el GRANT (authenticated + service_role).
--
-- El cupo del día y el "no es día hábil" AVISAN, no bloquean: vuelven en
-- `aviso_dia`.


-- ══════════════════════════════════════════════════════════════════════════
-- PROBADO EL 2026-09-04, DE PUNTA A PUNTA
-- ══════════════════════════════════════════════════════════════════════════
--   "+" dos veces                     → GV-01A y GV-01B (dos borradores a la vez)
--   2 NP del MISMO cliente, zona 3    → 0,500 m³ · 0 avisos
--   + 1 NP de otro cliente, zona 6    → 1,400 m³ · 2 avisos:
--       "Mezcla 2 zonas distintas: Zonas 2+3 · Zonas 6+7"
--       "Junta 2 clientes y suma 1.400 m³, por encima del tope de 0.80 m³"
--   la misma NP a la otra tanda       → "Esa NP ya está en otra tanda en armado"
--   sacarla y ponerla en GV-01B       → GV-01A vuelve a 0 avisos
--   programar GV-01A al 09/09         → 2 NP · 0,500 m³ · 3 líneas de artículos
--       NP numeradas LK 00001 y LK 00002
--       art 027 venía 8 + 2 → quedó en 10 cajas (suma por código)
--       cabecera 'programada' con fecha y quién · borrador vacío
--   calendario del 09/09              → 1 tanda · 2 NP · 0,500 m³ · restan 4,500
--   con la numeración apagada         → corta con el mensaje de la numeración
--
--   Y el pedido partido, con el pedido REAL 1117 (3 bloques, 17/17/18 líneas):
--     sólo el bloque 1 en GV-01A     → 1 aviso: "entran 1 de 3 bloques. Los otros
--                                      siguen sin programar"
--     el bloque 2 en GV-01B          → LAS DOS tandas se marcan y se nombran
--                                      entre sí ("Los otros borrador GV-01B")
--     el pedido ENTERO de una        → 3 NP · 0,367 m³ · 0 avisos
--
-- El camino feliz se probó prendiendo y apagando la numeración DENTRO de una
-- sola transacción, para no dejar el interruptor abierto ni un segundo.
-- Todo borrado después: las 5 tablas en 0 y `PPP_Programacion_Diaria` en 182.
--
-- ══════════════════════════════════════════════════════════════════════════
-- LO QUE FALTA
-- ══════════════════════════════════════════════════════════════════════════
-- · El FRONT: las tres columnas, el arrastre, el "+" y el badge. Esto es sólo la
--   lógica de atrás, que es lo que pidió el dueño primero.
-- · La lista de la IZQUIERDA la arma el front: las NP viven en LK/Chef y Virgilio
--   no las puede consultar. El front ya las trae; de acá sólo necesita saber
--   cuáles están tomadas (`PPP_Web_Tanda_Items` + `PPP_Web_Programacion`).
-- · Numeración apagada ⇒ programar no funciona todavía. A propósito.


-- ══════════════════════════════════════════════════════════════════════════
-- BUG EN PRODUCCION: 401 al abrir la solapa (2026-09-04, v12.81)
-- ══════════════════════════════════════════════════════════════════════════
-- El dueno abrio el modulo y le dio:
--
--   ⚠ Supabase respondio 401
--   {"code":"42501","message":"permission denied for table GV_Clientes_Reglas"}
--
-- CAUSA. `gv_ppp_web_tandas_abiertas` es `security_invoker = true` (obligatorio,
-- ver el §1 del CLAUDE.md), asi que sus lecturas corren con los permisos de quien
-- llama — el front lee con la anon key. La vista invoca
-- `gv_ppp_web_tanda_avisos`, que consulta `GV_Clientes_Reglas` (que clientes van
-- solos), y esa tabla esta CERRADA a `anon` a proposito.
--
-- ⚠⚠ POR QUE NO LO AGARRO LA PRUEBA: cuando probe la vista como `anon`, NO HABIA
--    NINGUNA TANDA. Con 0 filas la subconsulta correlacionada de los avisos nunca
--    se ejecuta, asi que dio "ok (0 filas)" y parecio sana. El permiso recien se
--    toca cuando hay al menos una tanda que evaluar — o sea reventaba en el
--    primer clic de "+ Nueva tanda".
--
--    LECCION, que vale para cualquier vista de este repo: **probar una vista
--    vacia no prueba nada sobre sus permisos.** Hay que probarla CON datos, y con
--    el rol real que la va a leer.
--
-- ARREGLO. `gv_ppp_web_tanda_avisos` pasa a SECURITY DEFINER con search_path
-- fijo: el candado es el GRANT, que es lo auditable — mismo patron que
-- `gv_pedidos_web_np_*` y `gv_ppp_web_np_asignar`. No amplia lo que se ve: los
-- nombres de cliente que devuelve el aviso ya estan en `PPP_Web_Tanda_Items`,
-- que `anon` lee.
--
-- Verificado con la URL EXACTA que manda el front y con tandas creadas:
--   antes  → 401  permission denied for table GV_Clientes_Reglas
--   despues→ 200  [{"codigo":"GV-01A",...},{"codigo":"GV-01B",...}]
--
-- ── CONTROL, para que no vuelva ────────────────────────────────────────────
--   -- Tiene que devolver filas SIN error. Correr con AL MENOS UNA tanda abierta.
--   set local role anon;
--   select codigo, n_avisos from public.gv_ppp_web_tandas_abiertas;
