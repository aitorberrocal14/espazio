"""Generador de datos sintéticos para la capa de anotación.

Mínimo para los criterios P1–P5, U1 y A6 de
`decisiones/2026-09-03-esquema-capa-anotacion.md`. No pretende ser un simulador del
piloto: pretende dar control exacto sobre quién anota qué, cuándo y en qué zona, que es
lo que necesitan las pruebas de umbral y de no agrupabilidad.

Nunca toca datos reales (CLAUDE.md regla 4). Todo lo que produce es inventado aquí.
"""
from __future__ import annotations

import random
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo
from uuid import UUID

TZ = ZoneInfo("Europe/Madrid")

# Vocabulario de PROYECTO.md §5.2.
#
# CUIDADO: los pares (valencia, activación) de abajo son RELLENO PARA PRUEBAS, no la
# codificación del instrumento. §5.2 dice que el vocabulario se valida antes con perfiles
# distintos, y el riesgo R2 de la decisión deja abierto en particular el signo de
# `indiferente`, que aquí va como 0 precisamente porque está sin decidir. No copies estos
# números a una campaña real.
VOCABULARIO = [
    # (codigo, valencia, activacion, es, eu)
    ("agradable",   2,  0, "agradable",   "atsegina"),
    ("tranquilo",   1, -1, "tranquilo",   "lasaia"),
    ("estimulante", 1,  2, "estimulante", "kitzikagarria"),
    ("seguro",      1, -1, "seguro",      "segurua"),
    ("incomodo",   -1,  0, "incómodo",    "deserosoa"),
    ("agobiante",  -2,  2, "agobiante",   "itogarria"),
    ("tenso",      -1,  1, "tenso",       "tentsioan"),
    ("indiferente", 0, -2, "indiferente", "axolagabea"),
]

ATRIBUCIONES = [
    ("limpieza", "limpieza", "garbiketa"), ("ruido", "ruido", "zarata"),
    ("luz", "luz", "argia"), ("gente", "gente", "jendea"),
    ("temperatura", "temperatura", "tenperatura"), ("orientacion", "orientación", "orientazioa"),
    ("privacidad", "privacidad", "pribatutasuna"), ("seguridad", "seguridad", "segurtasuna"),
]

# Propuesta de partida de la decisión, §5 «qué queda fuera»: pendiente de confirmación.
FRANJAS = [
    ("manana",   "07:00", "12:00", 1, "mañana",   "goiza"),
    ("mediodia", "12:00", "15:00", 2, "mediodía", "eguerdia"),
    ("tarde",    "15:00", "19:00", 3, "tarde",    "arratsaldea"),
    ("noche",    "19:00", "23:00", 4, "noche",    "gaua"),
]
HORA_CENTRAL = {"manana": 9, "mediodia": 13, "tarde": 17, "noche": 20}


@dataclass
class Venue:
    id: UUID
    grupos_rol: list[str]
    zonas: dict[str, UUID] = field(default_factory=dict)
    recintos: dict[str, list[UUID]] = field(default_factory=dict)
    aristas: dict[str, list[UUID]] = field(default_factory=dict)


@dataclass
class SesionPlan:
    """Lo que el generador sabe y el dato consolidado ya no: de qué sesión vino cada fila.

    `grupos` son las claves del criterio A6 —(grupo_rol, semana_iso, franja), sin zona—
    que esta sesión toca. Una sesión puede tocar más de una si cruza una franja, y ahí
    es donde el punto fijo de la consolidación tiene algo que hacer: excluirla puede
    dejar unitario el grupo de otra.
    """
    id: UUID
    grupo_rol: str
    zona: str
    semana_iso: date
    grupos: set[tuple] = field(default_factory=set)
    n_anotaciones: int = 0


def sembrar_instrumento(conn, version_id: int = 1, codigo: str = "v1-pruebas") -> int:
    with conn.cursor() as cur:
        cur.execute(
            "insert into instrumento.version (id, codigo, estado) values (%s, %s, 'borrador')",
            (version_id, codigo))
        for orden, (cod, val, act, es, eu) in enumerate(VOCABULARIO, start=1):
            cur.execute(
                "insert into instrumento.etiqueta_afectiva"
                " (version_id, codigo, valencia, activacion, orden_canonico)"
                " values (%s,%s,%s,%s,%s)", (version_id, cod, val, act, orden))
            _texto(cur, version_id, "etiqueta", cod, es, eu)
        for orden, (cod, es, eu) in enumerate(ATRIBUCIONES, start=1):
            cur.execute("insert into instrumento.atribucion (version_id, codigo, orden_canonico)"
                        " values (%s,%s,%s)", (version_id, cod, orden))
            _texto(cur, version_id, "atribucion", cod, es, eu)
        for cod, desde, hasta, orden, es, eu in FRANJAS:
            cur.execute("insert into instrumento.franja"
                        " (version_id, codigo, hora_desde, hora_hasta, orden)"
                        " values (%s,%s,%s,%s,%s)", (version_id, cod, desde, hasta, orden))
            _texto(cur, version_id, "franja", cod, es, eu)
        for n, (es, eu) in enumerate([("baja", "txikia"), ("media", "ertaina"), ("alta", "handia")], 1):
            _texto(cur, version_id, "intensidad", str(n), es, eu)
        # Con las traducciones completas ya puede validarse (criterio I3).
        cur.execute("update instrumento.version set estado='validado', validado_en=current_date,"
                    " notas_validacion='sintética: NO es una validación de campo'"
                    " where id=%s", (version_id,))
    return version_id


def _texto(cur, version_id, ambito, codigo, es, eu):
    cur.executemany(
        "insert into instrumento.texto (version_id, ambito, codigo, lengua, etiqueta_visible)"
        " values (%s,%s,%s,%s,%s)",
        [(version_id, ambito, codigo, "es", es), (version_id, ambito, codigo, "eu", eu)])


def sembrar_venue(conn, *, zonas: list[str], recintos_por_zona: int = 3,
                  aristas_por_zona: int = 1, grupos_rol: list[str],
                  validez_desde: date | None = None) -> Venue:
    """Crea venue, catálogo de roles y una zonificación que es PARTICIÓN.

    El orden importa: las zonas se crean antes que la campaña, porque en cuanto hay
    recogida abierta la congelación (Z5) impide tocarlas.
    """
    validez_desde = validez_desde or date(2000, 1, 1)
    with conn.cursor() as cur:
        cur.execute("insert into nucleo.venue default values returning id")
        venue = Venue(id=cur.fetchone()[0], grupos_rol=list(grupos_rol))
        for rol in grupos_rol:
            cur.execute("insert into anotacion.grupo_rol (venue_id, codigo) values (%s,%s)",
                        (venue.id, rol))
        for nombre in zonas:
            cur.execute("insert into anotacion.zona (venue_id, codigo, validez_desde)"
                        " values (%s,%s,%s) returning id", (venue.id, nombre, validez_desde))
            zona_id = cur.fetchone()[0]
            venue.zonas[nombre] = zona_id
            venue.recintos[nombre], venue.aristas[nombre] = [], []
            for _ in range(recintos_por_zona):
                cur.execute("insert into nucleo.recinto (venue_id) values (%s) returning id",
                            (venue.id,))
                rid = cur.fetchone()[0]
                venue.recintos[nombre].append(rid)
                cur.execute("insert into anotacion.zona_recinto"
                            " (zona_id, recinto_id, validez_desde) values (%s,%s,%s)",
                            (zona_id, rid, validez_desde))
            for _ in range(aristas_por_zona):
                cur.execute("insert into nucleo.arista (venue_id) values (%s) returning id",
                            (venue.id,))
                aid = cur.fetchone()[0]
                venue.aristas[nombre].append(aid)
                cur.execute("insert into anotacion.zona_arista"
                            " (zona_id, arista_id, validez_desde) values (%s,%s,%s)",
                            (zona_id, aid, validez_desde))
    return venue


def sembrar_campana(conn, venue: Venue, version_id: int, codigo: str = "piloto-pruebas",
                    dias_atras: int = 90, dias_adelante: int = 30) -> UUID:
    hoy = date.today()
    with conn.cursor() as cur:
        cur.execute(
            "insert into anotacion.campana (venue_id, version_instrumento, codigo,"
            " encargo_referencia, encargo_fecha, encargo_vigencia_hasta,"
            " recogida_desde, recogida_hasta)"
            " values (%s,%s,%s,%s,%s,%s,%s,%s) returning id",
            (venue.id, version_id, codigo, "sintético/sin encargo real",
             hoy - timedelta(days=dias_atras + 1), hoy + timedelta(days=dias_adelante + 1),
             datetime.combine(hoy - timedelta(days=dias_atras), datetime.min.time(), TZ),
             datetime.combine(hoy + timedelta(days=dias_adelante), datetime.min.time(), TZ)))
        return cur.fetchone()[0]


def momento_de(semana_iso: date, franja: str, dia: int = 1, minuto: int = 0) -> datetime:
    """Instante dentro de `franja`, en hora local, el día `dia` de esa semana ISO."""
    return datetime(semana_iso.year, semana_iso.month, semana_iso.day,
                    HORA_CENTRAL[franja], minuto, tzinfo=TZ) + timedelta(days=dia - 1)


def lunes_hace(semanas: int) -> date:
    hoy = date.today()
    return hoy - timedelta(days=hoy.weekday()) - timedelta(weeks=semanas)


def sembrar_sesion(conn, campana_id: UUID, venue: Venue, *, grupo_rol: str, zona: str,
                   semana_iso: date, franja: str, n_anotaciones: int = 1,
                   rng: random.Random, modo: str = "in_situ", lengua: str = "es",
                   cerrar: bool = True, con_nota: bool = False,
                   franja_extra: str | None = None) -> SesionPlan:
    """Una sesión con sus anotaciones en `zona`, `semana_iso` y `franja`.

    `franja_extra` añade una anotación más en otra franja de la misma semana, para que la
    sesión toque dos grupos A6. Sirve para provocar el caso en que excluir una sesión
    deja unitario el grupo de otra.
    """
    etiquetas = [c for c, *_ in VOCABULARIO]
    atribuciones = [c for c, *_ in ATRIBUCIONES]
    anclajes = venue.recintos[zona] + venue.aristas[zona]
    with conn.cursor() as cur:
        cur.execute("insert into captura.sesion (campana_id, venue_id, grupo_rol, modo, lengua)"
                    " values (%s,%s,%s,%s,%s) returning id",
                    (campana_id, venue.id, grupo_rol, modo, lengua))
        sesion_id = cur.fetchone()[0]
        for i in range(n_anotaciones):
            anclaje = anclajes[i % len(anclajes)]
            es_recinto = anclaje in venue.recintos[zona]
            # §5.2: el orden se sortea EN CADA ANOTACIÓN, no una vez por sesión.
            perm_e = etiquetas[:]; rng.shuffle(perm_e)
            perm_a = atribuciones[:]; rng.shuffle(perm_a)
            cur.execute(
                "insert into captura.anotacion_borrador (sesion_id, recinto_id, arista_id,"
                " etiqueta, intensidad, elicitacion, momento,"
                " permutacion_etiquetas, permutacion_atribuciones)"
                " values (%s,%s,%s,%s,%s,%s,%s,%s,%s) returning id",
                (sesion_id, anclaje if es_recinto else None, None if es_recinto else anclaje,
                 rng.choice(etiquetas), rng.randint(1, 3), "espontanea",
                 momento_de(semana_iso, franja, dia=1 + (i % 5), minuto=i % 60),
                 perm_e, perm_a))
            borrador_id = cur.fetchone()[0]
            cur.execute("insert into captura.atribucion_borrador (anotacion_id, atribucion)"
                        " values (%s,%s)", (borrador_id, rng.choice(atribuciones)))
            if con_nota:
                cur.execute("insert into captura.nota_borrador (anotacion_id, texto)"
                            " values (%s,%s)", (borrador_id, "nota sintética"))
        total = n_anotaciones
        grupos = {(grupo_rol, semana_iso, franja)}
        if franja_extra is not None:
            perm_e = etiquetas[:]; rng.shuffle(perm_e)
            perm_a = atribuciones[:]; rng.shuffle(perm_a)
            cur.execute(
                "insert into captura.anotacion_borrador (sesion_id, recinto_id, arista_id,"
                " etiqueta, intensidad, elicitacion, momento,"
                " permutacion_etiquetas, permutacion_atribuciones)"
                " values (%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                (sesion_id, venue.recintos[zona][0], None, rng.choice(etiquetas),
                 rng.randint(1, 3), "cierre_positivo",
                 momento_de(semana_iso, franja_extra, dia=2), perm_e, perm_a))
            total += 1
            grupos.add((grupo_rol, semana_iso, franja_extra))
        if cerrar:
            cur.execute("update captura.sesion set cerrada_en = now() where id = %s", (sesion_id,))
    return SesionPlan(id=sesion_id, grupo_rol=grupo_rol, zona=zona, semana_iso=semana_iso,
                      grupos=grupos, n_anotaciones=total)
