-- 0008 — Notas libres, en esquema propio (decisión §2.0b).
-- k=5 no las protege: §5.1 dice que se leen y no se agregan, y un umbral de agregación
-- es inaplicable a un texto que se lee de uno en uno. Ninguna vista de analisis referencia
-- este esquema, y eso es comprobable sobre pg_depend (criterio P4).
CREATE SCHEMA cualitativo;

CREATE TABLE cualitativo.nota (
  anotacion_id     uuid PRIMARY KEY REFERENCES anotacion.anotacion(id),
  texto            text NOT NULL CHECK (length(btrim(texto)) > 0),
  estado_revision  text NOT NULL DEFAULT 'sin_revisar'
                   CHECK (estado_revision IN ('sin_revisar','apta','retirada')),
  revisada_en      timestamptz,
  CHECK (estado_revision = 'sin_revisar' OR revisada_en IS NOT NULL)
);
