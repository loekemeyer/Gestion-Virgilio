-- ════════════════════════════════════════════════════════════════════
-- CARGA INICIAL de GV_Lugar / GV_Lugar_Item — 2026-09-11
--
-- Origen: relevamiento hecho EN EL DEPÓSITO sobre
-- docs/relevamiento-lugares-deposito-20260911.xlsx (hoja "A resolver"),
-- 41 de los 70 conflictos resueltos a mano. Lo que dijo el depósito MANDA
-- sobre lo que dicen las tablas viejas.
--
-- SOLO ARTÍCULOS. Los insumos quedan afuera por decisión de Luis (11/09):
-- se descartaron 100 items de insumo y 52 lugares que sólo tenían insumos
-- (entre ellos los 20 racks R##AD/AT y V##AD/AT, que son de insumos).
--
-- Resultado: 820 lugares (688 góndola + 132 rack) y 797 asignaciones
-- sobre 334 códigos distintos. 71 lugares quedan libres.
--
-- Criterios aplicados:
--   · sector normalizado con gv_norm_sector() → J01, nunca J1
--   · códigos sin ceros a la izquierda (066 = 66) y sin sufijo de empresa
--     (437E LK = 437E): la empresa la da el LUGAR
--   · tipo: góndola si el lugar aparece en Planimetria/Capacidad_Sector;
--     rack si sólo aparece en Racks_Planimetria/Ubicaciones_Articulos(racks)
--   · empresa: la que traen las tablas viejas; 4 lugares quedan en null
--
-- ROLLBACK:
--   delete from public."GV_Lugar_Item" where sector is not null;
--   delete from public."GV_Lugar"      where sector is not null;
-- ════════════════════════════════════════════════════════════════════

insert into public."GV_Lugar"(sector,tipo,empresa)
select unnest(string_to_array('Ñ53',' ')),'gondola',null
union all
select unnest(string_to_array('L01 L02 L03 L04 L05 L06 L07 L08 L09 L10 L11 L12 L13 L14 L15 L16 L17 L18 L19 L20 L21 L22 L23 L24 L25 L26 L27 L28 L29 L30 L31 L32 L33 L34 L35 L36 L37 L38 L39 L40 L41 L42 L43 L44 L45 L46 L47 L48 L49 L50 L51 L52 L53 L54 L55 L56 L57 L58 L59 L60 M01 M02 M03 M04 M05 M06 M07 M08 M09 M10 M11 M12 M13 M14 M15 M16 M17 M18 M19 M20 M21 M22 M23 M24 M25 M26 M27 M28 M29 M30 M31 M32 M33 M34 M35 M36 M37 M38 M39 M40 M41 M42 M43 M44 M45 M46 M47 M48 M49 M50 M51 M52 M53 M54 M55 M56 M57 M58 M59 M60 P01 P02 P03 P04 P05 P06 P07 P08 P09 P10 P11 P12 P13 P14 P15 P16 P17 P18 P19 P20 P21 P22 P23 P24 P25 P26 P27 P28 P29 P30 P31 P32 P33 P34 P35 P36 P37 P38 P39 P40 Ñ56 Ñ57',' ')),'gondola','CH'
union all
select unnest(string_to_array('A01 A02 A03 A04 A05 A06 A07 A08 A09 A10 A11 A12 A13 A14 A15 A16 A17 A18 A19 A20 A21 A22 A23 A24 A25 A26 A27 A28 A29 A30 A31 A32 A33 A34 A35 A36 A37 A38 A39 A40 A41 A42 A43 A44 A45 A46 A47 A48 A49 A50 A51 A52 A53 A54 A55 A56 A57 A58 A59 A60 A61 A62 A63 A64 A65 A66 A67 A68 A69 A70 A71 A72 A73 A74 A75 A76 A77 A78 A79 A80 A81 A82 A83 A84 A85 AD09 B01 B02 B03 B04 B05 B06 B07 B08 B09 B10 B11 B12 B13 B14 B15 B16 B17 B18 B19 B20 B21 B22 B23 B24 B25 B26 B27 B28 B29 B30 B31 B32 B33 B34 B35 B36 B37 B38 B39 B40 B41 B42 B43 B44 B45 B46 B47 B48 B49 B50 B51 B52 B53 B54 B55 B56 B57 B58 B59 B60 C01 C02 C03 C04 C05 C06 C07 C08 C09 C10 C11 C12 C13 C14 C15 C16 C17 C18 C19 C20 D01 D02 D03 D04 D05 D06 D07 D08 D09 D10 D11 D12 D13 D14 D15 D16 D17 D18 D19 D20 D21 D22 D23 D24 D25 D26 D27 D28 D29 D30 D31 D32 D33 D34 D35 D36 D37 D38 D39 D40 D41 D42 D43 D44 D45 D46 D47 D48 D49 D50 D51 D52 D53 D54 D55 D56 D57 D58 D59 D60 E01 E02 E03 E04 E05 E06 E07 E08 E09 E10 E11 E12 E13 E14 E15 E16 E17 E18 E19 E20 F01 F02 F03 F04 F05 F06 F07 F08 F09 F10 F11 F12 F13 F14 F15 F16 F17 F18 F19 F20 F21 F22 F23 F24 F25 F26 F27 F28 F29 F30 F31 F32 F33 F34 F35 F36 F37 F38 F39 F40 F41 F42 F43 F44 F45 F46 F47 F48 F49 F50 F51 F52 F53 F54 F55 F56 F57 F58 F59 F60 G01 G02 G03 G04 G05 G06 G07 G08 G09 G10 G11 G12 G13 G14 G15 G16 G17 G18 G19 G20 H01 H02 H03 H04 H05 H06 H07 H08 H09 H10 H11 H12 H13 H14 H15 H16 H17 H18 H19 H20 H21 H22 H23 H24 H25 H26 H27 H28 H29 H30 H31 H32 H33 H34 H35 H36 H37 H38 H39 H40 H41 H42 H43 H44 H45 H46 H47 H48 H49 H50 H51 H52 H53 H54 H55 H56 H57 H58 H59 H60 I01 I02 I03 I04 I05 I06 I07 I08 I09 I10 I11 I12 I13 I14 I15 I16 I17 I18 I19 I20 J01 J02 J03 J04 J05 J06 J07 J08 J09 J10 J11 J12 J13 J14 J15 J16 J17 J18 J19 J20 J21 J22 J23 J24 J25 J26 J27 J28 J29 J30 J31 J32 J33 J34 J35 J36 J37 J38 J39 J40 J41 J42 J43 J44 J45 J46 J47 J48 J49 J50 J51 J52 J53 J54 J55 J56 J57 J58 J59 J60 Y29 Z07',' ')),'gondola','LK'
union all
select unnest(string_to_array('Ñ01 Ñ02 Ñ03 Ñ04 Ñ05 Ñ06 Ñ07 Ñ08 Ñ09 Ñ10 Ñ11 Ñ12 Ñ13 Ñ14 Ñ15 Ñ16 Ñ17 Ñ18 Ñ19 Ñ20 Ñ21 Ñ22 Ñ23 Ñ24 Ñ25 Ñ26 Ñ27 Ñ28 Ñ29 Ñ30 Ñ31 Ñ32 Ñ33 Ñ34 Ñ35 Ñ36 Ñ37 Ñ38 Ñ39 Ñ40 Ñ41 Ñ42 Ñ43 Ñ44 Ñ45 Ñ46 Ñ47 Ñ48 Ñ49 Ñ50 Ñ51 Ñ52 Ñ54 Ñ55 Ñ58 Ñ59 Ñ60',' ')),'gondola','LOKE'
union all
select unnest(string_to_array('AD06 X05 Y01',' ')),'rack',null
union all
select unnest(string_to_array('AA01 AC10 AD05 X03 Y28',' ')),'rack','CH'
union all
select unnest(string_to_array('AA02 AA03 AA04 AA05 AA06 AA07 AA08 AA09 AA10 AA11 AA12 AB01 AB02 AB03 AB04 AB05 AB06 AB07 AB08 AB09 AB10 AB11 AB12 AC01 AC02 AC03 AC04 AC05 AC07 AC08 AC09 AC11 AC12 AD01 AD02 AD03 AD07 AD08 AD10 AD11 AD12 AE01 AE09 AE10 AE11 N03 N04 N05 N06 N08 N10 N12 R20 R21 R22 R23 R24 R25 R26 R27 R28 V17 V18 V19 V20 W01 W02 W03 W04 W05 W06 X01 X02 X04 X06 X07 X08 X10 X11 X12 X13 X14 X15 X16 X17 X18 X19 X25 X26 X27 X28 X29 X30 Y02 Y03 Y04 Y05 Y06 Y07 Y08 Y09 Y10 Y11 Y12 Y13 Y14 Y15 Y16 Y17 Y18 Y19 Y20 Y21 Y22 Y23 Y24 Y25 Y26 Y27 Y30 Z05 Z06 Z09 Z11',' ')),'rack','LK';

insert into public."GV_Lugar_Item"(sector,cod,clase)
select split_part(x,':',1), split_part(x,':',2), 'articulo'
from unnest(string_to_array('A01:502 A02:502 A03:502 A04:502 A05:321 A06:502 A07:502 A08:502 A09:502 A10:321 A11:501 A12:501 A13:501 A14:501 A15:321 A16:501 A17:501 A18:501 A19:501 A20:321 A21:504 A22:504 A23:504 A24:504 A25:321 A26:504 A27:504 A28:504 A29:504 A30:321 A31:504 A32:504 A33:504 A34:504 A35:321 A36:504 A37:504 A38:504 A39:504 A40:321 A41:506 A42:506 A43:506 A44:506 A45:321 A46:506 A47:506 A48:506 A49:506 A50:323 A51:506 A52:506 A53:506 A54:506 A55:607E A56:506 A57:506 A58:506 A59:506 A61:66 A62:355 A62:66 A63:66 A64:548 A64:565 A65:396 A65:556 A66:248 A67:332 A67:338 A68:500 A69:500 A70:395 A71:248 A72:393 A72:563 A73:394 A73:554 A74:508 A75:518 A76:246 A77:561 A78:336 A78:390 A79:391 A81:246 A82:560 A84:392 A85:573 AA03:601E AA04:583E AA07:960E AA09:933E AA11:933E AB01:PEDIDOS AB02:PEDIDOS AB04:937E AB05:816E AB07:PEDIDOS AB08:PEDIDOS AB09:935E AB11:935E AB12:932E AC01:PEDIDOS AC02:PEDIDOS AC03:870E AC04:437E AC05:598E AC07:PEDIDOS AC08:PEDIDOS AC09:817E AC10:712E AC11:367E AC12:367E AD02:522S AD03:816E AD05:809E-QUESO AD06:368E AD08:CAJAS AD09:505I AD10:812E AD11:438E AD12:1546903 AE01:361E AE09:1546903 AE09:366E AE10:812E AE11:809E-PIZZA B01:530 B02:530 B03:530 B04:530 B05:520 B06:520 B07:520 B08:520 B09:531 B10:531 B11:521 B12:521 B13:523 B14:523 B15:523 B16:523 B17:510 B18:510 B19:510 B20:510 B21:510 B22:510 B23:510 B24:510 B25:586 B26:586 B27:586 B28:586 B29:586 B30:586 B31:586 B32:586 B33:586 B34:586 B35:586 B36:586 B37:586 B38:586 B39:586 B40:586 B41:586 B42:586 B43:586 B44:586 B45:575 B46:575 B47:575 B48:586 B49:577 B50:577 B51:577 B52:586 B53:579 B54:579 B55:579 B56:586 B57:57 B58:511 B59:59 B60:532 C01:547 C02:510T C02:581T C03:601E C04:606E C05:606E C06:583E C07:540E C08:539E C09:498 C09:516 C10:547 C11:583E C12:540E C13:582E C14:590E C14:960E C15:510T C15:581T C16:584E C17:584E C18:538E C19:299 C19:580 C19:67 C20:502T C20:587T D01:505 D02:505 D03:505 D04:505 D05:505 D06:505 D07:505 D08:505 D09:505 D10:505 D11:505 D12:505 D13:505 D14:505 D15:505 D16:505 D17:505 D18:505 D19:505 D20:505 D21:505 D22:505 D23:505 D24:505 D25:505 D26:505 D27:505 D28:505 D29:505 D30:505 D31:505 D32:505 D33:515 D34:515 D36:534 D37:654 D38:542 D39:543 D40:555 D41:519 D42:519 D43:551 D44:551 D45:544 D46:544 D47:544 D48:544 D49:544 D50:544 D51:544 D52:544 D53:544 D54:544 D55:544 D56:544 D57:544 D58:544 D59:544 D60:544 E01:222 E02:225 E03:225 E04:225 E05:225 E06:222 E07:221 E08:221 E09:221 E10:312 E11:220 E12:220 E13:223 E14:223 E15:312 E15:337 E16:224 E17:224 E18:550 E19:550 E20:311 F01:26 F02:26 F03:26 F04:26 F05:27 F06:27 F07:27 F08:27 F09:437E F10:437E F11:437E F12:437E F13:438E F14:438E F15:438E F16:438E F17:513 F18:513 F19:513 F20:513 F21:513 F22:513 F23:513 F24:513 F25:513 F26:513 F27:513 F28:513 F29:513 F30:513 F31:513 F32:513 F33:513 F34:513 F35:513 F36:513 F37:513 F38:513 F39:513 F40:513 F41:513 F42:513 F43:513 F44:513 F45:546 F46:546 F47:546 F48:546 F49:574E F50:574 F51:546 F52:546 F53:559 F54:559 F55:559 F56:546 F57:325 F58:325 F59:325 F60:325 G01:229 G02:229 G03:326 G03:499 G03:58 G04:207 G05:509 G06:208 G07:355 G08:355 G10:255 G11:823 G12:823 G13:509 G14:823 G15:256 G16:594 G17:595 G18:596 G19:570 G20:256 H01:811E H02:811E H03:525E H04:525E H05:529E H06:529E H07:529E H08:819E H09:503E H10:816E H11:585E H12:585E H13:589E H14:816E H15:817E H16:260E H17:541E H18:812E H19:562 H20:562 H21:564 H22:564 H23:587 H24:587 H25:587 H26:587 H27:587 H28:587 H29:581 H30:581 H31:581 H32:581 H33:439E H34:439E H35:440E H36:440E H37:512 H38:512 H39:512 H40:512 H41:535 H42:535 H43:535 H44:535 H45:31 H46:31 H47:31 H48:31 H49:31 H50:31 H51:31 H52:31 H53:34 H54:34 H55:35E H56:35E H57:985E H58:988E H60:592E I01:932E I02:933E I03:934E I04:935E I05:936E I06:937E I07:942E I08:943E I09:944E I10:945E I11:948E I12:952E I13:953E I14:955E I15:931E I16:951E I17:954E I18:956E I19:957E I20:958E J01:328E J02:360E J03:361E J04:363E J05:366E J06:367E J07:810E J08:870E J09:315 J10:315 J11:315 J12:315 J13:809E J14:809E J15:598E J16:598E J17:234 J18:234 J19:323E J20:323E J21:404E J22:404E J23:70 J24:70 J25:597 J26:591 J27:591 J28:441 J29:507 J30:507 J31:507 J32:280 J33:557 J34:557 J35:557 J36:280 J37:558 J38:558 J39:558 J40:334 J41:333 J42:566E J43:590ES J44:599E J45:659 J46:658 J47:941E J48:946E J49:969E J50:522E J51:514E J52:970E J53:536E J54:56E J55:971E J56:980E J57:981E J58:982E J59:983E J60:984E L01:825 L02:825 L03:824 L04:824 L05:438E L06:438E L07:437E L08:437E L09:99 L10:99 L11:99 L12:99 L13:706 L14:706 L15:706 L16:706 L17:713 L18:713 L19:713 L20:713 L21:97 L22:97 L23:97 L24:97 L25:922 L26:922 L27:922 L28:922 L29:847 L30:847 L31:847 L32:609 L33:727E L34:735 L35:802 L36:802 L37:730 L38:731 L39:723 L40:725E L41:911 L42:920 L43:902 L44:909 L45:725E L46:729E L47:908 L48:900 L49:53 L50:54 L51:55 L52:456 L53:707 L53:708 L54:732 L54:977 L55:52 L56:720 L56:722 L57:865E L58:690E L59:453 L60:307 M01:701 M02:701 M03:701 M04:701 M04:818 M05:901 M06:901 M07:901 M08:901 M09:702E M10:702E M11:836 M12:836 M13:809E M14:809E M15:809E M16:809 M17:910 M18:910 M19:43 M20:43 M21:839 M22:816 M23:817 M24:817 M25:712E M26:762 M26:769 M27:747 M27:763 M28:764 M29:760 M29:761 M30:717 M30:878 M31:718 M31:719 M32:755 M33:859 M33:862 M33:863 M34:630 M34:631 M34:632 M35:633 M35:634 M35:635 M36:613 M36:636 M36:637 M36:858 M37:789 M38:842 M38:843 M39:844 M39:845 M40:846 M41:618 M41:619 M41:700 M42:615 M42:856 M42:857 M43:818 M43:848 M44:619 M44:890E M45:800 M45:877E M46:801 M46:852 M47:715 M47:867 M48:709 M48:710 M49:840 M50:840 M51:840 M52:840 M53:840 M54:840 M55:840 M56:840 M57:840 M58:840 M59:840 M60:840 N03:546 N04:504 N05:546 N06:504 N08:504 N10:315 N12:504 P39:396 R25:540E R26:538E R27:102E V18:585E V19:536E V20:585E W01:523C W02:102E W03:56E W04:522S W05:870E W06:541E X01:702E X02:574E X03:712E X04:598E X05:368E X06:798E X07:574E X08:574E X10:328E X11:438E X12:816E X13:VASTIDOR X14:870E X15:106E X16:539E X17:583E X18:404E X19:102E X25:870E X26:725E X27:811E X28:870E X29:106E X30:368E Y01:702E Y02:725E Y04:1000900 Y05:598E Y06:598E Y07:810E Y08:102E Y09:503E Y10:503E Y11:811E Y12:368E Y13:361E Y14:529E Y15:819E Y16:522E Y17:367E Y18:598E Y19:529E Y20:529E Y21:106E Y22:589E Y23:260E Y24:607E Y26:582E Y27:503E Y28:712E Y29:35E Y30:582E Z05:437E Z06:582E Z07:363E Z09:812E Z11:589E Ñ01:103 Ñ02:103 Ñ03:104 Ñ04:104 Ñ05:102E Ñ06:102E Ñ07:102E Ñ08:102E Ñ09:106E Ñ10:106E Ñ11:106E Ñ12:106E Ñ13:108 Ñ14:109 Ñ15:111 Ñ16:111 Ñ17:112 Ñ18:112 Ñ19:113 Ñ20:113 Ñ21:110 Ñ22:110 Ñ23:115 Ñ24:115 Ñ25:121 Ñ26:119 Ñ27:116 Ñ28:114 Ñ29:121 Ñ30:124E Ñ31:124E Ñ32:101 Ñ33:123 Ñ34:123 Ñ35:123 Ñ36:123 Ñ37:186 Ñ38:186 Ñ39:123 Ñ40:123 Ñ41:186 Ñ42:186 Ñ43:193 Ñ44:193 Ñ45:198E Ñ46:198E Ñ49:120 Ñ50:120 Ñ53:439E Ñ54:439E Ñ55:838E Ñ56:758 Ñ57:798E Ñ58:759 Ñ59:759',' ')) x;

-- ════════════════════════════════════════════════════════════════════
-- AJUSTES del 2026-09-11 (después de la primera carga), pedidos por Luis
--
-- 1) SE REPONEN todos los lugares: la primera carga había sacado 52 que
--    sólo tenían insumos. El catálogo de lugares es el catálogo físico y
--    va completo, tenga lo que tenga adentro. Quedan 872.
--
-- 2) LA INFO DE INSUMOS NO SE TIRA: se estaciona en GV_Lugar_Pendiente
--    ("después las combinamos y vemos de limpiar eso bien"). Son 148 filas:
--      71 motivo='insumo'        — insumo relevado en ese lugar
--      71 motivo='sin_resolver'  — las tablas viejas se contradicen y nadie
--                                  decidió; casi todas son la misma cosa
--                                  escrita distinto (N°63 vs 63, DISC.1 vs DISC1)
--       6 motivo='no_es_articulo'— 809E-PIZZA, 809E-QUESO, 522S, 523C, 592E
--
-- 3) USO OPERATIVO: PEDIDOS / CAJAS / VASTIDOR no eran artículos guardados
--    ahí, son lugares con una función. Pasan a GV_Lugar.uso y salen de
--    GV_Lugar_Item. Son 10 lugares: 8 de pedidos (AB01 AB02 AB07 AB08
--    AC01 AC02 AC07 AC08), 1 de cajas (AD08) y 1 de bastidor (X13).
--
-- 4) 809E-PIZZA / 809E-QUESO salen: son un sufijo manual sobre un dual y
--    el lugar ya dice la empresa (AE11 es LK, AD05 es CH). Luis: "seguramente
--    es un insumo o un código que se usaba para insumo".
--
-- Estado final: 872 lugares (688 góndola + 184 rack, 10 con uso operativo),
-- 781 asignaciones de artículo, 148 filas estacionadas.
-- ════════════════════════════════════════════════════════════════════

insert into public."GV_Lugar"(sector,tipo,empresa)
select unnest(string_to_array('AC06 AD04 AF01 AF03 AF05 AF10 AF11 AF13 AF14 AF20 K04 K05 K06 N07 O01 Q34 R01AD R01AT R02AT R04AT R06AD R06AT R07AT R08AD R08AT R09AD R09AT R11AD R11AT R12AD R13AD R13AT R14AD R14AT R15 V01AT V02AD V09AD V09AT V10AD V10AT V11AD V12AD V14AD X09 X20 X21 X22 X23 X24 Z02',' ')),'rack',null
union all
select unnest(string_to_array('Z10',' ')),'rack','LK'
on conflict (sector) do nothing;

update public."GV_Lugar" set uso='pedidos',  updated_at=now() where sector in ('AB01','AB02','AB07','AB08','AC01','AC02','AC07','AC08');
update public."GV_Lugar" set uso='cajas',    updated_at=now() where sector = 'AD08';
update public."GV_Lugar" set uso='bastidor', updated_at=now() where sector = 'X13';

insert into public."GV_Lugar_Pendiente"(sector,cod,motivo,nota)
select i.sector, i.cod, 'no_es_articulo',
  case when i.cod like '809E-%' then 'sufijo manual sobre un dual; el lugar ya dice la empresa'
       else 'no existe en Volumen_Articulos ni en precios_venta' end
from public."GV_Lugar_Item" i
where i.cod in ('809E-PIZZA','809E-QUESO','522S','523C','592E')
on conflict (sector,cod) do nothing;

delete from public."GV_Lugar_Item"
where cod in ('809E-PIZZA','809E-QUESO','522S','523C','592E','PEDIDOS','CAJAS','VASTIDOR');

-- (las 143 filas de insumo / sin_resolver se insertaron en GV_Lugar_Pendiente
--  desde el relevamiento; ver el chat de la sesión para el detalle)

-- ── Decisiones de Luis, 2026-09-11 (cierre de la carga) ──────────────
-- Ñ53: es de LOKE y está LIBRE. El 439E que traían las tablas viejas no
--      está fisicamente ahi. (Ñ54, al lado, sí tiene 439E y es LOKE.)
-- AD06 / X05 / Y01: racks con artículo real que ninguna tabla vieja tenía
--      asignados a una empresa. Se les pone LK.
-- A62: confirmado que son DOS códigos, 355 y 066 (cargados 355 y 66, sin
--      el cero de adelante). Excel los habia colapsado en el decimal 355,066.

update public."GV_Lugar" set empresa='LOKE',
  notas=coalesce(notas||' · ','')||'Luis 11/09: LOKE y libre; el 439E que decian las tablas viejas no esta',
  updated_at=now() where sector='Ñ53';
delete from public."GV_Lugar_Item" where sector='Ñ53';

update public."GV_Lugar" set empresa='LK',
  notas=coalesce(notas||' · ','')||'empresa asignada por Luis 11/09 (las tablas viejas no la traian)',
  updated_at=now() where sector in ('AD06','X05','Y01');

-- Estado final: 872 lugares · 780 asignaciones de articulo · 148 filas
-- estacionadas · 51 lugares sin empresa (TODOS racks de insumos, ninguno
-- con articulo) · 76 lugares realmente libres.

-- ── Más decisiones de Luis, 2026-09-11 ───────────────────────────────
-- 865ED va en L57, el MISMO lugar que el 865E (L57 es góndola de CH).
insert into public."GV_Lugar_Item"(sector,cod,clase,notas)
values ('L57','865ED','articulo','Luis 11/09: va en el mismo lugar que el 865E')
on conflict (sector,cod,clase) do nothing;

-- 759 (Bomb. Pico de Loro) es de CHEF: Ñ58 y Ñ59 pasan de LK a CH. Quedan
-- coherentes con Ñ56 y Ñ57, que ya eran CH: el final del pasillo Ñ es Chef.
update public."GV_Lugar" set empresa='CH',
  notas=coalesce(notas||' · ','')||'Luis 11/09: el 759 es de Chef, el lugar va CH (venia del pasillo Ñ que era LOKE)',
  updated_at=now() where sector in ('Ñ58','Ñ59');

-- ── OC_Maximos y Equivalencias_Codigos (tablas de PRODUCCIÓN) ────────
-- Backup previo en sql/backups/backup_oc_maximos_equiv_20260911.sql
--
-- 580 (Batidor Mini) tenía linea = '' (vacía) → LK.
update public."OC_Maximos" set linea='LK' where cod='580';

-- Las notas de 438EL/439EL decían lo contrario de lo que hace el mapeo.
-- La regla (ya estaba en el CLAUDE.md y en index.html v12.37): un código
-- terminado en L es un pedido de CHEF cuyo producto se levanta de la
-- góndola de LOEKEMEYER. No es otro producto: dice de qué góndola sale.
-- El mapeo 438EL -> 438E LK estaba BIEN; el texto de la nota estaba al revés.
update public."Equivalencias_Codigos"
set nota='438EL = pedido de CHEF que se pickea de la gondola de LOEKEMEYER (438E LK). La L no es otro producto: dice de que gondola se levanta. Nota corregida 11/09 por Luis; antes decia "= 438E CH", que era al reves.'
where cod_pedido='438EL';
update public."Equivalencias_Codigos"
set nota='439EL = pedido de CHEF que se pickea de la gondola de LOEKEMEYER (439E LK). La L no es otro producto: dice de que gondola se levanta. Nota corregida 11/09 por Luis; antes decia "= 439E CH", que era al reves.'
where cod_pedido='439EL';
