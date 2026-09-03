REVOKE EXECUTE ON FUNCTION consolidacion.consolidar(uuid, boolean)
  FROM espazio_consolidacion;
REVOKE ALL ON ALL TABLES IN SCHEMA captura, instrumento, anotacion, cualitativo, analisis
  FROM espazio_captura, espazio_consolidacion, espazio_analisis, espazio_cualitativo;
REVOKE ALL ON SCHEMA captura, instrumento, anotacion, cualitativo, analisis, consolidacion
  FROM espazio_captura, espazio_consolidacion, espazio_analisis, espazio_cualitativo;
