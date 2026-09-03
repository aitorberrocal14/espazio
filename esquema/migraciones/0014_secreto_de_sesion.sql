-- 0014 — El identificador de sesión deja de ser suficiente para escribir en ella.
--
-- 0012 dejó la API de escritura aceptando cualquier id de sesión que le pasaran, con el
-- supuesto de que quien llama es el backend de captura. Ese supuesto deja de ser cierto
-- en cuanto alguien añade un endpoint, y es contra eso exactamente contra lo que existe
-- la separación de privilegios entera. Además el id de sesión viaja por sitios donde se
-- queda escrito —URL de un QR, historial, logs, cabeceras—, así que tratarlo como
-- credencial es tratar como secreto algo que no lo es.
--
-- Quien abre la sesión recibe un secreto que no vuelve a estar en ninguna parte legible:
-- solo se guarda su sha256. Sin ese secreto no se anota ni se cierra.
--
-- CONSECUENCIA que obliga a cambiar el criterio P2: mientras espazio_captura conserve
-- INSERT directo sobre captura.anotacion_borrador, el secreto es decorativo —se escribe
-- saltándose la API—. Así que la zona de captura pasa a ser accesible ÚNICAMENTE por la
-- API. El rol se queda sin un solo privilegio sobre esas tablas.

ALTER TABLE captura.sesion ADD COLUMN secreto_hash bytea NOT NULL;

DROP FUNCTION captura.anotar(uuid, uuid, uuid, text, smallint, text, text[], text[], timestamptz);
DROP FUNCTION captura.cerrar_sesion(uuid);
DROP FUNCTION captura.abrir_sesion(uuid, uuid, text, text, text);

-- Un único mensaje para los tres motivos de rechazo: distinguir «secreto incorrecto» de
-- «sesión cerrada» convertiría la función en un oráculo sobre qué sesiones existen.
CREATE FUNCTION captura.exige_sesion_autorizada(p_sesion uuid, p_secreto text)
  RETURNS void LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = pg_catalog, public AS $$
DECLARE ok boolean;
BEGIN
  SELECT s.secreto_hash = sha256(p_secreto::bytea)
         AND s.cerrada_en IS NULL
         AND now() >= c.recogida_desde AND now() < c.recogida_hasta
    INTO ok
  FROM captura.sesion s JOIN anotacion.campana c ON c.id = s.campana_id
  WHERE s.id = p_sesion;

  IF NOT COALESCE(ok, false) THEN
    RAISE EXCEPTION 'sesión no autorizada'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
END $$;

CREATE FUNCTION captura.abrir_sesion(
    p_campana uuid, p_venue uuid, p_grupo_rol text, p_modo text, p_lengua text)
  RETURNS TABLE (sesion_id uuid, secreto text)
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_secreto text;
BEGIN
  v_secreto := gen_random_uuid()::text || gen_random_uuid()::text;
  INSERT INTO captura.sesion (campana_id, venue_id, grupo_rol, modo, lengua, secreto_hash)
  VALUES (p_campana, p_venue, p_grupo_rol, p_modo, p_lengua, sha256(v_secreto::bytea))
  RETURNING id INTO sesion_id;
  secreto := v_secreto;
  RETURN NEXT;
END $$;

-- La anotación entra entera de una vez: entidad, afecto, atribuciones y nota. Son los
-- cuatro pasos de PROYECTO.md §5.1 y son un solo acto, no cuatro escrituras sueltas.
CREATE FUNCTION captura.anotar(
    p_sesion uuid, p_secreto text, p_recinto uuid, p_arista uuid, p_etiqueta text,
    p_intensidad smallint, p_elicitacion text, p_atribuciones text[],
    p_permutacion_etiquetas text[], p_permutacion_atribuciones text[],
    p_nota text DEFAULT NULL, p_momento timestamptz DEFAULT now())
  RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = pg_catalog, public AS $$
DECLARE v_id uuid;
BEGIN
  PERFORM captura.exige_sesion_autorizada(p_sesion, p_secreto);

  INSERT INTO captura.anotacion_borrador (
    sesion_id, recinto_id, arista_id, etiqueta, intensidad, elicitacion, momento,
    permutacion_etiquetas, permutacion_atribuciones)
  VALUES (p_sesion, p_recinto, p_arista, p_etiqueta, p_intensidad, p_elicitacion,
          p_momento, p_permutacion_etiquetas, p_permutacion_atribuciones)
  RETURNING id INTO v_id;

  IF p_atribuciones IS NOT NULL THEN
    INSERT INTO captura.atribucion_borrador (anotacion_id, atribucion)
    SELECT v_id, a FROM unnest(p_atribuciones) AS a;
  END IF;

  IF p_nota IS NOT NULL AND btrim(p_nota) <> '' THEN
    INSERT INTO captura.nota_borrador (anotacion_id, texto) VALUES (v_id, p_nota);
  END IF;

  RETURN v_id;
END $$;

CREATE FUNCTION captura.cerrar_sesion(p_sesion uuid, p_secreto text)
  RETURNS void LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = pg_catalog, public AS $$
BEGIN
  PERFORM captura.exige_sesion_autorizada(p_sesion, p_secreto);
  UPDATE captura.sesion SET cerrada_en = now() WHERE id = p_sesion;
END $$;

-- La zona de captura queda accesible solo por la API. Sin esto el secreto no sirve.
REVOKE INSERT, UPDATE ON ALL TABLES IN SCHEMA captura FROM espazio_captura;

REVOKE EXECUTE ON FUNCTION
  captura.exige_sesion_autorizada(uuid, text),
  captura.abrir_sesion(uuid, uuid, text, text, text),
  captura.anotar(uuid, text, uuid, uuid, text, smallint, text, text[], text[], text[], text, timestamptz),
  captura.cerrar_sesion(uuid, text)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  captura.abrir_sesion(uuid, uuid, text, text, text),
  captura.anotar(uuid, text, uuid, uuid, text, smallint, text, text[], text[], text[], text, timestamptz),
  captura.cerrar_sesion(uuid, text)
TO espazio_captura;
-- exige_sesion_autorizada NO se concede: es interna, y ofrecerla sería el oráculo.
