DROP FUNCTION IF EXISTS captura.cerrar_sesion(uuid);
DROP FUNCTION IF EXISTS captura.anotar(uuid, uuid, uuid, text, smallint, text, text[], text[], timestamptz);
DROP FUNCTION IF EXISTS captura.abrir_sesion(uuid, uuid, text, text, text);
GRANT SELECT (id) ON captura.sesion             TO espazio_captura;
GRANT SELECT (id) ON captura.anotacion_borrador TO espazio_captura;
