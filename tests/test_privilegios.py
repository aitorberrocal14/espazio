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


def _abrir(conn, campana, venue, rol="pdi"):
    return conn.execute("select sesion_id, secreto from captura.abrir_sesion(%s,%s,%s,"
                        "'in_situ','es')", (campana, venue.id, rol)).fetchone()


def _anotar(conn, sesion, secreto, recinto, elicitacion="espontanea"):
    return conn.execute(
        "select captura.anotar(%s,%s,%s,null,'agradable',2::smallint,%s,%s,%s,%s)",
        (sesion, secreto, recinto, elicitacion, ["ruido"],
         [c for c, *_ in gen.VOCABULARIO], [c for c, *_ in gen.ATRIBUCIONES])).fetchone()[0]


def test_p2_captura_escribe_solo_por_la_api(conn):
    """P2 — la zona de captura es accesible únicamente por la API de escritura.

    Cambió respecto a la primera redacción del criterio, que pedía INSERT directo: con
    INSERT directo el secreto de sesión es decorativo, porque se escribe saltándose la
    comprobación. O una cosa o la otra.
    """
    version = gen.sembrar_instrumento(conn)
    venue = gen.sembrar_venue(conn, zonas=["z0"], grupos_rol=["pdi"])
    campana = gen.sembrar_campana(conn, venue, version)

    with como(conn, "espazio_captura"):
        sesion, secreto = _abrir(conn, campana, venue)
        assert sesion is not None and secreto
        assert _anotar(conn, sesion, secreto, venue.recintos["z0"][0]) is not None

        with punto_de_guardado(conn):
            with pytest.raises(psycopg.errors.InsufficientPrivilege) as err:
                conn.execute(
                    "insert into captura.anotacion_borrador (sesion_id, recinto_id,"
                    " etiqueta, intensidad, elicitacion, permutacion_etiquetas,"
                    " permutacion_atribuciones) values (%s,%s,'tenso',1,'espontanea',%s,%s)",
                    (sesion, venue.recintos["z0"][0],
                     [c for c, *_ in gen.VOCABULARIO], [c for c, *_ in gen.ATRIBUCIONES]))
            assert err.value.sqlstate == "42501"

        with punto_de_guardado(conn):
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                conn.execute("select * from anotacion.anotacion limit 1")

    assert conn.execute("select count(*) from captura.anotacion_borrador"
                        " where sesion_id = %s", (sesion,)).fetchone()[0] == 1


@pytest.mark.parametrize("consulta", [
    "select * from captura.anotacion_borrador",
    "select id from captura.anotacion_borrador",     # enumerar es el canal lateral
    "select count(*) from captura.anotacion_borrador",
    "select id from captura.sesion",
])
def test_p2_captura_no_puede_enumerar_borradores(conn, consulta):
    """Enumerar borradores revela la cadencia de recogida —cuántas personas anotan y
    cuándo— sin leer una sola anotación."""
    with como(conn, "espazio_captura"), punto_de_guardado(conn):
        with pytest.raises(psycopg.errors.InsufficientPrivilege) as err:
            conn.execute(consulta)
        assert err.value.sqlstate == "42501"


def test_p2_captura_no_tiene_ningun_privilegio_de_tabla(conn):
    """Estructural: si alguien reintroduce cualquier grant sobre captura, aquí se ve."""
    privilegios = conn.execute(
        "select table_name, privilege_type from information_schema.table_privileges"
        " where grantee='espazio_captura' and table_schema='captura'").fetchall()
    columnas = conn.execute(
        "select table_name, column_name, privilege_type"
        " from information_schema.column_privileges"
        " where grantee='espazio_captura' and table_schema='captura'").fetchall()
    assert privilegios == [], f"privilegios de tabla sobre captura: {privilegios}"
    assert columnas == [], f"privilegios de columna sobre captura: {columnas}"


def test_p8_el_id_de_sesion_no_basta_para_escribir_en_ella(conn):
    """P8 — el id de sesión viaja por URL, historial y logs. No es una credencial."""
    version = gen.sembrar_instrumento(conn)
    venue = gen.sembrar_venue(conn, zonas=["z0"], grupos_rol=["pdi"])
    campana = gen.sembrar_campana(conn, venue, version)

    with como(conn, "espazio_captura"):
        sesion, secreto = _abrir(conn, campana, venue)
        with punto_de_guardado(conn):
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                _anotar(conn, sesion, str(uuid.uuid4()), venue.recintos["z0"][0])
        # Con el correcto, entra.
        assert _anotar(conn, sesion, secreto, venue.recintos["z0"][0]) is not None


def test_p9_no_se_anota_en_una_sesion_cerrada(conn):
    """P9 — cerrar la sesión cierra la escritura, aunque se tenga el secreto."""
    version = gen.sembrar_instrumento(conn)
    venue = gen.sembrar_venue(conn, zonas=["z0"], grupos_rol=["pdi"])
    campana = gen.sembrar_campana(conn, venue, version)

    with como(conn, "espazio_captura"):
        sesion, secreto = _abrir(conn, campana, venue)
        _anotar(conn, sesion, secreto, venue.recintos["z0"][0])
        conn.execute("select captura.cerrar_sesion(%s,%s)", (sesion, secreto))
        with punto_de_guardado(conn):
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                _anotar(conn, sesion, secreto, venue.recintos["z0"][0],
                        elicitacion="cierre_positivo")


def test_p9_el_rechazo_no_distingue_el_motivo(conn):
    """Un mensaje distinto por motivo convertiría la función en un oráculo sobre qué
    sesiones existen y cuáles siguen abiertas."""
    version = gen.sembrar_instrumento(conn)
    venue = gen.sembrar_venue(conn, zonas=["z0"], grupos_rol=["pdi"])
    campana = gen.sembrar_campana(conn, venue, version)
    with como(conn, "espazio_captura"):
        sesion, secreto = _abrir(conn, campana, venue)
        conn.execute("select captura.cerrar_sesion(%s,%s)", (sesion, secreto))
        mensajes = set()
        for ses, sec in [(sesion, str(uuid.uuid4())),      # secreto incorrecto
                         (sesion, secreto),                # sesión cerrada
                         (uuid.uuid4(), secreto)]:         # sesión inexistente
            with punto_de_guardado(conn):
                try:
                    _anotar(conn, ses, sec, venue.recintos["z0"][0])
                except psycopg.errors.InsufficientPrivilege as e:
                    mensajes.add(str(e).strip())
        assert len(mensajes) == 1, f"el rechazo distingue motivos: {mensajes}"


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
