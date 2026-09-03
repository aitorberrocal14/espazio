"""Infraestructura de la suite.

Los tests corren contra un PostgreSQL real. No hay dobles ni simulaciones: lo que se está
comprobando es que la separación de privilegios y el umbral los hace cumplir el motor, y
eso no se puede verificar contra un mock.

    esquema/bd_local.sh arrancar
    PGHOST=/var/run/postgresql PGPORT=5433 PGUSER=postgres python -m pytest tests -v
"""
from __future__ import annotations

import os
import subprocess
import uuid
from contextlib import contextmanager
from pathlib import Path

import psycopg
import pytest

RAIZ = Path(__file__).resolve().parent.parent


@pytest.fixture(scope="session")
def base_de_datos() -> str:
    """Crea una base efímera y le aplica las migraciones en orden.

    Con ESPAZIO_BASE apuntando a una base ya preparada se usa esa y no se toca nada más:
    hace falta para correr la suite contra un esquema deliberadamente alterado y
    comprobar que los tests lo detectan.
    """
    fija = os.environ.get("ESPAZIO_BASE")
    if fija:
        yield fija
        return
    nombre = f"espazio_test_{uuid.uuid4().hex[:8]}"
    with psycopg.connect(dbname="postgres", autocommit=True) as cn:
        cn.execute(f'create database "{nombre}"')
    try:
        subprocess.run([str(RAIZ / "esquema" / "aplicar.sh"), nombre],
                       check=True, capture_output=True, text=True)
        yield nombre
    finally:
        with psycopg.connect(dbname="postgres", autocommit=True) as cn:
            cn.execute(f'drop database if exists "{nombre}" with (force)')


@pytest.fixture
def conn(base_de_datos):
    """Conexión por test, revertida al terminar: ningún test hereda datos de otro."""
    with psycopg.connect(dbname=base_de_datos) as cn:
        yield cn
        cn.rollback()


@contextmanager
def como(cn, rol: str):
    """Ejecuta como `rol`. Los roles son NOLOGIN: se entra por SET ROLE, y desde ahí las
    comprobaciones de privilegio se aplican de verdad aunque la conexión sea de superusuario."""
    cn.execute(f"set role {rol}")
    try:
        yield
    finally:
        cn.execute("reset role")


@contextmanager
def punto_de_guardado(cn):
    """Aísla una sentencia que se espera que falle, para no abortar la transacción."""
    nombre = f"sp_{uuid.uuid4().hex[:8]}"
    cn.execute(f"savepoint {nombre}")
    try:
        yield
    finally:
        cn.execute(f"rollback to savepoint {nombre}")
