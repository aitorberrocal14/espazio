-- 0009 — Consolidación (decisión §2.3).
-- Traslada la captura al dato consolidado destruyendo por el camino toda posibilidad de
-- reagrupar por autor. Una sesión se consolida entera o no se consolida: partirla haría
-- que contase dos veces en n_sesiones.
CREATE SCHEMA consolidacion;

CREATE FUNCTION consolidacion.consolidar(p_campana uuid, p_cerrar boolean DEFAULT false)
  RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_lote uuid; v_venue uuid; v_version smallint; v_sin_franja integer;
BEGIN
  SELECT venue_id, version_instrumento INTO v_venue, v_version
    FROM anotacion.campana WHERE id = p_campana;
  IF v_venue IS NULL THEN
    RAISE EXCEPTION 'campaña % inexistente', p_campana USING ERRCODE = 'no_data_found';
  END IF;

  DROP TABLE IF EXISTS _cand; DROP TABLE IF EXISTS _bor; DROP TABLE IF EXISTS _excl;

  -- Al cerrar entran también las sesiones abandonadas sin cerrar: o se consolidan o se
  -- descartan, pero no se quedan.
  CREATE TEMP TABLE _cand AS
    SELECT s.id AS sesion_id, s.grupo_rol, s.modo, s.lengua
    FROM captura.sesion s
    WHERE s.campana_id = p_campana AND (p_cerrar OR s.cerrada_en IS NOT NULL);

  -- A8: por debajo del lote mínimo no se consolida nada; las sesiones esperan en captura.
  IF NOT p_cerrar AND (SELECT count(*) FROM _cand) < instrumento.umbral_k() THEN
    DROP TABLE _cand; RETURN NULL;
  END IF;

  CREATE TEMP TABLE _bor AS
    SELECT b.id AS borrador_id, gen_random_uuid() AS nueva_id, b.sesion_id,
           c.grupo_rol, c.modo, c.lengua,
           b.recinto_id, b.arista_id, b.etiqueta, b.intensidad, b.elicitacion,
           array_position(b.permutacion_etiquetas, b.etiqueta)::smallint AS posicion_etiqueta,
           date_trunc('week', b.momento AT TIME ZONE 'Europe/Madrid')::date AS semana_iso,
           instrumento.franja_de(v_version, b.momento) AS franja
    FROM captura.anotacion_borrador b JOIN _cand c ON c.sesion_id = b.sesion_id;

  SELECT count(*) INTO v_sin_franja FROM _bor WHERE franja IS NULL;
  IF v_sin_franja > 0 THEN
    RAISE EXCEPTION '% anotaciones caen fuera de toda franja de la versión %',
      v_sin_franja, v_version USING ERRCODE = 'check_violation';
  END IF;

  -- Punto fijo: una sesión no se consolida si alguno de sus grupos
  -- (campaña, venue, grupo_rol, semana_iso, franja) quedaría formado por ella sola.
  -- Es iterativo porque excluir una sesión puede dejar unitario el grupo de otra.
  CREATE TEMP TABLE _excl (sesion_id uuid PRIMARY KEY);
  LOOP
    INSERT INTO _excl
    SELECT DISTINCT b.sesion_id FROM _bor b
    WHERE b.sesion_id NOT IN (SELECT sesion_id FROM _excl)
      AND EXISTS (
        SELECT 1 FROM (
          SELECT b2.grupo_rol, b2.semana_iso, b2.franja,
                 count(DISTINCT b2.sesion_id) AS n
          FROM _bor b2 WHERE b2.sesion_id NOT IN (SELECT sesion_id FROM _excl)
          GROUP BY 1,2,3) g
        WHERE g.grupo_rol = b.grupo_rol AND g.semana_iso = b.semana_iso
          AND g.franja = b.franja AND g.n < 2
          -- Un grupo que ya existe consolidado nació con dos sesiones o más: sumarle una
          -- no lo vuelve unitario.
          AND NOT EXISTS (
            SELECT 1 FROM anotacion.anotacion a
            WHERE a.campana_id = p_campana AND a.venue_id = v_venue
              AND a.grupo_rol = g.grupo_rol AND a.semana_iso = g.semana_iso
              AND a.franja = g.franja));
    EXIT WHEN NOT FOUND;
  END LOOP;

  INSERT INTO anotacion.lote_consolidacion (campana_id, n_sesiones, n_anotaciones)
  SELECT p_campana,
         (SELECT count(DISTINCT sesion_id) FROM _bor WHERE sesion_id NOT IN (SELECT sesion_id FROM _excl)),
         (SELECT count(*) FROM _bor WHERE sesion_id NOT IN (SELECT sesion_id FROM _excl))
  RETURNING id INTO v_lote;

  -- ORDER BY random(): el orden de inserción no debe reproducir el orden de sesión.
  INSERT INTO anotacion.anotacion (
    id, campana_id, venue_id, version_instrumento, grupo_rol, recinto_id, arista_id,
    etiqueta, intensidad, modo, elicitacion, lengua, posicion_etiqueta, semana_iso, franja)
  SELECT b.nueva_id, p_campana, v_venue, v_version, b.grupo_rol, b.recinto_id, b.arista_id,
         b.etiqueta, b.intensidad, b.modo, b.elicitacion, b.lengua, b.posicion_etiqueta,
         b.semana_iso, b.franja
  FROM _bor b WHERE b.sesion_id NOT IN (SELECT sesion_id FROM _excl)
  ORDER BY random();

  INSERT INTO anotacion.atribucion_anotacion (anotacion_id, version_instrumento, atribucion)
  SELECT b.nueva_id, v_version, ab.atribucion
  FROM _bor b JOIN captura.atribucion_borrador ab ON ab.anotacion_id = b.borrador_id
  WHERE b.sesion_id NOT IN (SELECT sesion_id FROM _excl);

  INSERT INTO cualitativo.nota (anotacion_id, texto)
  SELECT b.nueva_id, nb.texto
  FROM _bor b JOIN captura.nota_borrador nb ON nb.anotacion_id = b.borrador_id
  WHERE b.sesion_id NOT IN (SELECT sesion_id FROM _excl);

  -- n_sesiones por celda, calculado aquí porque después ya no habrá sesiones que contar.
  INSERT INTO anotacion.celda_recuento AS cr
    (campana_id, zona_id, grupo_rol, franja, n_anotaciones, n_sesiones)
  SELECT p_campana, z.zona_id, z.grupo_rol, z.franja,
         count(*), count(DISTINCT z.sesion_id)
  FROM (
    SELECT b.*, COALESCE(zr.zona_id, za.zona_id) AS zona_id
    FROM _bor b
    LEFT JOIN anotacion.zona_recinto zr ON zr.recinto_id = b.recinto_id
         AND daterange(zr.validez_desde, zr.validez_hasta) @> b.semana_iso
    LEFT JOIN anotacion.zona_arista za ON za.arista_id = b.arista_id
         AND daterange(za.validez_desde, za.validez_hasta) @> b.semana_iso
    WHERE b.sesion_id NOT IN (SELECT sesion_id FROM _excl)) z
  GROUP BY z.zona_id, z.grupo_rol, z.franja
  ON CONFLICT (campana_id, zona_id, grupo_rol, franja) DO UPDATE
    SET n_anotaciones = cr.n_anotaciones + EXCLUDED.n_anotaciones,
        n_sesiones    = cr.n_sesiones    + EXCLUDED.n_sesiones;

  IF p_cerrar THEN
    -- R10: con nombre, no como total.
    INSERT INTO anotacion.descarte
      (lote_id, campana_id, venue_id, grupo_rol, n_sesiones, n_anotaciones)
    SELECT v_lote, p_campana, v_venue, b.grupo_rol,
           count(DISTINCT b.sesion_id), count(*)
    FROM _bor b WHERE b.sesion_id IN (SELECT sesion_id FROM _excl)
    GROUP BY b.grupo_rol;
    DELETE FROM captura.sesion WHERE campana_id = p_campana;
  ELSE
    DELETE FROM captura.sesion s
    WHERE s.campana_id = p_campana
      AND s.id IN (SELECT sesion_id FROM _cand)
      AND s.id NOT IN (SELECT sesion_id FROM _excl);
  END IF;

  DROP TABLE _cand; DROP TABLE _bor; DROP TABLE _excl;
  RETURN v_lote;
END $$;
