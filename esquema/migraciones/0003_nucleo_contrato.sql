-- 0003 — Contrato mínimo con el esquema núcleo (decisión §2.8).
--
-- ESTO NO ES EL ESQUEMA NÚCLEO. Es la parte del contrato que la capa de anotación
-- necesita para que sus claves ajenas resuelvan: identidad estable e inmutable, y
-- versiones con validez temporal aparte. La geometría, los alias de plano, IMDF y el
-- grafo de navegación son otra decisión y otra migración.
CREATE SCHEMA nucleo;

CREATE TABLE nucleo.venue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid()
);

-- Identidad estable: sin atributos que cambien. Los códigos de plano son alias y viven
-- en el núcleo, nunca aquí y nunca como clave.
CREATE TABLE nucleo.recinto (
  id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id uuid NOT NULL REFERENCES nucleo.venue(id)
);

CREATE TABLE nucleo.arista (
  id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id uuid NOT NULL REFERENCES nucleo.venue(id)
);

-- Las tablas de versión (recinto_version, arista_version) las define el esquema núcleo.
-- La anotación no las referencia: apunta a la identidad estable y resuelve la versión
-- por join temporal contra su semana.
