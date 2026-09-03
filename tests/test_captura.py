"""Comportamiento de la zona de captura que no es de privilegios.

Z7: el instante tiene que caer en una franja del instrumento, y eso se comprueba al
anotar. Antes se comprobaba al consolidar, y entonces una sola fila fuera de rejilla
tumbaba el lote entero —el trabajo de varias sesiones— y lo tumbaba justo para quien
entra antes de las siete, que es a quien la rejilla deja fuera (PROYECTO.md §5.5 y §8).
"""
from __future__ import annotations

import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import psycopg
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from datos_sinteticos import generador as gen
from tests.conftest import como, punto_de_guardado

TZ = ZoneInfo("Europe/Madrid")


@pytest.fixture
def captura_lista(conn):
    version = gen.sembrar_instrumento(conn)
    venue = gen.sembrar_venue(conn, zonas=["z0"], grupos_rol=["limpieza"])
    campana = gen.sembrar_campana(conn, venue, version)
    with como(conn, "espazio_captura"):
        sesion, secreto = conn.execute(
            "select sesion_id, secreto from captura.abrir_sesion(%s,%s,'limpieza',"
            "'in_situ','es')", (campana, venue.id)).fetchone()
    return venue, sesion, secreto


def _anotar_a_las(conn, venue, sesion, secreto, hora):
    momento = datetime(2026, 3, 2, hora, 30, tzinfo=TZ)   # lunes
    return conn.execute(
        "select captura.anotar(%s,%s,%s,null,'agradable',2::smallint,'espontanea',"
        "%s,%s,%s,null,%s)",
        (sesion, secreto, venue.recintos["z0"][0], ["luz"],
         [c for c, *_ in gen.VOCABULARIO], [c for c, *_ in gen.ATRIBUCIONES],
         momento)).fetchone()[0]


def test_z7_el_momento_fuera_de_rejilla_falla_al_anotar(conn, captura_lista):
    venue, sesion, secreto = captura_lista
    with como(conn, "espazio_captura"), punto_de_guardado(conn):
        # Las seis de la mañana: el turno de limpieza, fuera de la rejilla 07:00–23:00.
        with pytest.raises(psycopg.errors.CheckViolation) as err:
            _anotar_a_las(conn, venue, sesion, secreto, 6)
        assert "franja" in str(err.value)


def test_z7_el_fallo_no_llega_a_la_consolidacion(conn, captura_lista):
    """Lo que importa no es que falle, sino DÓNDE. Si la anotación entra al borrador, la
    consolidación revienta después y se lleva por delante las sesiones de los demás."""
    venue, sesion, secreto = captura_lista
    with como(conn, "espazio_captura"), punto_de_guardado(conn):
        with pytest.raises(psycopg.errors.CheckViolation):
            _anotar_a_las(conn, venue, sesion, secreto, 6)
    assert conn.execute("select count(*) from captura.anotacion_borrador"
                        " where sesion_id = %s", (sesion,)).fetchone()[0] == 0


def test_z7_dentro_de_rejilla_entra(conn, captura_lista):
    venue, sesion, secreto = captura_lista
    with como(conn, "espazio_captura"):
        assert _anotar_a_las(conn, venue, sesion, secreto, 9) is not None
