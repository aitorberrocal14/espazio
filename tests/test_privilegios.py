"""P1–P5: la separación de privilegios (decisión §2.1 y §2.2).

Es donde k=5 deja de ser una norma de uso. Si estos fallan, todo lo demás da igual: el
umbral se salta abriendo una consulta.
"""
from __future__ import annotations

import random
import sys
import uuid
from pathlib import Path

import psycopg
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from datos_sinteticos import generador as gen
from tests.conftest import como, punto_de_guardado

RESTRINGIDAS = [
    "anotacion.anotacion",
    "anotacion.celda_recuento",
    "captura.sesion",
    "cualitativo.nota",
]


@pytest.mark.parametrize("tabla", RESTRINGIDAS)
def test_p1_analisis_no_alcanza_la_fila(conn, tabla):
    """P1 — espazio_analisis no tiene privilegio alguno sobre el dato de origen."""
    with como(conn, "espazio_analisis"), punto_de_guardado(conn):
        with pytest.raises(psycopg.errors.InsufficientPrivilege) as err:
            conn.execute(f"select * from {tabla} limit 1")
        assert err.value.sqlstate == "42501"


def test_p2_captura_escribe_y_no_lee(conn):
    """P2 — el formulario inserta en captura y no puede leer el dato consolidado."""
    version = gen.sembrar_instrumento(conn)
    venue = gen.sembrar_venue(conn, zonas=["z0"], grupos_rol=["pdi"])
    campana = gen.sembrar_campana(conn, venue, version)

    sesion_id = uuid.uuid4()
    with como(conn, "espazio_captura"):
        # El id lo genera el cliente: espazio_captura no tiene SELECT sobre el contenido.
        conn.execute(
            "insert into captura.sesion (id, campana_id, venue_id, grupo_rol, modo, lengua)"
            " values (%s,%s,%s,'pdi','in_situ','es')", (sesion_id, campana, venue.id))
        conn.execute(
            "insert into captura.anotacion_borrador (sesion_id, recinto_id, etiqueta,"
            " intensidad, elicitacion, permutacion_etiquetas, permutacion_atribuciones)"
            " values (%s,%s,'agradable',2,'espontanea',%s,%s)",
            (sesion_id, venue.recintos["z0"][0],
             [c for c, *_ in gen.VOCABULARIO], [c for c, *_ in gen.ATRIBUCIONES]))

        # No puede leer el dato consolidado…
        with punto_de_guardado(conn):
            with pytest.raises(psycopg.errors.InsufficientPrivilege) as err:
                conn.execute("select * from anotacion.anotacion limit 1")
            assert err.value.sqlstate == "42501"

        # …ni el contenido de lo que él mismo acaba de escribir.
        with punto_de_guardado(conn):
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                conn.execute("select etiqueta from captura.anotacion_borrador limit 1")

    # Y sin embargo la inserción entró de verdad.
    assert conn.execute("select count(*) from captura.anotacion_borrador"
                        " where sesion_id = %s", (sesion_id,)).fetchone()[0] == 1


def test_p3_analisis_lee_todas_las_vistas_publicadas(conn):
    """P3 — y lo que sí puede hacer, lo puede hacer: leer la superficie publicada."""
    vistas = [r[0] for r in conn.execute(
        "select table_name from information_schema.views"
        " where table_schema = 'analisis' order by table_name").fetchall()]
    assert vistas, "no hay ninguna vista en analisis: la superficie publicada está vacía"
    with como(conn, "espazio_analisis"):
        for v in vistas:
            conn.execute(f"select * from analisis.{v} limit 1").fetchall()


def test_p4_ninguna_vista_publicada_depende_de_las_notas(conn):
    """P4 — k=5 no protege la nota libre, así que la nota libre no sale por analisis."""
    dependencias = conn.execute("""
        select distinct v.relname
        from pg_depend d
        join pg_rewrite r  on r.oid = d.objid
        join pg_class   v  on v.oid = r.ev_class
        join pg_class   t  on t.oid = d.refobjid
        join pg_namespace nv on nv.oid = v.relnamespace
        join pg_namespace nt on nt.oid = t.relnamespace
        where nv.nspname = 'analisis' and nt.nspname = 'cualitativo'
    """).fetchall()
    assert dependencias == [], f"vistas de analisis que tocan cualitativo: {dependencias}"


def test_p5_ninguna_vista_publicada_expone_la_entidad_anclada(conn):
    """P5 — se ancla al recinto y se publica a la zona. El recinto no sale."""
    columnas = conn.execute("""
        select table_name, column_name
        from information_schema.columns
        where table_schema = 'analisis' and column_name in ('recinto_id','arista_id')
    """).fetchall()
    assert columnas == [], f"resolución espacial por debajo de zona: {columnas}"
