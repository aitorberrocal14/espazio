DROP FUNCTION IF EXISTS captura.cerrar_sesion(uuid, text);
DROP FUNCTION IF EXISTS captura.anotar(uuid, text, uuid, uuid, text, smallint, text, text[], text[], text[], text, timestamptz);
DROP FUNCTION IF EXISTS captura.abrir_sesion(uuid, uuid, text, text, text);
DROP FUNCTION IF EXISTS captura.exige_sesion_autorizada(uuid, text);
ALTER TABLE captura.sesion DROP COLUMN IF EXISTS secreto_hash;
GRANT INSERT, UPDATE ON ALL TABLES IN SCHEMA captura TO espazio_captura;

-- Devolver el estado anterior es devolver también las funciones de 0012, que esta
-- migración sustituyó. Sí, es duplicar sus cuerpos; es el precio de una migración que
-- reemplaza funciones, y la alternativa —una reversión que deja la zona de captura sin
-- API— no es una reversión.
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
