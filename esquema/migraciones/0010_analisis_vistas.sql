-- 0010 — Superficie publicada (decisión §2.2 y §2.7).
-- El perfil se emite sobre los ejes de valencia y activación, NUNCA sobre el desglose de
-- las ocho etiquetas: ocho proporciones junto a n son ocho recuentos exactos, y con n=5
-- una proporción de 0,2 es una persona.

-- Cálculo compartido, en la zona restringida. Las vistas de analisis son propiedad del
-- propietario y se ejecutan con sus privilegios (security_invoker apagado, que es el
-- defecto), así que pueden leer esto sin que espazio_analisis pueda.
CREATE VIEW anotacion.celda_desglosada AS
WITH celda AS (
  SELECT a.campana_id, a.zona_id, a.grupo_rol, a.franja,
         count(*)::integer            AS n_anotaciones,
         cr.n_sesiones,
         round(avg(e.valencia),   2)  AS valencia_media,
         round(avg(e.activacion), 2)  AS activacion_media,
         round(avg(a.intensidad), 2)  AS intensidad_media
  FROM anotacion.anotacion_con_zona a
  JOIN instrumento.etiqueta_afectiva e
    ON e.version_id = a.version_instrumento AND e.codigo = a.etiqueta
  JOIN anotacion.celda_recuento cr
    ON cr.campana_id = a.campana_id AND cr.zona_id = a.zona_id
   AND cr.grupo_rol  = a.grupo_rol  AND cr.franja  = a.franja
  GROUP BY a.campana_id, a.zona_id, a.grupo_rol, a.franja, cr.n_sesiones
), marcada AS (
  -- Umbral doble: cinco anotaciones Y cinco personas. Contarlo solo sobre anotaciones
  -- dejaría publicar una celda de cinco que es una única respondente (§2.2 punto 7).
  SELECT c.*, (c.n_anotaciones >= instrumento.umbral_k()
               AND c.n_sesiones >= instrumento.umbral_k()) AS pasa
  FROM celda c
), ventana AS (
  SELECT m.*,
         count(*)                    FILTER (WHERE NOT m.pasa) OVER w AS n_suprimidas,
         COALESCE(sum(m.n_anotaciones) FILTER (WHERE NOT m.pasa) OVER w, 0) AS masa_suprimida,
         count(*)                    FILTER (WHERE m.pasa)     OVER w AS n_publicables,
         CASE WHEN m.pasa THEN row_number() OVER (
           PARTITION BY m.campana_id, m.zona_id, m.franja, m.pasa
           ORDER BY m.n_anotaciones, m.grupo_rol) END AS orden_publicable
  FROM marcada m
  WINDOW w AS (PARTITION BY m.campana_id, m.zona_id, m.franja)
)
-- Supresión complementaria. Suprimir solo la celda pequeña la filtra por resta, así que
-- o el residuo suprimido reparte al menos k entre dos celdas, o se sacrifica además la
-- menor de las publicables. Si no se llega, no sale nada del desglose, ni el total.
SELECT v.*,
       CASE
         WHEN v.n_suprimidas = 0 THEN 0
         WHEN v.n_suprimidas >= 2 AND v.masa_suprimida >= instrumento.umbral_k() THEN 0
         WHEN v.n_publicables >= 1 THEN 1
         ELSE NULL
       END AS sacrificadas
FROM ventana v;

CREATE SCHEMA analisis;

CREATE VIEW analisis.perfil_zona_rol AS
SELECT d.campana_id, d.zona_id, d.grupo_rol, d.franja,
       d.n_anotaciones, d.valencia_media, d.activacion_media, d.intensidad_media
FROM anotacion.celda_desglosada d
WHERE d.pasa AND d.sacrificadas IS NOT NULL AND d.orden_publicable > d.sacrificadas;

-- Marginal sobre grupo_rol. La franja y la zona van SIEMPRE en la clave: con dos ejes
-- marginalizables a la vez la supresión habría que resolverla sobre el retículo completo.
CREATE VIEW analisis.perfil_zona AS
SELECT d.campana_id, d.zona_id, d.franja,
       sum(d.n_anotaciones)::integer AS n_anotaciones,
       round(sum(d.valencia_media   * d.n_anotaciones) / sum(d.n_anotaciones), 2) AS valencia_media,
       round(sum(d.activacion_media * d.n_anotaciones) / sum(d.n_anotaciones), 2) AS activacion_media,
       round(sum(d.intensidad_media * d.n_anotaciones) / sum(d.n_anotaciones), 2) AS intensidad_media
FROM anotacion.celda_desglosada d
WHERE d.sacrificadas IS NOT NULL
GROUP BY d.campana_id, d.zona_id, d.franja
HAVING sum(d.n_anotaciones) >= instrumento.umbral_k()
   AND sum(d.n_sesiones)    >= instrumento.umbral_k();
