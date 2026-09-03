-- 0013 — La franja se valida al anotar, no al consolidar.
--
-- Antes, una anotación cuyo instante no caía en ninguna franja entraba en el borrador sin
-- protestar y hacía fallar la consolidación del lote entero: el trabajo de varias sesiones
-- a la basura por una fila. Y quien anota fuera de la rejilla es, por construcción, quien
-- entra antes de las siete, o sea el turno que PROYECTO.md §8 ya señala como el que
-- siempre acaba pagando. Falla ahora, en el INSERT, donde la persona todavía está delante
-- y puede corregir.
CREATE FUNCTION captura.exige_momento_en_franja() RETURNS trigger
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_version smallint; v_franja text;
BEGIN
  SELECT c.version_instrumento INTO v_version
  FROM captura.sesion s JOIN anotacion.campana c ON c.id = s.campana_id
  WHERE s.id = NEW.sesion_id;

  v_franja := instrumento.franja_de(v_version, NEW.momento);
  IF v_franja IS NULL THEN
    RAISE EXCEPTION 'el momento % no cae en ninguna franja del instrumento %',
      NEW.momento, v_version USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER exige_momento_en_franja
  BEFORE INSERT OR UPDATE ON captura.anotacion_borrador
  FOR EACH ROW EXECUTE FUNCTION captura.exige_momento_en_franja();
