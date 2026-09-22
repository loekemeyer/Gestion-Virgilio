-- v21.20 (2026-09-22, Luis) — A BLISTPACK, OSCAR Y PEDERNERA NO SE LES MANDA OC.
--
-- Luis, textual: "a blistpack/oscar/pedernera no se le manda OC, porque ellos fabrican acorde a
-- lo que le mandamos desde log/fabr" · y antes, sobre 544/560/800: "son pedernera 100%, pero no
-- se le manda la OC a pedernera, solo se le manda a log. Pero la recepcion de mercaderia es
-- mercaderia de Pedernera".
--
-- Son DOS datos distintos y los dos son ciertos:
--   · quien FABRICA y entrega las cajas  -> asi se carga en Recepcion, y esta BIEN
--   · a quien se le EMITE la orden       -> siempre Log/ Fabr, que es el que les manda material
-- Ninguno se "corrige" con el otro. Lo que faltaba es la pieza que los relaciona.
--
-- ⚠ Por que importa, medido el 22/09: `gv_oc_recompute_recibido` imputa por (proveedor, codigo),
--    asi que cuando los dos nombres no coinciden la OC NO SE CIERRA NUNCA. Las diez OC de 544 y
--    560 tienen cantidad_recibida = 0 — 2.190 cajas ordenadas a Log/ Fabr, 2.125 recibidas de
--    Pedernera, ninguna imputada (nueve quedaron 'anulada' y una 'pendiente').
--
-- ⚠ Y hoy conviven las DOS configuraciones para el mismo fabricante, que es el desorden de fondo:
--      544, 560            -> OC a Log/ Fabr  (bien segun la regla)  pero no imputa
--      115, 561, 800..802  -> OC a Pedernera  (mal segun la regla)   e imputa por casualidad
--
-- Esta version SOLO deja el dato y el centinela. NO toca OC_Maximos, NO toca la imputacion y NO
-- cambia ningun estado de OC: eso es dato real y lo autoriza el dueno.

create table if not exists public."GV_OC_Fabrica_Para" (
  fabricante      text primary key,
  recibe_la_oc    text not null,
  nota            text,
  creado_por      text,
  creado_at       timestamptz not null default now()
);
alter table public."GV_OC_Fabrica_Para" enable row level security;
revoke insert, update, delete, truncate on public."GV_OC_Fabrica_Para" from anon, authenticated;

insert into public."GV_OC_Fabrica_Para" (fabricante, recibe_la_oc, nota, creado_por) values
 ('Blistpack','Log/ Fabr','Fabrica con material que le manda Log/ Fabr. ⚠ En Recepcion se carga "Blist-Pack" (con guion) y en OC_Maximos "Blistpack" (sin guion).','Luis (claude-remote)'),
 ('Oscar','Log/ Fabr','Hace el SKIN sobre el articulo terminado que le da Log/ Fabr (regla del dueno, 15/09). Oscar fallecio; sigue su nieto.','Luis (claude-remote)'),
 ('Pedernera','Log/ Fabr','Fabrica con material de Log/ Fabr. Entrega 544, 560 y 561 desde el 10/06/2026.','Luis (claude-remote)')
on conflict (fabricante) do nothing;

-- Centinela: que esta por emitirse a nombre de alguien que no recibe OC.
create or replace view public.gv_oc_proveedor_no_recibe_oc as
 select g.total::int as a_pedir, g.cod, g.descripcion,
        g.proveedor as fabricante, f.recibe_la_oc as la_oc_va_a, f.nota,
        (select coalesce(sum(o.cantidad),0)::int from public."Ordenes_Compra" o
          where norm_cod(o.codigo) = norm_cod(g.cod)
            and gv_norm_prov_key(o.proveedor) = gv_norm_prov_key(g.proveedor)) as cajas_ya_emitidas_mal,
        (select coalesce(sum(o.cantidad_recibida),0)::int from public."Ordenes_Compra" o
          where norm_cod(o.codigo) = norm_cod(g.cod)
            and gv_norm_prov_key(o.proveedor) = gv_norm_prov_key(g.proveedor)) as de_esas_imputadas
   from public.vista_generador_oc g
   join public."GV_OC_Fabrica_Para" f
     on gv_norm_prov_key(f.fabricante) = gv_norm_prov_key(g.proveedor)
  where g.activo and g.tiene_prov_real
  order by g.total desc, g.cod;

alter view public.gv_oc_proveedor_no_recibe_oc set (security_invoker = true);

-- Al 22/09: 225 cajas en 12 lineas por salir a nombre equivocado en la proxima corrida
-- (Blistpack 177 en 10 codigos de bombillas + Manga Repostera; Pedernera 48 en 561 y 801).

-- ══════════════════════════════════════════════════════════════════════════════
-- PENDIENTE DEL DUENO — las dos mitades del arreglo, ninguna aplicada:
--
-- (1) que la OC salga a nombre de quien la recibe. UN solo lugar: gv_oc_generar_pendientes,
--     que es por donde escriben el generador manual Y el automatico (cron 50):
--        v_prov := coalesce((select f.recibe_la_oc from public."GV_OC_Fabrica_Para" f
--                             where gv_norm_prov_key(f.fabricante) = gv_norm_prov_key(v_prov)),
--                           v_prov);
--     ⚠ OC_Maximos NO se toca: su `proveedor` sigue diciendo quien FABRICA, que es cierto y es
--       lo que el dueno pidio conservar el 15/09 ("dejalo ahi").
--
-- (2) que la recepcion del fabricante impute contra la OC de Log/ Fabr. El mecanismo YA EXISTE:
--     gv_norm_prov_keys devuelve un ARRAY de claves y gv_prov_match compara todas contra todas
--     (asi esta resuelto hoy 'pettofrezza' -> 'rafael', hardcodeado adentro de dos funciones).
--     Se le suma esta tabla como fuente y el alias de Pettofrezza se migra ahi.
--     ⚠ Esto FUSIONA los dos nombres a efectos de imputacion. Medido el riesgo: solo 3 codigos
--       tienen entregas de los dos por separado desde el 01/06 — 506 (logfabr 3.439 vs blistpack
--       203), 659 (42 vs 8) y 764 (49 vs 8). En los tres Log/ Fabr es el grueso.
--     ⚠ Y recalcula `cantidad_recibida` y `estado` de OC existentes: va con backup.
-- ══════════════════════════════════════════════════════════════════════════════

-- Chequeo: select * from public.gv_oc_proveedor_no_recibe_oc;   -- vacia = todo emitido a quien corresponde
