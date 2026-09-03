-- 0006 — Zona de captura: estado efímero de recogida (decisión §2.3).
-- Todo lo que hay aquí se destruye al consolidar. Es el único sitio del esquema donde
-- existe un identificador capaz de agrupar anotaciones por autor.
CREATE SCHEMA captura;

-- Deduplicación por token de un solo uso. NO se guarda qué sesión lo consumió: si se
-- guardara, y los tokens se repartieran nominalmente, el token sería un pseudónimo.
CREATE TABLE captura.token (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campana_id    uuid NOT NULL REFERENCES anotacion.campana(id),
  emitido_en    timestamptz NOT NULL DEFAULT now(),
  consumido_en  timestamptz
);

CREATE TABLE captura.sesion (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campana_id  uuid NOT NULL REFERENCES anotacion.campana(id),
  venue_id    uuid NOT NULL,
  grupo_rol   text NOT NULL,
  modo        text NOT NULL CHECK (modo IN ('in_situ','retrospectivo')),
  lengua      text NOT NULL CHECK (lengua IN ('es','eu')),
  abierta_en  timestamptz NOT NULL DEFAULT now(),
  cerrada_en  timestamptz,
  FOREIGN KEY (venue_id, grupo_rol) REFERENCES anotacion.grupo_rol (venue_id, codigo)
);
-- Sin columna de permutación: el orden se sortea POR ANOTACIÓN (PROYECTO.md §5.2,
-- decisión §2.6), así que la permutación es del borrador, no de la sesión.

CREATE TABLE captura.anotacion_borrador (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sesion_id                 uuid NOT NULL REFERENCES captura.sesion(id) ON DELETE CASCADE,
  recinto_id                uuid REFERENCES nucleo.recinto(id),
  arista_id                 uuid REFERENCES nucleo.arista(id),
  etiqueta                  text     NOT NULL,
  intensidad                smallint NOT NULL CHECK (intensidad IN (1,2,3)),
  elicitacion               text     NOT NULL
                            CHECK (elicitacion IN ('espontanea','cierre_positivo')),
  momento                   timestamptz NOT NULL DEFAULT now(),
  permutacion_etiquetas     text[] NOT NULL,
  permutacion_atribuciones  text[] NOT NULL,
  CHECK (num_nonnulls(recinto_id, arista_id) = 1),
  -- elicitacion en la clave: §5.5 cierra preguntando por un sitio donde se esté a gusto,
  -- y la persona puede nombrar uno que ya anotó espontáneamente.
  UNIQUE (sesion_id, recinto_id, elicitacion),
  UNIQUE (sesion_id, arista_id, elicitacion)
);
CREATE INDEX ON captura.anotacion_borrador (sesion_id);
CREATE INDEX ON captura.sesion (campana_id) WHERE cerrada_en IS NOT NULL;

CREATE TABLE captura.atribucion_borrador (
  anotacion_id  uuid NOT NULL REFERENCES captura.anotacion_borrador(id) ON DELETE CASCADE,
  atribucion    text NOT NULL,
  PRIMARY KEY (anotacion_id, atribucion)
);

CREATE TABLE captura.nota_borrador (
  anotacion_id  uuid PRIMARY KEY REFERENCES captura.anotacion_borrador(id) ON DELETE CASCADE,
  texto         text NOT NULL CHECK (length(btrim(texto)) > 0)
);

-- Z1 — sin campaña vigente no hay sesión. SECURITY DEFINER porque espazio_captura no
-- tiene privilegio de lectura sobre anotacion.campana.
CREATE FUNCTION captura.exige_campana_vigente() RETURNS trigger
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE ok boolean;
BEGIN
  SELECT now() >= c.recogida_desde AND now() < c.recogida_hasta
    INTO ok FROM anotacion.campana c WHERE c.id = NEW.campana_id;
  IF NOT COALESCE(ok, false) THEN
    RAISE EXCEPTION 'la campaña no está en ventana de recogida'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER exige_campana_vigente BEFORE INSERT ON captura.sesion
  FOR EACH ROW EXECUTE FUNCTION captura.exige_campana_vigente();

-- Z6 — la entidad anclada tiene que estar en una zona vigente. Cierra el hueco de un
-- recinto añadido a mitad de campaña, que produciría anotaciones impublicables.
CREATE FUNCTION captura.exige_entidad_zonificada() RETURNS trigger
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE ok boolean;
BEGIN
  IF NEW.recinto_id IS NOT NULL THEN
    SELECT EXISTS (SELECT 1 FROM anotacion.zona_recinto zr
                   WHERE zr.recinto_id = NEW.recinto_id
                     AND daterange(zr.validez_desde, zr.validez_hasta)
                         @> (NEW.momento AT TIME ZONE 'Europe/Madrid')::date) INTO ok;
  ELSE
    SELECT EXISTS (SELECT 1 FROM anotacion.zona_arista za
                   WHERE za.arista_id = NEW.arista_id
                     AND daterange(za.validez_desde, za.validez_hasta)
                         @> (NEW.momento AT TIME ZONE 'Europe/Madrid')::date) INTO ok;
  END IF;
  IF NOT ok THEN
    RAISE EXCEPTION 'la entidad anotada no pertenece a ninguna zona vigente'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER exige_entidad_zonificada BEFORE INSERT OR UPDATE ON captura.anotacion_borrador
  FOR EACH ROW EXECUTE FUNCTION captura.exige_entidad_zonificada();
