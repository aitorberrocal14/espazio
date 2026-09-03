-- 0007 — Dato consolidado (decisión §2.3 y §2.7).
-- Aquí no hay forma de agrupar por autor. Las cuatro vías están cerradas:
--   sesion_id       -> la columna no existe
--   instante exacto -> se guarda semana ISO + franja
--   orden inserción -> PK uuid aleatoria, inserción en orden aleatorizado
--   etiqueta lote   -> no hay consolidada_en; la auditoría va aparte, sin vínculo
CREATE TABLE anotacion.anotacion (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campana_id           uuid     NOT NULL,
  venue_id             uuid     NOT NULL,
  version_instrumento  smallint NOT NULL,
  grupo_rol            text     NOT NULL,
  recinto_id           uuid REFERENCES nucleo.recinto(id),
  arista_id            uuid REFERENCES nucleo.arista(id),
  etiqueta             text     NOT NULL,
  intensidad           smallint NOT NULL CHECK (intensidad IN (1,2,3)),
  modo                 text     NOT NULL CHECK (modo IN ('in_situ','retrospectivo')),
  elicitacion          text     NOT NULL
                       CHECK (elicitacion IN ('espontanea','cierre_positivo')),
  lengua               text     NOT NULL CHECK (lengua IN ('es','eu')),
  posicion_etiqueta    smallint NOT NULL CHECK (posicion_etiqueta >= 1),
  semana_iso           date     NOT NULL,
  franja               text     NOT NULL,
  CHECK (num_nonnulls(recinto_id, arista_id) = 1),
  CHECK (extract(isodow from semana_iso) = 1),
  FOREIGN KEY (campana_id, venue_id, version_instrumento)
    REFERENCES anotacion.campana (id, venue_id, version_instrumento) ON UPDATE RESTRICT,
  FOREIGN KEY (venue_id, grupo_rol)
    REFERENCES anotacion.grupo_rol (venue_id, codigo),
  FOREIGN KEY (version_instrumento, etiqueta)
    REFERENCES instrumento.etiqueta_afectiva (version_id, codigo),
  FOREIGN KEY (version_instrumento, franja)
    REFERENCES instrumento.franja (version_id, codigo),
  UNIQUE (id, version_instrumento)
);

CREATE INDEX ON anotacion.anotacion (campana_id, recinto_id);
CREATE INDEX ON anotacion.anotacion (campana_id, arista_id);
CREATE INDEX ON anotacion.anotacion (campana_id, grupo_rol, franja);
CREATE INDEX ON anotacion.anotacion (version_instrumento);

CREATE TABLE anotacion.atribucion_anotacion (
  anotacion_id         uuid     NOT NULL,
  version_instrumento  smallint NOT NULL,
  atribucion           text     NOT NULL,
  PRIMARY KEY (anotacion_id, atribucion),
  FOREIGN KEY (anotacion_id, version_instrumento)
    REFERENCES anotacion.anotacion (id, version_instrumento) ON DELETE CASCADE,
  FOREIGN KEY (version_instrumento, atribucion)
    REFERENCES instrumento.atribucion (version_id, codigo)
);
CREATE INDEX ON anotacion.atribucion_anotacion (atribucion);

-- §2.2 punto 7 — el umbral cuenta PERSONAS, no anotaciones. Como el identificador de
-- sesión se destruye al consolidar, n_sesiones se calcula durante la consolidación,
-- cuando las sesiones todavía existen, y se acumula aquí. Es aditivo entre lotes porque
-- cada sesión se consolida exactamente una vez y de forma atómica.
CREATE TABLE anotacion.celda_recuento (
  campana_id     uuid    NOT NULL,
  zona_id        uuid    NOT NULL REFERENCES anotacion.zona(id),
  grupo_rol      text    NOT NULL,
  franja         text    NOT NULL,
  n_anotaciones  integer NOT NULL CHECK (n_anotaciones >= 0),
  n_sesiones     integer NOT NULL CHECK (n_sesiones    >= 0),
  PRIMARY KEY (campana_id, zona_id, grupo_rol, franja),
  CHECK (n_sesiones <= n_anotaciones)
);
CREATE INDEX ON anotacion.celda_recuento (campana_id, zona_id);

CREATE TABLE anotacion.lote_consolidacion (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campana_id     uuid NOT NULL REFERENCES anotacion.campana(id),
  momento        timestamptz NOT NULL DEFAULT now(),
  n_sesiones     integer NOT NULL,
  n_anotaciones  integer NOT NULL
);
-- No hay FK desde anotacion.anotacion hacia aquí: sería la etiqueta de lote otra vez.

-- R10 — el descarte se registra POR GRUPO DE ROL, no como total. El sesgo no es
-- aleatorio: cae sobre los roles poco poblados que PROYECTO.md §8 identifica. Que se
-- hayan descartado cuatro sesiones de limpieza y ninguna de PDI es un resultado que va
-- al informe, no una nota de auditoría.
CREATE TABLE anotacion.descarte (
  lote_id        uuid    NOT NULL REFERENCES anotacion.lote_consolidacion(id),
  campana_id     uuid    NOT NULL REFERENCES anotacion.campana(id),
  venue_id       uuid    NOT NULL,
  grupo_rol      text    NOT NULL,
  n_sesiones     integer NOT NULL CHECK (n_sesiones    > 0),
  n_anotaciones  integer NOT NULL CHECK (n_anotaciones > 0),
  PRIMARY KEY (lote_id, grupo_rol),
  FOREIGN KEY (venue_id, grupo_rol) REFERENCES anotacion.grupo_rol (venue_id, codigo)
);

-- Resolución zona <- entidad anclada, por join temporal contra la semana de la anotación.
-- Vive en la zona restringida: las vistas publicadas la usan porque se ejecutan con los
-- privilegios del propietario, pero espazio_analisis no puede leerla.
CREATE VIEW anotacion.anotacion_con_zona AS
SELECT a.*, COALESCE(zr.zona_id, za.zona_id) AS zona_id
FROM anotacion.anotacion a
LEFT JOIN anotacion.zona_recinto zr
  ON zr.recinto_id = a.recinto_id
 AND daterange(zr.validez_desde, zr.validez_hasta) @> a.semana_iso
LEFT JOIN anotacion.zona_arista za
  ON za.arista_id = a.arista_id
 AND daterange(za.validez_desde, za.validez_hasta) @> a.semana_iso;
