-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- v19.60 (Thomas, 2026-09-18) — TODO SE PROGRAMA SOLO, SALVO SÚPER (MENOS CARREFOUR) Y MATIZ
-- ═══════════════════════════════════════════════════════════════════════════════════════════
--
-- Regla del dueño, textual: *"Todos los pedidos que llegan se programan automaticamente. con
-- excepcion de supers (excepto carrefour ya que viene con la fecha desde el pedido que mandan)
-- y Matiz"*.
--
-- Al medirlo contra lo que corría, DOS de las tres partes YA estaban:
--   · los súper no los programa el automático desde la v18.28 (padrón `GV_Supers`);
--   · Carrefour ya era la excepción desde la v19.13 (regla `auto_super` sobre LK 1651, pase (a3)
--     de `gv_ppp_web_armar_pendientes`, que toma el turno de la OC y PISA EL CUPO);
--   · Matiz SA es el cod **4263 de LK**, y ya estaba en `GV_Supers` con `super_key = 'gigot'`
--     (nombre "Gigot"), así que ya quedaba afuera por ser súper. No hizo falta tocar nada.
--
-- Lo que NO era cierto era "todo lo demás automático", y ése es el cambio (bloque 1).
--
-- ⚠ El `CLAUDE.md` decía `zonas_automaticas = '1,2,3'` desde la v13.07. **La base decía `'1,2'`.**
--   Otra vez lo mismo: la doc no es la fuente de verdad, la base sí.


-- ── 1. TODAS LAS ZONAS SE PROGRAMAN SOLAS ───────────────────────────────────────────────────
--   Antes: zonas 1 y 2 en cascada por cupo (pase (b)); las zonas 3 a 7 SÓLO se colgaban de un
--   camión que ya fuera ese día (pase (c)), y si no había camión el pedido quedaba en A Programar.
--   Las 7 zonas son AMBA y mapean a los 4 camiones de siempre (`gv_ppp_web_camion`:
--   1/2/3 → Capital, 4 → GBA Sur, 5 → GBA Oeste, 6/7 → GBA Norte), así que esto NO inventa
--   camiones a otras provincias: el interior viaja por expreso y su zona es el barrio del
--   depósito del expreso (ver el bloque 4).
--
--   Backup: zz_backups."GV_Backup_PPPWebConfig_20260918"
--   Rollback: update public."PPP_Web_Config" set valor_texto = '1,2' where clave = 'zonas_automaticas';

update public."PPP_Web_Config"
   set valor_texto = '1,2,3,4,5,6,7'
 where clave = 'zonas_automaticas';

-- chequeo: las 7 tienen que dar true
-- select z, public.gv_ppp_web_zona_automatica('Zona '||z||' - x') from generate_series(1,7) z;


-- ── 2. CARREFOUR TAMBIÉN EN CHEF ────────────────────────────────────────────────────────────
--   La regla `auto_super` estaba sólo en LK 1651. El espejo de Chef (cod 1087, mismo CUIT
--   30687310434) no la tenía, así que una OC suya que entrara por Chef no se programaba sola.
--   Thomas, 18/09: *"Aplica la regla a Chef tambien como LK para carrefour"*.

insert into public."GV_Clientes_Reglas" (cod_cliente, empresa, regla, nombre, nota, creado_en)
values ('1087','chef','auto_super','Carrefour (espejo Chef de Supermercados Norte)',
 'Thomas 2026-09-18. Espejo del auto_super de LK 1651 (mismo CUIT 30687310434). Entra al armado '
 'automatico aunque este en GV_Supers; sigue SOLO en su tanda y en su camion Super. Si la OC trae '
 'turno, ese es el dia.', now())
on conflict do nothing;

-- chequeo: las dos tienen que dar true
-- select empresa, cod_cliente, public.gv_cliente_auto_super(empresa, cod_cliente)
--   from public."GV_Clientes_Reglas" where regla = 'auto_super';


-- ── 3. EL DÍA CARGADO A MANO AHORA SÍ PROGRAMA ──────────────────────────────────────────────
--   ⚠ ESTE ES EL AGUJERO QUE APARECIÓ AL VERIFICAR, y es el que valía la pena.
--
--   El badge 🕑 de A Programar (v17.74) deja poner día y franja a mano y guarda en
--   `GV_Pedido_Horario` vía `gv_pedido_horario_set`. Lo lleva TODO pedido con zona Retira y todo
--   cliente de `gv_clientes_horario`, con día o sin él.
--
--   Pero los dos pases del armador que miran un día pactado — (a4) Retira y (a3) súper — leían
--   SÓLO `lk_pedidos_match` (lo que eligió el cliente en la página / el turno que trae la OC) y
--   NUNCA `GV_Pedido_Horario`. Consecuencia:
--     · un Retira del Cotizador o recuperado (los que no pasan por el checkout, que es justo el
--       caso que el badge existe para resolver) seguía en A Programar aunque un supervisor le
--       hubiera puesto el día: el botón servía para AVISAR el día, no para que el pedido saliera;
--     · y si alguien recoordinaba el turno con un súper, el automático seguía programando por el
--       turno viejo de la OC aunque en pantalla figurara el nuevo.
--
--   EL MANUAL MANDA, que es la precedencia que el front ya tenía escrita (`aprHorBadge`: *"El
--   horario cargado a mano MANDA sobre el de la OC: si un supervisor lo pisó es porque
--   recoordinó con el súper"*). La clave de `GV_Pedido_Horario` es el `order_id` en texto para
--   los pedidos de la página (`aprHorClave`: order_id si vino de la web, NP si es de ISIS).

create or replace function public.gv_web_retiro_pactado(p_empresa text, p_order_id bigint)
 returns date language sql stable set search_path to 'public'
as $function$
  /* v19.52 (Luis, 2026-09-17) — EL DIA QUE EL CLIENTE ELIGIO PARA RETIRAR. La pagina se lo
     pide al marcar "Retira" (minimo +3 dias habiles, lun-vie) y lo guarda en
     orders.sheets_payload->>'retiro_fecha'. Viaja de LK por el FDW cada 15 min
     (sync_pedidos_match_virgilio -> lk_pedidos_match.retiro_fecha).

     v19.60 (Thomas, 2026-09-18: *"para los que vienen sin eso, se tiene el boton para
     editarlo"*) — AHORA TAMBIEN MIRA EL DIA CARGADO A MANO en GV_Pedido_Horario. Sin esto el
     boton del badge no hacia que el pedido se programara solo. EL MANUAL MANDA, mismo criterio
     que ya usa el front. */
  select coalesce(
    (select h.fecha from public."GV_Pedido_Horario" h
      where h.empresa = p_empresa and h.clave = p_order_id::text and h.fecha is not null
      limit 1),
    (select m.retiro_fecha from public.lk_pedidos_match m
      where m.empresa = p_empresa and m.order_id = p_order_id
      limit 1))
$function$;

create or replace function public.gv_web_turno_pactado(p_empresa text, p_order_id bigint)
 returns date language sql stable set search_path to 'public'
as $function$
  /* v19.13 — la fecha de entrega que exige el super, tal como la trae su OC. Llega de LK por
     el FDW a lk_pedidos_match.fecha_entrega; el texto crudo con hora queda en
     fecha_entrega_txt ("29/09/2026 14:00").

     v19.60 (Thomas, 2026-09-18) — mismo arreglo que gv_web_retiro_pactado: si un supervisor
     recoordino el turno con el super desde el badge, ese dia es el que vale y el pase (a3)
     ahora lo ve. */
  select coalesce(
    (select h.fecha from public."GV_Pedido_Horario" h
      where h.empresa = p_empresa and h.clave = p_order_id::text and h.fecha is not null
      limit 1),
    (select m.fecha_entrega from public.lk_pedidos_match m
      where m.empresa = p_empresa and m.order_id = p_order_id
      limit 1))
$function$;

-- Probado con ESCRITURAS DE VERDAD, no leyendo la funcion (4 casos, y despues borradas):
--   A) fila manual 30/09 sobre un order_id inexistente  -> 30/09   (antes: null, no programaba)
--   B) pedido 1483, solo el dia del cliente             -> 22/09
--   C) 1483 + fila manual 25/09                         -> 25/09   (el manual pisa)
--   D) borrada la fila de prueba                        -> 22/09   (vuelve al del cliente)
-- insert into public."GV_Pedido_Horario" (empresa, clave, np, fecha, franja, origen, actualizado_por)
-- values ('lk','-999','__PRUEBA__','2026-09-30','08:00 a 12:00','manual','__PRUEBA__');
-- select public.gv_web_retiro_pactado('lk', -999);   -- 2026-09-30
-- delete from public."GV_Pedido_Horario" where actualizado_por = '__PRUEBA__';


-- ── 4. LOS 11 BARRIOS DE AMBA QUE FALTABAN EN EL MAPA ───────────────────────────────────────
--   `GV_Zonas_Barrios` es la capa de override sobre `Zonas_Barrios` (la vieja) y estaba VACÍA:
--   todo el mapa vivía en la original. Estas 11 filas son las primeras.
--
--   La zona de cada una sale del mapa que ya existe, no de una opinión: se eligió la zona de los
--   barrios LIMÍTROFES que ya estaban cargados.
--
--   ⚠ `_norm_barrio` baja a minúscula, recorta, colapsa espacios y saca acentos de las vocales
--   (pero NO la ñ) — y NO corrige errores de tipeo. Por eso 'hurlingam' y 'costitucion' necesitan
--   fila propia aunque 'hurlingham' y 'constitucion' ya existan.
--
--   Backup: zz_backups."GV_Backup_ZonasBarrios_20260918" (0 filas: la tabla estaba vacía)
--   Rollback: delete de estas 11 filas.

insert into public."GV_Zonas_Barrios" (barrio_norm, zona, motivo) values
 ('la tablada',      'Zona 5 - GBA Oeste',        'La Matanza, pegado a Lomas del Mirador y Ciudadela, que ya son zona 5. Thomas 18/09.'),
 ('villa madero',    'Zona 5 - GBA Oeste',        'La Matanza, pegado a Tapiales y Lomas del Mirador. Thomas 18/09.'),
 ('tapiales',        'Zona 5 - GBA Oeste',        'La Matanza, pegado a Villa Madero y Ciudadela. Thomas 18/09.'),
 ('paso del rey',    'Zona 5 - GBA Oeste',        'Partido de Moreno; moreno y merlo ya son zona 5. Thomas 18/09.'),
 ('saenz peña',      'Zona 5 - GBA Oeste',        'Tres de Febrero (Av. America); caseros, santos lugares, ciudadela y palomar ya son zona 5. NO es Saenz Peña de Chaco. Thomas 18/09.'),
 ('hurlingam',       'Zona 5 - GBA Oeste',        'Error de tipeo de Hurlingham, que ya es zona 5. _norm_barrio no corrige typos, por eso necesita fila propia. Thomas 18/09.'),
 ('bernal oeste',    'Zona 4 - GBA Sur',          'Partido de Quilmes; bernal y quilmes oeste ya son zona 4. Thomas 18/09.'),
 ('general pacheco', 'Zona 7 - GBA Norte Lejos',  'Partido de Tigre; don torcuato, tigre y garin ya son zona 7. Thomas 18/09.'),
 ('escobar',         'Zona 7 - GBA Norte Lejos',  'Pegado a Garin y Del Viso, ya zona 7, y a la misma distancia que Pilar. Thomas 18/09.'),
 ('parque chas',     'Zona 2 - CABA Centro',      'Barrio de CABA rodeado por Chacarita, Villa Ortuzar y Villa Urquiza, los tres ya zona 2. Thomas 18/09.'),
 ('costitucion',     'Zona 1 - CABA Sur',         'Error de tipeo de Constitucion, que ya es zona 1. Thomas 18/09.')
on conflict (barrio_norm) do nothing;

-- Probado sobre las direcciones REALES del padrón, no sobre la tabla: las 13 direcciones que
-- usaban esos 11 barrios resuelven, y cada una en la zona que corresponde.
-- Direcciones sin zona en `GV_Clientes_Direcciones`: 40 -> 27.


-- ── 5. ⚠ CAMPANA Y ZÁRATE NO SE CARGARON, Y NO ES UN OLVIDO ─────────────────────────────────
--   Las propuse como "¿camión propio o expreso?" y estaba mal planteado. Thomas: *"EL DATO DE
--   ENTREGA VIAJA CON EL PEDIDO DEL CLIENTE, te estas complicando al pedo me parece"*.
--
--   LA LÓGICA QUE YA EXISTE: un cliente del interior lleva un EXPRESO, y `zona_expreso` guarda el
--   **barrio del depósito del expreso en AMBA** — NO la ciudad del cliente. Por eso Salta,
--   Tucumán, Río Grande, Comodoro y Bariloche terminan todos en Zona 1 o Zona 4 (Soldati,
--   Barracas, Pompeya, Parque Patricios, Avellaneda, Lugano, Mataderos) y los entrega el camión
--   propio como a cualquier otro. Campana → expreso Bijarra (Soldati); Zárate → Larraz (Pompeya);
--   La Plata → Caltabiano (Soldati). La respuesta ya estaba en los datos.
--
--   Medido: 945 direcciones con expreso, **944 resuelven zona**. Y sobre los PEDIDOS, que es lo
--   que importa: de 1.172 NP de LK en 120 días, **1.121 (95,6 %) traen `zona_expreso` con el
--   pedido**. Lo que no resuelve son 18 pedidos en 4 meses (21 direcciones), y en todos la
--   sucursal existe y viaja: lo único que falta es el expreso cargado en esa dirección, en el ABM
--   de la PÁGINA (LK/Chef). No hace falta tabla de override en Virgilio ni padrón de expresos.
--
--   Chequeos:
--   select * from public.gv_ppp_web_armado_salud;          -- FEED CAIDO / SIN CORRER = mirar
--   select * from public.gv_ppp_tanda_camion_mezclado;     -- vacía = todo bien
--   select * from public.gv_ppp_cliente_dos_dias;          -- el cliente partido en dos días
--   select * from public.gv_ppp_super_mezclado;            -- vacía = todo bien
--   select * from public.gv_ppp_tanda_dos_dias;            -- vacía = todo bien
