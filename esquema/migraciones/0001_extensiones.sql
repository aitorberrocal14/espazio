-- 0001 — Extensiones.
-- btree_gist es imprescindible: sostiene el EXCLUDE que hace disyunta la zonificación
-- (criterio Z3). PostGIS no se pide aquí: la capa de anotación no guarda geometría, la
-- guarda el esquema núcleo, que es otra decisión.
CREATE EXTENSION IF NOT EXISTS btree_gist;
