#!/usr/bin/env python3
"""
Genera los iconos de la app GP2 a partir de GP2_logo.png (1000x322, alta resolucion).

Por que existe este script y no unos PNG sueltos:
  - Los iconos ANTERIORES eran el favicon de 180px estirado a 512 => borrosos en el
    telefono. Aca se recortan del logo original, que tiene resolucion de sobra.
  - Si manana cambia el logo, se corre esto y salen todos los tamanos consistentes.

Uso:  python3 tools/generar_iconos.py       (desde la raiz del repo)

Que genera:
  icons/icon-192.png          PWA, purpose "any"
  icons/icon-512.png          PWA, purpose "any"
  icons/icon-maskable-512.png PWA, purpose "maskable" (Android le recorta un circulo:
                              el contenido tiene que entrar en el 80% central)
  apple-touch-icon.png        iOS 180x180. CUADRADO y SIN transparencia: iOS aplica su
                              propia mascara redondeada, si el PNG ya viene con esquinas
                              redondeadas quedan esquinas dentro de esquinas.
"""
import math

from PIL import Image, ImageFilter

LOGO = "GP2_logo.png"
# Recorte del "GP2" dentro del logo: las letras metalicas + el destornillador rojo
# adentro de la G + la barra plateada y las rayitas. Sin "GESTION PRODUCTIVA", que a
# 192px no se lee y solo ensucia.
CROP = (285, 45, 955, 250)

# Cuanto del ancho ocupa la marca en cada variante.
ANCHO_ANY      = 0.88   # el resto es aire para que la mascara del SO no coma las puntas
ANCHO_MASKABLE = 0.66   # zona segura de maskable: circulo del 80% => la marca va mas chica


def marca():
    """El GP2 recortado del logo, en resolucion nativa."""
    return Image.open(LOGO).convert("RGB").crop(CROP)


# Colores de marca: azul medio detras de la marca, navy en las esquinas.
AZUL_CENTRO = (26, 63, 104)
AZUL_BORDE = (2, 16, 38)


def lienzo(lado):
    """
    Fondo cuadrado sintetico: degradado radial con los azules de la marca.
    No se usa el favicon como fondo porque el favicon YA trae el GP2 dibujado:
    pegarle la marca encima daba el GP2 duplicado (probado, se veia el fantasma).
    """
    f = Image.new("RGB", (lado, lado))
    px = f.load()
    c = lado / 2
    for y in range(lado):
        for x in range(lado):
            t = min(1.0, math.hypot(x - c, y - c) / (c * 1.42)) ** 1.25
            px[x, y] = tuple(int(a * (1 - t) + b * t)
                             for a, b in zip(AZUL_CENTRO, AZUL_BORDE))
    return f


def mascara(m):
    """
    Alpha de las letras, sacada de la luminancia: el fondo del logo es azul oscuro
    y las letras son claras. Asi la marca queda RECORTADA y flota sobre el
    degradado, sin el rectangulo del recorte (con un simple desvanecido de bordes
    el rectangulo se seguia viendo).
    """
    a = m.convert("L").point(
        lambda v: 0 if v < 55 else (255 if v > 95 else int((v - 55) * 255 / 40)))
    return a.filter(ImageFilter.GaussianBlur(0.8))


def armar(lado, ancho_rel):
    m = marca()
    fondo = lienzo(lado)
    ancho = int(lado * ancho_rel)
    alto = max(1, round(m.height * ancho / m.width))
    pos = ((lado - ancho) // 2, (lado - alto) // 2)
    fondo.paste(m.resize((ancho, alto), Image.LANCZOS), pos,
                mascara(m).resize((ancho, alto), Image.LANCZOS))
    return fondo


def main():
    salidas = [
        ("icons/icon-192.png", 192, ANCHO_ANY),
        ("icons/icon-512.png", 512, ANCHO_ANY),
        ("icons/icon-maskable-512.png", 512, ANCHO_MASKABLE),
        ("apple-touch-icon.png", 180, ANCHO_ANY),
    ]
    for ruta, lado, ancho in salidas:
        armar(lado, ancho).save(ruta, "PNG", optimize=True)
        print(f"{ruta}  {lado}x{lado}  marca al {int(ancho*100)}% del ancho")


if __name__ == "__main__":
    main()
