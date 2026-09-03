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
    """P2 — el formulario escribe en captura y no puede leer nada, ni siquiera lo suyo."""
    version = gen.sembrar_instrumento(conn)
    venue = gen.sembrar_venue(conn, zonas=["z0"], grupos_rol=["pdi"])
    campana = gen.sembrar_campana(conn, venue, version)

    with como(conn, "espazio_captura"):
        # La vía real: la API de escritura devuelve el id de lo que acaba de crear.
        sesion_id = conn.execute(
            "select captura.abrir_sesion(%s,%s,'pdi','in_situ','es')",
            (campana, venue.id)).fetchone()[0]
        assert sesion_id is not None
        borrador_id = conn.execute(
            "select captura.anotar(%s,%s,null,'agradable',2::smallint,'espontanea',%s,%s)",
            (sesion_id, venue.recintos["z0"][0],
             [c for c, *_ in gen.VOCABULARIO], [c for c, *_ in gen.ATRIBUCIONES])).fetchone()[0]
        assert borrador_id is not None

        # Y el INSERT directo sigue entrando (el criterio, en su letra).
        conn.execute(
            "insert into captura.anotacion_borrador (sesion_id, recinto_id, etiqueta,"
            " intensidad, elicitacion, permutacion_etiquetas, permutacion_atribuciones)"
            " values (%s,%s,'tranquilo',1,'cierre_positivo',%s,%s)",
            (sesion_id, venue.recintos["z0"][0],
             [c for c, *_ in gen.VOCABULARIO], [c for c, *_ in gen.ATRIBUCIONES]))

        with punto_de_guardado(conn):
            with pytest.raises(psycopg.errors.InsufficientPrivilege) as err:
                conn.execute("select * from anotacion.anotacion limit 1")
            assert err.value.sqlstate == "42501"

    assert conn.execute("select count(*) from captura.anotacion_borrador"
                        " where sesion_id = %s", (sesion_id,)).fetchone()[0] == 2


@pytest.mark.parametrize("consulta", [
    "select * from captura.anotacion_borrador",
    "select id from captura.anotacion_borrador",     # enumerar es el canal lateral
    "select count(*) from captura.anotacion_borrador",
    "select id from captura.sesion",
])
def test_p2_captura_no_puede_enumerar_borradores(conn, consulta):
    """Enumerar borradores revela la cadencia de recogida —cuántas personas anotan y
    cuándo— sin leer una sola anotación. Por eso la zona de captura no concede SELECT,
    ni de tabla ni de columna, y el id sale del propio INSERT dentro de la API."""
    with como(conn, "espazio_captura"), punto_de_guardado(conn):
        with pytest.raises(psycopg.errors.InsufficientPrivilege) as err:
            conn.execute(consulta)
        assert err.value.sqlstate == "42501"


def test_p2_captura_no_tiene_select_ni_de_tabla_ni_de_columna(conn):
    """La comprobación estructural, por si alguien reintroduce el grant que 0012 quitó."""
    de_tabla = conn.execute(
        "select table_name from information_schema.table_privileges"
        " where grantee='espazio_captura' and privilege_type='SELECT'"
        "   and table_schema='captura'").fetchall()
    de_columna = conn.execute(
        "select table_name, column_name from information_schema.column_privileges"
        " where grantee='espazio_captura' and privilege_type='SELECT'"
        "   and table_schema='captura'").fetchall()
    assert de_tabla == [], f"SELECT de tabla sobre captura: {de_tabla}"
    assert de_columna == [], f"SELECT de columna sobre captura: {de_columna}"


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
