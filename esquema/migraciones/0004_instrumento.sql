-- 0004 — Catálogos del instrumento, versionados (decisión §2.5).
-- Cambiar el vocabulario invalida los datos ya recogidos (CLAUDE.md regla 6). Versionarlo
-- convierte esa advertencia en estructura: mezclar cohortes exige un acto explícito.
CREATE SCHEMA instrumento;

CREATE TABLE instrumento.version (
  id                smallint PRIMARY KEY,
  codigo            text NOT NULL UNIQUE,
  estado            text NOT NULL CHECK (estado IN ('borrador','validado','retirado')),
  validado_en       date,
  notas_validacion  text,
  creado_en         timestamptz NOT NULL DEFAULT now(),
  CHECK (estado <> 'validado' OR validado_en IS NOT NULL)
);

CREATE TABLE instrumento.etiqueta_afectiva (
  version_id      smallint NOT NULL REFERENCES instrumento.version(id),
  codigo          text     NOT NULL,
  valencia        smallint NOT NULL CHECK (valencia   BETWEEN -2 AND 2),
  activacion      smallint NOT NULL CHECK (activacion BETWEEN -2 AND 2),
  orden_canonico  smallint NOT NULL,
  PRIMARY KEY (version_id, codigo)
);
COMMENT ON COLUMN instrumento.etiqueta_afectiva.orden_canonico IS
  'Reproduce la lista base. NO es el orden de presentación: §5.2 exige sortearlo en cada anotación.';

CREATE TABLE instrumento.atribucion (
  version_id      smallint NOT NULL REFERENCES instrumento.version(id),
  codigo          text     NOT NULL,
  orden_canonico  smallint NOT NULL,
  PRIMARY KEY (version_id, codigo)
);

CREATE TABLE instrumento.franja (
  version_id  smallint NOT NULL REFERENCES instrumento.version(id),
  codigo      text     NOT NULL,
  hora_desde  time     NOT NULL,
  hora_hasta  time     NOT NULL,
  orden       smallint NOT NULL,
  PRIMARY KEY (version_id, codigo),
  CHECK (hora_desde < hora_hasta)
);

CREATE TABLE instrumento.texto (
  version_id        smallint NOT NULL,
  ambito            text NOT NULL CHECK (ambito IN ('etiqueta','atribucion','franja','intensidad')),
  codigo            text NOT NULL,
  lengua            text NOT NULL CHECK (lengua IN ('es','eu')),
  etiqueta_visible  text NOT NULL,
  PRIMARY KEY (version_id, ambito, codigo, lengua)
);

-- El umbral vive en DDL y solo en DDL. No hay tabla cuyo contenido lo determine, así que
-- no existe ningún UPDATE que lo baje: cambiarlo exige una migración revisada (§2.2).
CREATE FUNCTION instrumento.umbral_k() RETURNS integer
  LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$ SELECT 5 $$;

-- I3: una versión no pasa a 'validado' si le falta cualquier traducción es/eu.
CREATE FUNCTION instrumento.exige_traduccion_completa() RETURNS trigger
  LANGUAGE plpgsql AS $$
DECLARE faltan integer;
BEGIN
  IF NEW.estado <> 'validado' THEN RETURN NEW; END IF;
  SELECT count(*) INTO faltan FROM (
    SELECT 'etiqueta' AS ambito, codigo FROM instrumento.etiqueta_afectiva WHERE version_id = NEW.id
    UNION ALL
    SELECT 'atribucion', codigo FROM instrumento.atribucion WHERE version_id = NEW.id
    UNION ALL
    SELECT 'franja', codigo FROM instrumento.franja WHERE version_id = NEW.id
  ) e
  CROSS JOIN (VALUES ('es'),('eu')) AS l(lengua)
  WHERE NOT EXISTS (
    SELECT 1 FROM instrumento.texto t
    WHERE t.version_id = NEW.id AND t.ambito = e.ambito
      AND t.codigo = e.codigo AND t.lengua = l.lengua);
  IF faltan > 0 THEN
    RAISE EXCEPTION 'la versión % no puede validarse: faltan % traducciones', NEW.codigo, faltan
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER exige_traduccion_completa
  BEFORE INSERT OR UPDATE ON instrumento.version
  FOR EACH ROW EXECUTE FUNCTION instrumento.exige_traduccion_completa();

-- Franja a partir del instante local.
-- El huso lo fija PROYECTO.md §5.5 como decisión del instrumento, no el código: cambiarlo
-- después de recoger invalida la cohorte. Aquí solo se aplica.
-- Pendiente asociado: los cortes de §5.5 no cubren el día entero, así que una anotación
-- fuera de 07:00–23:00 no tiene franja y la consolidación falla al llegar a ella. Falla
-- ruidosamente y no en silencio, que es lo correcto, pero tumba el lote entero.
CREATE FUNCTION instrumento.franja_de(p_version smallint, p_momento timestamptz)
  RETURNS text LANGUAGE sql STABLE AS $$
  SELECT f.codigo FROM instrumento.franja f
  WHERE f.version_id = p_version
    AND (p_momento AT TIME ZONE 'Europe/Madrid')::time >= f.hora_desde
    AND (p_momento AT TIME ZONE 'Europe/Madrid')::time <  f.hora_hasta
  ORDER BY f.orden LIMIT 1
$$;
