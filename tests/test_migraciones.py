"""Reversibilidad: aplicar, revertir, reaplicar deja exactamente el mismo esquema.

`CLAUDE.md` pide migraciones reversibles. Hasta ahora eso estaba afirmado y no
demostrado, que es la peor forma de tener una propiedad: se descubre que no la tienes el
día que la necesitas.

La comparación es sobre el catálogo, no sobre un `pg_dump` en texto: columnas y tipos,
restricciones con su definición, índices, vistas, funciones, disparadores y privilegios.
Si una reversión deja algo a medias o una reaplicación produce algo distinto, aquí sale.
"""
from __future__ import annotations

import subprocess
import uuid
from pathlib import Path

import psycopg
import pytest

RAIZ = Path(__file__).resolve().parent.parent
ESQUEMAS = ("instrumento", "anotacion", "captura", "cualitativo",
            "analisis", "consolidacion", "nucleo")

CONSULTAS = {
    "columnas": """
        select table_schema, table_name, column_name, data_type,
               is_nullable, coalesce(column_default,'')
        from information_schema.columns
        where table_schema = any(%(esq)s) order by 1,2,3""",
    "restricciones": """
        select n.nspname, t.relname, c.conname, c.contype::text,
               pg_get_constraintdef(c.oid)
        from pg_constraint c
        join pg_class t on t.oid = c.conrelid
        join pg_namespace n on n.oid = t.relnamespace
        where n.nspname = any(%(esq)s) order by 1,2,3""",
    "indices": """
        select schemaname, tablename, indexname, indexdef
        from pg_indexes where schemaname = any(%(esq)s) order by 1,2,3""",
    "vistas": """
        select schemaname, viewname, definition
        from pg_views where schemaname = any(%(esq)s) order by 1,2""",
    "funciones": """
        select n.nspname, p.proname, pg_get_function_identity_arguments(p.oid),
               p.prosecdef, pg_get_functiondef(p.oid)
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = any(%(esq)s) order by 1,2,3""",
    "disparadores": """
        select n.nspname, t.relname, g.tgname, pg_get_triggerdef(g.oid)
        from pg_trigger g
        join pg_class t on t.oid = g.tgrelid
        join pg_namespace n on n.oid = t.relnamespace
        where n.nspname = any(%(esq)s) and not g.tgisinternal order by 1,2,3""",
    "privilegios_tabla": """
        select table_schema, table_name, grantee, privilege_type
        from information_schema.table_privileges
        where table_schema = any(%(esq)s) order by 1,2,3,4""",
    "privilegios_columna": """
        select table_schema, table_name, column_name, grantee, privilege_type
        from information_schema.column_privileges
        where table_schema = any(%(esq)s) order by 1,2,3,4,5""",
    "privilegios_rutina": """
        select routine_schema, routine_name, grantee, privilege_type
        from information_schema.routine_privileges
        where routine_schema = any(%(esq)s) order by 1,2,3,4""",
}


def _huella(base: str) -> dict[str, list]:
    with psycopg.connect(dbname=base) as cn:
        return {nombre: cn.execute(sql, {"esq": list(ESQUEMAS)}).fetchall()
                for nombre, sql in CONSULTAS.items()}


def _correr(base: str, *args):
    subprocess.run([str(RAIZ / "esquema" / "aplicar.sh"), base, *args],
                   check=True, capture_output=True, text=True)


DIR = RAIZ / "esquema" / "migraciones"
MIGRACIONES = sorted(f for f in DIR.glob("*.sql") if not f.name.endswith(".revertir.sql"))


def _psql(base: str, archivo: Path):
    subprocess.run(["psql", "--dbname", base, "--set", "ON_ERROR_STOP=1", "--quiet",
                    "--file", str(archivo)], check=True, capture_output=True, text=True)


@pytest.fixture
def base_vacia():
    nombre = f"espazio_rev_{uuid.uuid4().hex[:8]}"
    with psycopg.connect(dbname="postgres", autocommit=True) as cn:
        cn.execute(f'create database "{nombre}"')
    try:
        yield nombre
    finally:
        with psycopg.connect(dbname="postgres", autocommit=True) as cn:
            cn.execute(f'drop database if exists "{nombre}" with (force)')


def test_revertir_deja_la_base_limpia(base_vacia):
    _correr(base_vacia)
    _correr(base_vacia, "revertir")
    with psycopg.connect(dbname=base_vacia) as cn:
        restos = cn.execute(
            "select nspname from pg_namespace where nspname = any(%s)",
            (list(ESQUEMAS),)).fetchall()
    assert restos == [], f"la reversión dejó esquemas por medio: {restos}"


def test_aplicar_revertir_reaplicar_reproduce_el_mismo_esquema(base_vacia):
    _correr(base_vacia)
    antes = _huella(base_vacia)
    _correr(base_vacia, "revertir")
    _correr(base_vacia)
    despues = _huella(base_vacia)

    # Sección por sección, para que el fallo diga qué cambió y no solo que algo cambió.
    for seccion in CONSULTAS:
        faltan = [f for f in antes[seccion] if f not in despues[seccion]]
        sobran = [f for f in despues[seccion] if f not in antes[seccion]]
        assert not faltan and not sobran, (
            f"la reaplicación cambió «{seccion}»\n"
            f"  desaparecieron: {faltan[:5]}\n"
            f"  aparecieron:    {sobran[:5]}")

    assert antes["columnas"], "la huella está vacía: el test no comprueba nada"


@pytest.mark.parametrize("i", range(len(MIGRACIONES)), ids=[f.stem for f in MIGRACIONES])
def test_cada_migracion_revierte_a_su_estado_anterior(base_vacia, i):
    """La propiedad que de verdad significa «reversible».

    Comparar solo el estado final de aplicar-revertir-reaplicar no basta: si la reversión
    de la migración N se olvida de deshacer algo, la reaplicación de N lo vuelve a hacer y
    el estado final coincide igualmente. Se descubrió con una mutación sobre el fichero de
    reversión de 0014, que el test anterior dejaba pasar. Aquí se comprueba migración a
    migración: aplicar hasta N-1, aplicar N, revertir N, y volver exactamente a N-1.

    Salvedad conocida: los roles son objetos de clúster y `0002` no los borra a propósito,
    porque pueden estar en uso por otra base. La huella es por esquema, así que ese caso
    no lo cubre este test y está documentado en la propia migración.
    """
    for anterior in MIGRACIONES[:i]:
        _psql(base_vacia, anterior)
    antes = _huella(base_vacia)

    actual = MIGRACIONES[i]
    _psql(base_vacia, actual)
    _psql(base_vacia, DIR / f"{actual.stem}.revertir.sql")
    despues = _huella(base_vacia)

    for seccion in CONSULTAS:
        faltan = [f for f in antes[seccion] if f not in despues[seccion]]
        sobran = [f for f in despues[seccion] if f not in antes[seccion]]
        assert not faltan and not sobran, (
            f"revertir {actual.name} no devuelve el estado anterior; cambió «{seccion}»\n"
            f"  se perdieron: {faltan[:5]}\n"
            f"  quedaron:     {sobran[:5]}")
