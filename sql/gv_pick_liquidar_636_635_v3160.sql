-- v31.60 (Luis, 16/10/2026): «cuando se pida 636E o 635E se manda a pickear el nacional (636 / 635)
-- hasta liquidar el stock; cuando se termina, se discontinúan».
-- Mismo mecanismo que el 574 (v30.29 · v31.54 · v31.56): fila en GV_Pick_Liquidar + PK_LIQUIDAR_EN (index.html).
--   · picking: el 636E/635E de Chef levanta primero el saldo del nacional (góndola + excedente, v31.60).
--   · armado: gv_stock_liquidacion_imputar (cron 68) pasa el nacional pickeado a a_facturar del E.
--   · baja: gv_liquidado_discontinuar (cron 160) da de alta el nacional en Articulos_Discontinuados cuando
--     no le queda saldo > 0 y se facturó la última NP donde se pickeó → libera M36 / M35 y sale de Stocks.
-- Al 16/10: 636 CH = 5 en góndola M36 + 9 en excedente + 6 separadas · 635 CH = 11 en M35. 636E y 635E en 0.
insert into public."GV_Pick_Liquidar" (cod_pedido, cod_liq, empresa, desde, activo, nota)
values ('636E','636','CH', now(), true, 'Luis 16/10 (v31.60): liquidar el 636 nacional dentro de los pedidos de 636E'),
       ('635E','635','CH', now(), true, 'Luis 16/10 (v31.60): liquidar el 635 nacional dentro de los pedidos de 635E')
on conflict do nothing;
-- Chequeo: select * from public."GV_Pick_Liquidar"; select * from gv_liquidado_discontinuar(true);
-- Rollback: update public."GV_Pick_Liquidar" set activo = false where cod_liq in ('636','635');
--           (y sacar las dos filas de PK_LIQUIDAR_EN en index.html)
