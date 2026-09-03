-- 0012 — Corrige el privilegio de captura que introdujo 0011.
--
-- 0011 concedió SELECT sobre la columna `id` para que UPDATE y RETURNING funcionasen.
-- Era un canal lateral: con SELECT (id), `select id from captura.anotacion_borrador`
-- enumera todos los borradores y con ello la cadencia de recogida —cuántas personas
-- están anotando y cuándo—, que es justo lo que la zona de captura no debe exponer.
--
-- Comprobado contra el motor, las tres alternativas con privilegios de tabla:
--   sin SELECT             -> INSERT ... RETURNING id falla (permission denied)
--   con GRANT SELECT (id)  -> RETURNING funciona Y el SELECT desnudo enumera
--   RLS SELECT USING(false)-> el SELECT desnudo no enumera Y RETURNING falla
-- No hay combinación de grants que dé las dos cosas. Así que el INSERT ... RETURNING se
-- mete dentro de la frontera: funciones SECURITY DEFINER que devuelven el id recién
-- creado y nada más. El rol conserva INSERT/UPDATE directos sobre las tablas (criterio
-- P2) y no recupera ninguna capacidad de lectura.

REVOKE SELECT (id) ON captura.sesion             FROM espazio_captura;
REVOKE SELECT (id) ON captura.anotacion_borrador FROM espazio_captura;

CREATE FUNCTION captura.abrir_sesion(
    p_campana uuid, p_venue uuid, p_grupo_rol text, p_modo text, p_lengua text)
  RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = pg_catalog, public AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO captura.sesion (campana_id, venue_id, grupo_rol, modo, lengua)
  VALUES (p_campana, p_venue, p_grupo_rol, p_modo, p_lengua)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE FUNCTION captura.anotar(
    p_sesion uuid, p_recinto uuid, p_arista uuid, p_etiqueta text, p_intensidad smallint,
    p_elicitacion text, p_permutacion_etiquetas text[], p_permutacion_atribuciones text[],
    p_momento timestamptz DEFAULT now())
  RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = pg_catalog, public AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO captura.anotacion_borrador (
    sesion_id, recinto_id, arista_id, etiqueta, intensidad, elicitacion, momento,
    permutacion_etiquetas, permutacion_atribuciones)
  VALUES (p_sesion, p_recinto, p_arista, p_etiqueta, p_intensidad, p_elicitacion,
          p_momento, p_permutacion_etiquetas, p_permutacion_atribuciones)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE FUNCTION captura.cerrar_sesion(p_sesion uuid)
  RETURNS void LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = pg_catalog, public AS $$
BEGIN
  UPDATE captura.sesion SET cerrada_en = now() WHERE id = p_sesion AND cerrada_en IS NULL;
END $$;

-- Las tres devuelven un identificador o nada. Ninguna devuelve contenido, ninguna acepta
-- un filtro, ninguna enumera. Quien llama tiene que traer ya el id de la fila sobre la
-- que actúa: los uuid son aleatorios y no se adivinan.
REVOKE EXECUTE ON FUNCTION
  captura.abrir_sesion(uuid, uuid, text, text, text),
  captura.anotar(uuid, uuid, uuid, text, smallint, text, text[], text[], timestamptz),
  captura.cerrar_sesion(uuid)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  captura.abrir_sesion(uuid, uuid, text, text, text),
  captura.anotar(uuid, uuid, uuid, text, smallint, text, text[], text[], timestamptz),
  captura.cerrar_sesion(uuid)
TO espazio_captura;
