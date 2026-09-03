-- 0011 — Privilegios (decisión §2.1). Aquí es donde k=5 deja de ser una norma de uso.
REVOKE ALL ON SCHEMA instrumento, anotacion, captura, cualitativo, analisis, consolidacion
  FROM PUBLIC;

-- captura: escribe y no lee. Ni el dato consolidado, ni las notas, ni los agregados.
GRANT USAGE ON SCHEMA captura, instrumento TO espazio_captura;
GRANT INSERT, UPDATE ON ALL TABLES IN SCHEMA captura TO espazio_captura;
GRANT SELECT ON ALL TABLES IN SCHEMA instrumento TO espazio_captura;
-- HUECO DE LA ESPECIFICACIÓN. La decisión dice «INSERT/UPDATE en captura.*, sin SELECT»,
-- pero en Postgres un UPDATE con WHERE y un INSERT ... RETURNING exigen SELECT sobre las
-- columnas que referencian: sin esto el rol no puede ni cerrar una sesión ni recuperar el
-- id de lo que acaba de insertar, y la zona de captura queda inservible. Se concede el
-- mínimo que lo arregla: SELECT sobre la columna `id` y nada más. La propiedad que
-- buscaba la decisión se mantiene —el formulario no puede leer lo que escribió—; lo que
-- puede es referirse a filas cuyo identificador ya tiene.
GRANT SELECT (id) ON captura.sesion            TO espazio_captura;
GRANT SELECT (id) ON captura.anotacion_borrador TO espazio_captura;

-- consolidación: mueve el dato de una zona a otra y borra la de origen.
GRANT USAGE ON SCHEMA captura, anotacion, cualitativo, instrumento, consolidacion
  TO espazio_consolidacion;
GRANT SELECT, DELETE ON ALL TABLES IN SCHEMA captura TO espazio_consolidacion;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA anotacion TO espazio_consolidacion;
GRANT SELECT, INSERT ON cualitativo.nota TO espazio_consolidacion;
GRANT SELECT ON ALL TABLES IN SCHEMA instrumento TO espazio_consolidacion;
GRANT EXECUTE ON FUNCTION consolidacion.consolidar(uuid, boolean) TO espazio_consolidacion;

-- análisis: USAGE sobre analisis y SELECT sobre sus vistas. Nada más. Ni una fila.
GRANT USAGE ON SCHEMA analisis TO espazio_analisis;
GRANT SELECT ON analisis.perfil_zona_rol, analisis.perfil_zona TO espazio_analisis;

-- cualitativo: se concede y se revoca por acto explícito, fuera del despliegue.
GRANT USAGE ON SCHEMA cualitativo TO espazio_cualitativo;
GRANT SELECT ON cualitativo.nota TO espazio_cualitativo;
