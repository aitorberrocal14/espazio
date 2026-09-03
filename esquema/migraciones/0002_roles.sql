-- 0002 — Los cinco roles de la decisión §2.1.
-- Son objetos de clúster, no de base de datos: la creación es idempotente para que
-- aplicar el esquema en una segunda base no falle.
DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['espazio_propietario','espazio_captura','espazio_consolidacion',
                           'espazio_analisis','espazio_cualitativo']
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN', r);
    END IF;
  END LOOP;
END $$;

-- P7: espazio_analisis y espazio_consolidacion no pueden concederse al mismo principal.
-- Juntos rehacen la diferencia que la supresión complementaria impide (§2.7, R4).
CREATE OR REPLACE FUNCTION public.espazio_veta_acumulacion_de_roles()
  RETURNS event_trigger LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_auth_members ma
    JOIN pg_auth_members mc ON ma.member = mc.member
    WHERE ma.roleid = 'espazio_analisis'::regrole
      AND mc.roleid = 'espazio_consolidacion'::regrole)
  THEN
    RAISE EXCEPTION
      'espazio_analisis y espazio_consolidacion no pueden recaer en el mismo principal'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
END $$;
