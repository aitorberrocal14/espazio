"""U1: el umbral se aplica y se aplica sobre PERSONAS (decisión §2.2, puntos 2 y 7).

La cuarta anotación no publica; la quinta sí, pero solo si viene de una quinta sesión.
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from datos_sinteticos import generador as gen
from tests.conftest import como


def _consolidar(conn, campana, cerrar=False):
    with como(conn, "espazio_consolidacion"):
        return conn.execute("select consolidacion.consolidar(%s, %s)",
                            (campana, cerrar)).fetchone()[0]


def _filas_publicadas(conn, zona_id):
    with como(conn, "espazio_analisis"):
        return conn.execute(
            "select grupo_rol, franja, n_anotaciones from analisis.perfil_zona_rol"
            " where zona_id = %s", (zona_id,)).fetchall()


def test_u1_la_celda_publica_en_la_quinta_sesion_y_no_antes(conn):
    rng = random.Random(20260903)
    version = gen.sembrar_instrumento(conn)
    venue = gen.sembrar_venue(conn, zonas=["z0", "z1"], grupos_rol=["pdi"])
    campana = gen.sembrar_campana(conn, venue, version)
    semana = gen.lunes_hace(2)

    # Cuatro sesiones en la celda que vigilamos, más dos de relleno en otra zona para
    # llegar al lote mínimo. El relleno comparte grupo (rol, semana, franja), así que no
    # crea grupos unitarios.
    for _ in range(4):
        gen.sembrar_sesion(conn, campana, venue, grupo_rol="pdi", zona="z0",
                           semana_iso=semana, franja="tarde", rng=rng)
    for _ in range(2):
        gen.sembrar_sesion(conn, campana, venue, grupo_rol="pdi", zona="z1",
                           semana_iso=semana, franja="tarde", rng=rng)
    assert _consolidar(conn, campana) is not None

    recuento = conn.execute(
        "select n_anotaciones, n_sesiones from anotacion.celda_recuento"
        " where zona_id = %s", (venue.zonas["z0"],)).fetchone()
    assert recuento == (4, 4), "el escenario no es el que cree el test"
    assert _filas_publicadas(conn, venue.zonas["z0"]) == [], \
        "con cuatro anotaciones de cuatro sesiones la celda no puede publicar"

    # La quinta, desde una quinta persona.
    gen.sembrar_sesion(conn, campana, venue, grupo_rol="pdi", zona="z0",
                       semana_iso=semana, franja="tarde", rng=rng)
    assert _consolidar(conn, campana, cerrar=True) is not None

    assert conn.execute("select n_anotaciones, n_sesiones from anotacion.celda_recuento"
                        " where zona_id = %s", (venue.zonas["z0"],)).fetchone() == (5, 5)
    assert _filas_publicadas(conn, venue.zonas["z0"]) == [("pdi", "tarde", 5)]


def test_u1_cinco_anotaciones_de_cuatro_personas_no_publican(conn):
    """El caso que el umbral contado sobre anotaciones dejaba pasar: cinco filas, cuatro
    respondentes. Una celda así es el perfil de cuatro personas presentado como grupo."""
    rng = random.Random(4)
    version = gen.sembrar_instrumento(conn)
    venue = gen.sembrar_venue(conn, zonas=["z0", "z1"], grupos_rol=["pdi"])
    campana = gen.sembrar_campana(conn, venue, version)
    semana = gen.lunes_hace(2)

    # Cuatro sesiones, cinco anotaciones: una de ellas anota dos veces.
    for i in range(4):
        gen.sembrar_sesion(conn, campana, venue, grupo_rol="pdi", zona="z0",
                           semana_iso=semana, franja="tarde",
                           n_anotaciones=2 if i == 0 else 1, rng=rng)
    for _ in range(2):
        gen.sembrar_sesion(conn, campana, venue, grupo_rol="pdi", zona="z1",
                           semana_iso=semana, franja="tarde", rng=rng)
    _consolidar(conn, campana, cerrar=True)

    assert conn.execute("select n_anotaciones, n_sesiones from anotacion.celda_recuento"
                        " where zona_id = %s", (venue.zonas["z0"],)).fetchone() == (5, 4)
    assert _filas_publicadas(conn, venue.zonas["z0"]) == [], \
        "cinco anotaciones de cuatro personas no son cinco personas"
