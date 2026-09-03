"""Catálogo de mutaciones: cada protección del esquema, desactivada a propósito.

Un test en verde no demuestra que una protección funcione; demuestra que el test pasa.
Lo que lo demuestra es que el test se ponga ROJO cuando la protección se quita. Por eso
cada protección de la zona sensible entra aquí con su mutación el mismo día que se
implementa, y `test_mutaciones.py` comprueba que el criterio correspondiente la detecta.

Regla: si añades una restricción de privilegio, de umbral o de agrupabilidad y no puedes
escribir la mutación que la rompe, es que no sabes qué está protegiendo.
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Mutacion:
    nombre: str
    sql: str
    criterio: str   # el nodo de pytest que tiene que ponerse rojo


CATALOGO: list[Mutacion] = [
    Mutacion(
        "el umbral k=5 baja a 1",
        "create or replace function instrumento.umbral_k() returns integer"
        " language sql immutable as $$ select 1 $$;",
        "tests/test_umbral.py::test_u1_la_celda_publica_en_la_quinta_sesion_y_no_antes"),
    Mutacion(
        "el umbral vuelve a contar anotaciones y no personas",
        "create function mut_umbral() returns trigger language plpgsql as $$ begin"
        " new.n_sesiones := new.n_anotaciones; return new; end $$;"
        " create trigger mut before insert or update on anotacion.celda_recuento"
        " for each row execute function mut_umbral();",
        "tests/test_umbral.py::test_u1_cinco_anotaciones_de_cuatro_personas_no_publican"),
    Mutacion(
        "espazio_analisis recibe SELECT sobre la fila",
        "grant usage on schema anotacion to espazio_analisis;"
        " grant select on anotacion.anotacion to espazio_analisis;",
        "tests/test_privilegios.py::test_p1_analisis_no_alcanza_la_fila"),
    Mutacion(
        "espazio_captura recupera el SELECT (id) que quitó 0012",
        "grant select (id) on captura.anotacion_borrador to espazio_captura;",
        "tests/test_privilegios.py::test_p2_captura_no_puede_enumerar_borradores"),
    Mutacion(
        "una vista publicada expone el recinto en vez de la zona",
        "create view analisis.fuga as select recinto_id, arista_id from anotacion.anotacion;",
        "tests/test_privilegios.py::test_p5_ninguna_vista_publicada_expone_la_entidad_anclada"),
    Mutacion(
        "una vista publicada se cuelga de las notas libres",
        "create view analisis.fuga as select n.anotacion_id from cualitativo.nota n;",
        "tests/test_privilegios.py::test_p4_ninguna_vista_publicada_depende_de_las_notas"),
    Mutacion(
        "la consolidación pierde el punto fijo y emite grupos unitarios",
        "create or replace function consolidacion.consolidar(p_campana uuid,"
        " p_cerrar boolean default false) returns uuid language plpgsql as $$"
        " declare v_lote uuid; v_venue uuid; v_version smallint; begin"
        " select venue_id, version_instrumento into v_venue, v_version"
        "   from anotacion.campana where id = p_campana;"
        " insert into anotacion.lote_consolidacion (campana_id, n_sesiones, n_anotaciones)"
        "   values (p_campana, 0, 0) returning id into v_lote;"
        " insert into anotacion.anotacion (campana_id, venue_id, version_instrumento,"
        "   grupo_rol, recinto_id, arista_id, etiqueta, intensidad, modo, elicitacion,"
        "   lengua, posicion_etiqueta, semana_iso, franja)"
        " select p_campana, v_venue, v_version, s.grupo_rol, b.recinto_id, b.arista_id,"
        "   b.etiqueta, b.intensidad, s.modo, b.elicitacion, s.lengua,"
        "   array_position(b.permutacion_etiquetas, b.etiqueta)::smallint,"
        "   date_trunc('week', b.momento at time zone 'Europe/Madrid')::date,"
        "   instrumento.franja_de(v_version, b.momento)"
        " from captura.anotacion_borrador b join captura.sesion s on s.id = b.sesion_id"
        " where s.campana_id = p_campana;"
        " delete from captura.sesion where campana_id = p_campana; return v_lote; end $$;",
        "tests/test_no_agrupabilidad.py"
        "::test_a6_ningun_grupo_consolidado_procede_de_una_sola_sesion"),
]
