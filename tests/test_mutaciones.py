"""Comprueba que la suite muerde: cada mutación del catálogo pone rojo su criterio.

Es lento —crea una base y aplica las migraciones por mutación— así que va marcado:

    python -m pytest tests -m "not mutacion"    # solo la suite
    python -m pytest tests -m mutacion          # solo las mutaciones
"""
from __future__ import annotations

import os
import subprocess
import sys
import uuid
from pathlib import Path

import psycopg
import pytest

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ))
from tests.mutaciones import CATALOGO, Mutacion


@pytest.mark.mutacion
@pytest.mark.parametrize("mutacion", CATALOGO, ids=lambda m: m.nombre)
def test_la_mutacion_pone_rojo_su_criterio(mutacion: Mutacion):
    base = f"espazio_mut_{uuid.uuid4().hex[:8]}"
    with psycopg.connect(dbname="postgres", autocommit=True) as cn:
        cn.execute(f'create database "{base}"')
    try:
        subprocess.run([str(RAIZ / "esquema" / "aplicar.sh"), base],
                       check=True, capture_output=True, text=True)
        with psycopg.connect(dbname=base, autocommit=True) as cn:
            cn.execute(mutacion.sql)

        r = subprocess.run(
            [sys.executable, "-m", "pytest", mutacion.criterio, "-q", "-p", "no:cacheprovider"],
            capture_output=True, text=True, cwd=RAIZ,
            env=dict(os.environ, ESPAZIO_BASE=base))
        assert r.returncode != 0, (
            f"la mutación «{mutacion.nombre}» no la detecta nadie:\n"
            f"{mutacion.criterio} sigue en verde.\n{r.stdout[-2000:]}")
    finally:
        with psycopg.connect(dbname="postgres", autocommit=True) as cn:
            cn.execute(f'drop database if exists "{base}" with (force)')
