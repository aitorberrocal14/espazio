-- 0005 — Campaña, catálogo social y zonificación (decisión §2.4 y §2.7).
CREATE SCHEMA anotacion;

-- El encargo institucional de §7 deja de ser una norma de uso: sin campaña con encargo
-- registrado y vigente no se puede abrir una sesión.
CREATE TABLE anotacion.campana (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id                uuid NOT NULL REFERENCES nucleo.venue(id),
  version_instrumento     smallint NOT NULL REFERENCES instrumento.version(id),
  codigo                  text NOT NULL UNIQUE,
  encargo_referencia      text NOT NULL,
  encargo_fecha           date NOT NULL,
  encargo_vigencia_hasta  date NOT NULL,
  -- Hoy solo cabe 'ninguno'. Un panel futuro amplía este CHECK para una campaña nueva:
  -- migración aditiva, el histórico conserva 'ninguno' y no se toca (§2.4).
  regimen_pseudonimo      text NOT NULL DEFAULT 'ninguno'
                          CHECK (regimen_pseudonimo IN ('ninguno')),
  recogida_desde          timestamptz NOT NULL,
  recogida_hasta          timestamptz NOT NULL,
  CHECK (recogida_desde < recogida_hasta),
  CHECK (encargo_fecha <= recogida_desde::date),
  CHECK (recogida_hasta::date <= encargo_vigencia_hasta),
  UNIQUE (id, venue_id, version_instrumento)
);

-- §7: función amplia, nunca departamento ni persona. No hay columna de departamento en
-- ninguna parte del esquema: la protección es no recogerlo.
CREATE TABLE anotacion.grupo_rol (
  venue_id  uuid NOT NULL REFERENCES nucleo.venue(id),
  codigo    text NOT NULL,
  PRIMARY KEY (venue_id, codigo)
);

-- Unidad de PUBLICACIÓN (§9.4). Se ancla al recinto y se publica a la zona.
CREATE TABLE anotacion.zona (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id       uuid NOT NULL REFERENCES nucleo.venue(id),
  codigo         text NOT NULL,
  validez_desde  date NOT NULL,
  validez_hasta  date,
  UNIQUE (venue_id, codigo, validez_desde),
  CHECK (validez_hasta IS NULL OR validez_desde < validez_hasta)
);

CREATE TABLE anotacion.zona_recinto (
  zona_id        uuid NOT NULL REFERENCES anotacion.zona(id),
  recinto_id     uuid NOT NULL REFERENCES nucleo.recinto(id),
  validez_desde  date NOT NULL,
  validez_hasta  date,
  EXCLUDE USING gist (recinto_id WITH =, daterange(validez_desde, validez_hasta) WITH &&)
);

CREATE TABLE anotacion.zona_arista (
  zona_id        uuid NOT NULL REFERENCES anotacion.zona(id),
  arista_id      uuid NOT NULL REFERENCES nucleo.arista(id),
  validez_desde  date NOT NULL,
  validez_hasta  date,
  EXCLUDE USING gist (arista_id WITH =, daterange(validez_desde, validez_hasta) WITH &&)
);

CREATE INDEX ON anotacion.zona_recinto (recinto_id, validez_desde);
CREATE INDEX ON anotacion.zona_arista  (arista_id,  validez_desde);

-- Z4 — cobertura: la zonificación es una PARTICIÓN, no solo una familia disyunta.
-- El EXCLUDE da la disyunción; esto da que no falte nadie.
CREATE FUNCTION anotacion.zona_particion_completa(p_venue uuid, p_ventana daterange)
  RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT NOT EXISTS (
    SELECT 1 FROM nucleo.recinto r
    WHERE r.venue_id = p_venue
      AND NOT COALESCE((
        SELECT range_agg(daterange(zr.validez_desde, zr.validez_hasta)) @> p_ventana
        FROM anotacion.zona_recinto zr WHERE zr.recinto_id = r.id), false)
    UNION ALL
    SELECT 1 FROM nucleo.arista a
    WHERE a.venue_id = p_venue
      AND NOT COALESCE((
        SELECT range_agg(daterange(za.validez_desde, za.validez_hasta)) @> p_ventana
        FROM anotacion.zona_arista za WHERE za.arista_id = a.id), false))
$$;

CREATE FUNCTION anotacion.exige_particion_al_abrir() RETURNS trigger
  LANGUAGE plpgsql AS $$
BEGIN
  IF NOT anotacion.zona_particion_completa(
       NEW.venue_id, daterange(NEW.recogida_desde::date, NEW.recogida_hasta::date, '[]'))
  THEN
    RAISE EXCEPTION
      'no se abre la recogida de %: hay recintos o aristas fuera de toda zona en la ventana',
      NEW.codigo USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER exige_particion_al_abrir
  BEFORE INSERT OR UPDATE ON anotacion.campana
  FOR EACH ROW EXECUTE FUNCTION anotacion.exige_particion_al_abrir();

-- Z5 — congelación: repartir las zonas a mitad de recogida cambia retroactivamente la
-- unidad de publicación y con ella qué celdas superan el umbral.
CREATE FUNCTION anotacion.congela_zonas_en_recogida() RETURNS trigger
  LANGUAGE plpgsql AS $$
DECLARE
  v_desde date; v_hasta date; v_zona uuid; v_campana text; v_fila record;
BEGIN
  -- Ramas explícitas y no CASE: PL/pgSQL evalúa el CASE como una sola expresión SQL, así
  -- que referenciaría NEW.id también sobre zona_recinto, que no tiene esa columna.
  IF TG_OP = 'DELETE' THEN v_fila := OLD; ELSE v_fila := NEW; END IF;
  v_desde := v_fila.validez_desde;
  v_hasta := v_fila.validez_hasta;
  IF TG_TABLE_NAME = 'zona' THEN v_zona := v_fila.id; ELSE v_zona := v_fila.zona_id; END IF;

  SELECT c.codigo INTO v_campana
  FROM anotacion.campana c
  JOIN anotacion.zona z ON z.id = v_zona AND z.venue_id = c.venue_id
  WHERE now() < c.recogida_hasta
    AND daterange(c.recogida_desde::date, c.recogida_hasta::date, '[]')
        && daterange(v_desde, v_hasta)
  LIMIT 1;

  IF v_campana IS NOT NULL THEN
    RAISE EXCEPTION 'zonas congeladas: la campaña % tiene la recogida abierta', v_campana
      USING ERRCODE = 'check_violation';
  END IF;

  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $$;

CREATE TRIGGER congela BEFORE INSERT OR UPDATE OR DELETE ON anotacion.zona_recinto
  FOR EACH ROW EXECUTE FUNCTION anotacion.congela_zonas_en_recogida();
CREATE TRIGGER congela BEFORE INSERT OR UPDATE OR DELETE ON anotacion.zona_arista
  FOR EACH ROW EXECUTE FUNCTION anotacion.congela_zonas_en_recogida();
CREATE TRIGGER congela BEFORE UPDATE OR DELETE ON anotacion.zona
  FOR EACH ROW EXECUTE FUNCTION anotacion.congela_zonas_en_recogida();
