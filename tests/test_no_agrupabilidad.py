"""A6: peor caso, no caso medio (decisión §2.3).

Ningún grupo (campaña, venue, grupo_rol, semana_iso, franja) del dato consolidado puede
proceder de una sola sesión. Un grupo así ES esa sesión, entera y reconstruida, aunque
el identificador se haya severado. Un índice de Rand global mediría el caso medio y
escondería justo este.

La verdad la conoce el generador porque él creó las sesiones; el dato consolidado ya no.
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from datos_sinteticos import generador as gen
from tests.conftest import como


def _escenario(conn):
    """Escenario con verdad conocida y grupos unitarios puestos a propósito."""
    rng = random.Random(20260903)
    version = gen.sembrar_instrumento(conn)
    venue = gen.sembrar_venue(
        conn, zonas=["z0", "z1"],
        grupos_rol=["pdi", "administracion", "conserjeria", "limpieza"])
    campana = gen.sembrar_campana(conn, venue, version)
    w1, w2 = gen.lunes_hace(2), gen.lunes_hace(3)
    plan = []

    # Grupos sanos: más de una sesión cada uno.
    for _ in range(3):
        plan.append(gen.sembrar_sesion(conn, campana, venue, grupo_rol="pdi", zona="z0",
                                       semana_iso=w1, franja="manana",
                                       n_anotaciones=2, rng=rng))
    for _ in range(2):
        plan.append(gen.sembrar_sesion(conn, campana, venue, grupo_rol="administracion",
                                       zona="z1", semana_iso=w1, franja="tarde", rng=rng))

    # Unitario directo: una sola persona de limpieza esa semana, a esa hora.
    plan.append(gen.sembrar_sesion(conn, campana, venue, grupo_rol="limpieza", zona="z0",
                                   semana_iso=w2, franja="tarde", rng=rng))

    # Unitario en cadena: X toca dos grupos y está sola en el segundo. Excluir X deja
    # sola a Y en el primero, así que Y también cae. Esto es el punto fijo.
    plan.append(gen.sembrar_sesion(conn, campana, venue, grupo_rol="conserjeria", zona="z0",
                                   semana_iso=w1, franja="mediodia",
                                   franja_extra="noche", rng=rng))
    plan.append(gen.sembrar_sesion(conn, campana, venue, grupo_rol="conserjeria", zona="z0",
                                   semana_iso=w1, franja="mediodia", rng=rng))
    return venue, campana, plan


def _sesiones_por_grupo(plan):
    conteo = {}
    for s in plan:
        for g in s.grupos:
            conteo.setdefault(g, set()).add(s.id)
    return {g: len(ids) for g, ids in conteo.items()}


def test_a6_ningun_grupo_consolidado_procede_de_una_sola_sesion(conn):
    venue, campana, plan = _escenario(conn)
    esperado = _sesiones_por_grupo(plan)
    assert min(esperado.values()) == 1, "el escenario no contiene grupos unitarios: sería vacuo"

    with como(conn, "espazio_consolidacion"):
        conn.execute("select consolidacion.consolidar(%s, true)", (campana,))

    presentes = conn.execute(
        "select grupo_rol, semana_iso, franja, count(*) from anotacion.anotacion"
        " where campana_id = %s group by 1,2,3", (campana,)).fetchall()
    assert presentes, "no se consolidó nada: el test no estaría comprobando nada"

    # EL criterio. Cada grupo que sobrevivió tuvo dos sesiones o más detrás.
    for grupo_rol, semana, franja, _n in presentes:
        origen = esperado.get((grupo_rol, semana, franja))
        assert origen is not None, f"grupo inesperado en el consolidado: {grupo_rol} {semana} {franja}"
        assert origen >= 2, (
            f"el grupo ({grupo_rol}, {semana}, {franja}) procede de {origen} sesión: "
            "está reconstruido entero")


def test_a6_los_grupos_unitarios_no_se_consolidan_y_quedan_contados_por_rol(conn):
    venue, campana, plan = _escenario(conn)
    esperado = _sesiones_por_grupo(plan)
    unitarios = {g for g, n in esperado.items() if n < 2}

    with como(conn, "espazio_consolidacion"):
        conn.execute("select consolidacion.consolidar(%s, true)", (campana,))

    presentes = {tuple(r) for r in conn.execute(
        "select grupo_rol, semana_iso, franja from anotacion.anotacion"
        " where campana_id = %s", (campana,)).fetchall()}
    assert unitarios & presentes == set(), f"grupos unitarios consolidados: {unitarios & presentes}"

    # El punto fijo: conserjeria cae entera, las dos sesiones, no solo la que estaba sola.
    assert not any(r == "conserjeria" for r, _s, _f in presentes)

    # R10 — el descarte se registra CON NOMBRE, porque el sesgo no es aleatorio.
    descartes = dict(conn.execute(
        "select grupo_rol, n_sesiones from anotacion.descarte where campana_id = %s",
        (campana,)).fetchall())
    assert descartes == {"limpieza": 1, "conserjeria": 2}, descartes
    assert "pdi" not in descartes

    # A2 — cerrada la campaña, en captura no queda nada.
    assert conn.execute("select count(*) from captura.sesion where campana_id = %s",
                        (campana,)).fetchone()[0] == 0
