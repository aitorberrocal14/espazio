# Esquema de la capa de anotación afectiva

Fecha: 2026-09-03
Estado: propuesta, pendiente de aprobación
Ámbito: fase 0
Afecta a: `esquema/` (migraciones), `datos_sinteticos/`, contrato con el esquema núcleo IMDF

---

## 1. Problema

`PROYECTO.md` §10 fija el orden de construcción: **el esquema de la anotación se cierra
antes que el backend**, porque tomarlo después significa tomarlo condicionado por lo ya
construido. Es también, junto al esquema núcleo, el sitio donde un error es caro de
deshacer: cambiar el vocabulario, el orden de los pasos, la escala de intensidad o el
modo de anclaje **invalida los datos ya recogidos** (CLAUDE.md, regla 6).

Hay además una decisión con coste de reversión infinito en una dirección: si el dato
consolidado no permite agrupar anotaciones por autor, no habrá forma de reconstruirlo
después. Esa decisión se toma aquí y ahora, no cuando haya datos.

Esta decisión cubre: tablas, campos, tipos, restricciones e índices de la capa de
anotación, el mecanismo por el que k=5 es una restricción del motor y no una norma de
uso, y el contrato que el esquema núcleo tendrá que cumplir para que esto se sostenga.

## 2. Decisión

### 2.0 Tres precisiones previas

**(a) Una anotación es un evento, no un estado.** «Toda entidad lleva validez temporal»
(§4.1) aplica a recinto, zona, ocupante o asignación: cosas que empiezan y dejan de ser
verdad. Una anotación ocurrió; no tiene intervalo que se cierre. Lo temporal entra por
otra vía y es más fuerte: la anotación referencia el **ID estable** de la entidad y el
momento aproximado, y qué versión del recinto era se resuelve por join temporal. Es lo
que hace que los vintages distintos de §9.2 no se pisen y que una reforma que parta un
recinto en dos no borre lo anotado sobre él.

**(b) k=5 no protege la nota libre.** §5.1 dice que el paso 4 «no se agrega, se lee». Un
umbral de agregación es inaplicable por definición a un texto que se lee de uno en uno.
La nota libre va a un esquema aparte, sin ninguna vista de análisis por encima, y con
revisión humana previa a cualquier publicación.

**(c) Se ancla fino y se publica grueso.** §5.3 obliga a anclar a recinto o arista; §7 y
§9.4 obligan a publicar por encima de eso. Son dos unidades distintas y el esquema las
separa: `recinto`/`arista` es la unidad de **anclaje**, `zona` es la unidad de
**publicación**. Sin esa separación, k=5 sobre 501 recintos suprime prácticamente todo.

### 2.1 Cuatro zonas, no una base de datos

La restricción se implementa como separación de privilegios en el motor, no como control
en la aplicación. Cuatro esquemas Postgres y cinco roles.

| esquema | contiene | quién puede leerlo |
|---|---|---|
| `instrumento` | catálogos versionados: vocabulario, atribuciones, franjas, traducciones | todos |
| `captura` | estado efímero de recogida: sesión, token, borradores | solo `espazio_captura` (INSERT/UPDATE) y `espazio_consolidacion` |
| `anotacion` | dato consolidado, sin clave de sesión | solo `espazio_consolidacion` y el propietario |
| `cualitativo` | notas libres | solo `espazio_cualitativo`, concedido por persona y por aprobación |
| `analisis` | **solo vistas** con el umbral incrustado | `espazio_analisis` |

| rol | privilegios |
|---|---|
| `espazio_propietario` | dueño de todo. Solo migraciones. |
| `espazio_captura` | INSERT/UPDATE en `captura.*`, SELECT en `instrumento.*`. **Sin SELECT sobre `anotacion.*`**: el formulario escribe y no puede leer lo escrito. |
| `espazio_consolidacion` | lee `captura`, escribe `anotacion` y `cualitativo`, borra `captura`. No lo usa ningún endpoint web. |
| `espazio_analisis` | USAGE en `analisis` y SELECT en sus vistas. **Cero privilegios** sobre `captura`, `anotacion` y `cualitativo`. |
| `espazio_cualitativo` | SELECT sobre `cualitativo.nota`. Se concede y se revoca por acto explícito, fuera del despliegue. |

Las vistas de `analisis` son propiedad de `espazio_propietario` y se crean con
`security_invoker = off` (el defecto), de modo que se ejecutan con los privilegios del
propietario. `espazio_analisis` puede leer el agregado y no puede llegar a la fila.

### 2.2 El umbral como restricción del motor

Cinco mecanismos, todos verificables:

1. **Sin grant no hay fila.** `espazio_analisis` no tiene privilegio alguno sobre
   `anotacion.anotacion`. No hay endpoint, export o `psql` que pueda saltárselo con ese
   rol, porque el motor rechaza la consulta antes de mirar el contenido.
2. **El umbral vive en DDL.** `instrumento.umbral_k()` es una función `IMMUTABLE` que
   devuelve `5`. **No existe ninguna tabla cuyo contenido determine el umbral**; no hay
   `UPDATE configuracion SET k = 1` posible. Cambiarlo exige una migración revisada.
3. **Gramática de celdas cerrada.** La superficie publicada es un conjunto fijo de
   vistas. No se expone `GROUP BY` arbitrario ni constructor de consultas: lo que no se
   puede pedir en combinación arbitraria no se puede diferenciar.
4. **Supresión complementaria.** Suprimir solo la celda pequeña la filtra por resta. La
   regla, aplicada dentro de cada desglose (misma campaña, zona, franja, versión):

   > Sean `c1..cm` las celdas por `grupo_rol` con recuentos `n1..nm` y total `N`.
   > `P = {i : ni ≥ 5}`, `S` su complemento.
   > Se publican las celdas de `P`, y se publica `N`, **solo si** `|S| = 0`, o bien
   > `|S| ≥ 2` **y** `Σ_{i∈S} ni ≥ 5`.
   > Si `|S| = 1`, se mueve a `S` la celda más pequeña de `P` y se reevalúa.
   > Si no se alcanza la condición, no se publica nada de ese desglose, ni el total.

   Con `{38, 2}`: se suprime también el 38; se publica `N = 40` y ninguna celda.
   Con `{38, 2, 3}`: se publica el 38 y `N = 43`; el residuo suprimido es 5 repartido
   entre dos celdas y ninguna es aislable.
5. **Resolución espacial mínima.** Ninguna vista de `analisis` expone `recinto_id` ni
   `arista_id`. La única unidad espacial publicada es `zona`.

Lo que esto **no** protege: un superusuario de Postgres puede reemplazar cualquier vista
o función. La restricción protege frente a endpoints nuevos, exports descuidados, el rol
de análisis y el olvido; no frente a un DBA decidido. No hay diseño que lo haga, y decir
lo contrario sería vender humo.

### 2.3 No hay forma de agrupar por autor en el dato consolidado

La sesión existe durante la recogida y se destruye al consolidar. Severar el
identificador **no basta**: hay dos vías por las que las sesiones se reconstituyen solas,
y las tres se cierran juntas.

| vía de reconstitución | cierre |
|---|---|
| `sesion_id` en la fila consolidada | no existe la columna; `captura.sesion` se borra en la misma transacción |
| timestamp exacto (diez anotaciones en cuatro minutos son una sesión) | el dato consolidado guarda `semana_iso` + `franja`, nunca el instante |
| orden de inserción (PK secuencial, `consolidada_en` por fila) | PK `uuid` aleatoria —**prohibida** cualquier columna `serial`/`identity`/UUIDv7—, `consolidada_en` idéntico para todo el lote, e inserción en orden aleatorizado |

Además, el **token de un solo uso** que resuelve la deduplicación no se guarda asociado a
la sesión: `captura.token` registra emisión y consumo y **no tiene FK ni columna que
referencie `captura.sesion`**. Si la guardara, y los tokens se repartieran nominalmente,
el token sería un pseudónimo con otro nombre.

La consolidación se ejecuta por **lotes de ≥ 5 sesiones**, o al cerrar la ventana de
recogida de la campaña. Consolidar sesión a sesión devolvería la agrupación por la puerta
de atrás.

### 2.4 La campaña hace del encargo institucional una restricción

§7 exige encargo institucional explícito antes de recoger una sola anotación. Eso se
implementa: toda sesión referencia una `campana`, y una campaña no existe sin referencia
documental del encargo, fecha y vigencia, con la ventana de recogida contenida en ella.
Sin campaña válida y vigente, el `INSERT` de una sesión falla.

La campaña es también el sitio donde vive el **régimen de pseudónimo**, hoy con un único
valor permitido (`'ninguno'`). Ampliar ese `CHECK` en el futuro para una campaña de panel
concreta es una migración **aditiva**: las filas históricas conservan `'ninguno'` y no se
tocan. Es la vía que pediste, y queda escrita en §6.

### 2.5 La versión del instrumento viaja con el dato

Regla 6 de CLAUDE.md dice que cambiar el vocabulario invalida lo ya recogido. Eso deja de
ser una advertencia en un documento y pasa a ser estructura:

- Cada campaña declara **una** versión de instrumento.
- Cada anotación arrastra `version_instrumento`, ligada a la de su campaña por FK
  compuesta con `ON UPDATE RESTRICT`: una campaña con anotaciones **no puede** cambiar de
  versión.
- Todas las listas cerradas (etiqueta, atribución, franja) son FK contra el catálogo de
  esa versión. Una etiqueta de v2 en una anotación de v1 no entra.
- Una versión no puede pasar a `validado` si le falta cualquier traducción es/eu.

Consecuencia deliberada: mezclar versiones en un análisis exige un acto explícito. No
puede ocurrir por descuido.

### 2.6 Esbozo del esquema

> Esto es especificación, no la migración. Los nombres, tipos y restricciones son
> vinculantes; el reparto en archivos de migración lo decide quien implemente.

#### `instrumento` — catálogos versionados

```sql
CREATE TABLE instrumento.version (
  id                smallint PRIMARY KEY,
  codigo            text NOT NULL UNIQUE,            -- 'v1-piloto-ehu'
  estado            text NOT NULL
                    CHECK (estado IN ('borrador','validado','retirado')),
  validado_en       date,
  notas_validacion  text,
  creado_en         timestamptz NOT NULL DEFAULT now(),
  CHECK (estado <> 'validado' OR validado_en IS NOT NULL)
);

CREATE TABLE instrumento.etiqueta_afectiva (
  version_id      smallint NOT NULL REFERENCES instrumento.version(id),
  codigo          text     NOT NULL,
  valencia        smallint NOT NULL CHECK (valencia   BETWEEN -2 AND 2),
  activacion      smallint NOT NULL CHECK (activacion BETWEEN -2 AND 2),
  orden_canonico  smallint NOT NULL,
  PRIMARY KEY (version_id, codigo)
);

CREATE TABLE instrumento.atribucion (
  version_id      smallint NOT NULL REFERENCES instrumento.version(id),
  codigo          text     NOT NULL,
  orden_canonico  smallint NOT NULL,
  PRIMARY KEY (version_id, codigo)
);

CREATE TABLE instrumento.franja (
  version_id  smallint NOT NULL REFERENCES instrumento.version(id),
  codigo      text     NOT NULL,
  hora_desde  time     NOT NULL,
  hora_hasta  time     NOT NULL,
  orden       smallint NOT NULL,
  PRIMARY KEY (version_id, codigo)
);

CREATE TABLE instrumento.texto (                     -- bilingüe es/eu
  version_id        smallint NOT NULL,
  ambito            text NOT NULL
                    CHECK (ambito IN ('etiqueta','atribucion','franja','intensidad')),
  codigo            text NOT NULL,
  lengua            text NOT NULL CHECK (lengua IN ('es','eu')),
  etiqueta_visible  text NOT NULL,
  PRIMARY KEY (version_id, ambito, codigo, lengua)
);

CREATE FUNCTION instrumento.umbral_k() RETURNS integer
  LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$ SELECT 5 $$;
```

`orden_canonico` existe para reproducir la lista base, **no** para presentarla: §5.2
exige aleatorizar el orden mostrado en cada sesión.

La escala `-2..2` en `valencia`/`activacion` admite el 0. Está puesta a propósito: ver
riesgo R2 sobre `indiferente`.

#### `anotacion` — campaña, catálogo social, zona, dato consolidado

```sql
CREATE TABLE anotacion.campana (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id                uuid NOT NULL REFERENCES nucleo.venue(id),
  version_instrumento     smallint NOT NULL REFERENCES instrumento.version(id),
  codigo                  text NOT NULL UNIQUE,
  encargo_referencia      text NOT NULL,
  encargo_fecha           date NOT NULL,
  encargo_vigencia_hasta  date NOT NULL,
  regimen_pseudonimo      text NOT NULL DEFAULT 'ninguno'
                          CHECK (regimen_pseudonimo IN ('ninguno')),
  recogida_desde          timestamptz NOT NULL,
  recogida_hasta          timestamptz NOT NULL,
  CHECK (recogida_desde < recogida_hasta),
  CHECK (encargo_fecha <= recogida_desde::date),
  CHECK (recogida_hasta::date <= encargo_vigencia_hasta),
  UNIQUE (id, venue_id, version_instrumento)
);

CREATE TABLE anotacion.grupo_rol (                   -- lista cerrada, por venue
  venue_id  uuid NOT NULL REFERENCES nucleo.venue(id),
  codigo    text NOT NULL,
  PRIMARY KEY (venue_id, codigo)
);

CREATE TABLE anotacion.zona (                        -- unidad de PUBLICACIÓN (§9.4)
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
  EXCLUDE USING gist (                               -- un recinto, una zona a la vez
    recinto_id WITH =,
    daterange(validez_desde, validez_hasta) WITH &&
  )
);
-- anotacion.zona_arista: idéntica, contra nucleo.arista(id).

CREATE TABLE anotacion.anotacion (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),  -- v4, NUNCA secuencial
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
  semana_iso           date     NOT NULL,            -- lunes ISO. NUNCA el instante.
  franja               text     NOT NULL,
  consolidada_en       timestamptz NOT NULL,         -- idéntico para todo el lote
  CHECK (num_nonnulls(recinto_id, arista_id) = 1),   -- §5.3: una entidad, exactamente
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
-- NO existe columna de sesión, de participante, de departamento ni de instante exacto.

CREATE TABLE anotacion.atribucion_anotacion (        -- §5.1 paso 3, multiselección
  anotacion_id         uuid     NOT NULL,
  version_instrumento  smallint NOT NULL,
  atribucion           text     NOT NULL,
  PRIMARY KEY (anotacion_id, atribucion),
  FOREIGN KEY (anotacion_id, version_instrumento)
    REFERENCES anotacion.anotacion (id, version_instrumento) ON DELETE CASCADE,
  FOREIGN KEY (version_instrumento, atribucion)
    REFERENCES instrumento.atribucion (version_id, codigo)
);
```

#### `captura` — efímero

```sql
CREATE TABLE captura.token (                         -- deduplicación, un solo uso
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campana_id    uuid NOT NULL REFERENCES anotacion.campana(id),
  emitido_en    timestamptz NOT NULL DEFAULT now(),
  consumido_en  timestamptz
);
-- Deliberadamente SIN referencia a captura.sesion: si la tuviera, sería un pseudónimo.

CREATE TABLE captura.sesion (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campana_id                uuid NOT NULL REFERENCES anotacion.campana(id),
  venue_id                  uuid NOT NULL,
  grupo_rol                 text NOT NULL,
  modo                      text NOT NULL CHECK (modo IN ('in_situ','retrospectivo')),
  lengua                    text NOT NULL CHECK (lengua IN ('es','eu')),
  permutacion_etiquetas     text[] NOT NULL,         -- §5.2: orden realmente mostrado
  permutacion_atribuciones  text[] NOT NULL,
  abierta_en                timestamptz NOT NULL DEFAULT now(),
  cerrada_en                timestamptz,
  FOREIGN KEY (venue_id, grupo_rol) REFERENCES anotacion.grupo_rol (venue_id, codigo)
);

CREATE TABLE captura.anotacion_borrador (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sesion_id    uuid NOT NULL REFERENCES captura.sesion(id) ON DELETE CASCADE,
  recinto_id   uuid REFERENCES nucleo.recinto(id),
  arista_id    uuid REFERENCES nucleo.arista(id),
  etiqueta     text     NOT NULL,
  intensidad   smallint NOT NULL CHECK (intensidad IN (1,2,3)),
  elicitacion  text     NOT NULL
               CHECK (elicitacion IN ('espontanea','cierre_positivo')),
  momento      timestamptz NOT NULL DEFAULT now(),   -- exacto aquí, y solo aquí
  CHECK (num_nonnulls(recinto_id, arista_id) = 1),
  UNIQUE (sesion_id, recinto_id),                    -- NULLS DISTINCT: no colisionan
  UNIQUE (sesion_id, arista_id)
);
-- captura.atribucion_borrador y captura.nota_borrador: análogas, ON DELETE CASCADE.
```

`permutacion_etiquetas` guarda el orden que se mostró de verdad. §5.2 exige aleatorizar
porque el primer elemento se elige desproporcionadamente; guardar la permutación es lo
único que permite **comprobar** que la aleatorización ocurrió y controlar el efecto de
posición después. Es una columna, y sin ella el requisito no es verificable.

#### `cualitativo` — notas libres

```sql
CREATE TABLE cualitativo.nota (
  anotacion_id     uuid PRIMARY KEY REFERENCES anotacion.anotacion(id),
  texto            text NOT NULL CHECK (length(btrim(texto)) > 0),
  estado_revision  text NOT NULL DEFAULT 'sin_revisar'
                   CHECK (estado_revision IN ('sin_revisar','apta','retirada')),
  revisada_en      timestamptz,
  CHECK (estado_revision = 'sin_revisar' OR revisada_en IS NOT NULL)
);
```

**Ninguna vista de `analisis` referencia este esquema.** Es una restricción estructural,
comprobable sobre `pg_depend`, no una convención.

#### `analisis` — la superficie publicada

Fase 0 publica lo mínimo para demostrar que el umbral se sostiene:

- `analisis.perfil_zona_rol` — una fila por `(campana, zona, grupo_rol, franja)` con `n`
  y las proporciones por etiqueta, tras aplicar el umbral y la supresión complementaria
  de §2.2. Proporciones, no recuentos por etiqueta.
- `analisis.perfil_zona` — la marginal sobre roles, sujeta a la misma regla.
- `analisis.cobertura_campana` — recuentos agregados por grupo de rol para medir
  completitud sin identificador persistente, con el umbral aplicado.

El motor de divergencia (§6.1), la matriz de desacople (§6.2) y la capa de traducción son
**fase 1** y no entran aquí.

#### Índices

```sql
CREATE INDEX ON anotacion.anotacion (campana_id, recinto_id);
CREATE INDEX ON anotacion.anotacion (campana_id, arista_id);
CREATE INDEX ON anotacion.anotacion (campana_id, grupo_rol, franja);   -- celda publicada
CREATE INDEX ON anotacion.anotacion (version_instrumento);
CREATE INDEX ON anotacion.atribucion_anotacion (atribucion);           -- §6.3 covariación
CREATE INDEX ON anotacion.zona_recinto (recinto_id, validez_desde);
CREATE INDEX ON captura.anotacion_borrador (sesion_id);
CREATE INDEX ON captura.sesion (campana_id) WHERE cerrada_en IS NOT NULL;
```

La restricción `EXCLUDE` de `zona_recinto` crea su propio índice GiST y exige
`btree_gist`.

### 2.7 Contrato con el esquema núcleo

Esta capa **no** define el núcleo IMDF, pero depende de él. El núcleo tendrá que ofrecer:

- `nucleo.venue(id uuid PK)`.
- `nucleo.recinto(id uuid PK)` — identidad **estable e inmutable**, sin atributos que
  cambien con el tiempo. Los códigos de plano (`4.126`, `MM3`) son alias en otra tabla,
  nunca aquí.
- `nucleo.recinto_version(recinto_id, validez_desde, validez_hasta, geometria, …)`.
- `nucleo.arista(id uuid PK)` y `nucleo.arista_version(…)`, análogas.
- Resolución `(entidad_id, fecha) → versión vigente`.

Si el núcleo hace que la anotación apunte a una **versión** en vez de a la identidad
estable, al reeditar la geometría se rompen las anotaciones. Es la parte del contrato que
no se puede negociar.

La capa de anotación es **extensión declarada sobre IMDF**, no parte de él: IMDF no tiene
concepto de anotación afectiva y su `unit` no admite estos atributos. Vive en esquemas
propios y el export IMDF se produce sin ella, de modo que sigue siendo IMDF válido.

## 3. Alternativas descartadas

**Umbral en la capa de aplicación.** Es exactamente lo que CLAUDE.md llama configuración:
cualquier endpoint nuevo, cualquier export, cualquier `psql` lo salta. El primer endpoint
que alguien añada sin acordarse es un bug de seguridad, no un descuido.

**Umbral en una tabla de configuración.** Un `UPDATE` lo derriba. Vive en DDL.

**RLS (row level security).** RLS decide visibilidad de fila; k=5 es una propiedad de un
agregado, no de una fila. Expresarlo como política con subconsulta es caro y
semánticamente falso: la fila no es el problema.

**`CHECK` sobre la tabla.** Imposible: no es un invariante de fila.

**Privacidad diferencial / ruido.** Con n de decenas o pocos cientos el ruido se come la
señal, y §8 dice que esto es cartografía cualitativa densa, no estadística inferencial.
Añadiría una apariencia de robustez que la n no tiene, que es justo lo que §8 teme.

**Constructor de consultas o `GROUP BY` arbitrario sobre las vistas.** Habilita ataques
por diferencia sin límite. De ahí la gramática de celdas cerrada.

**Anclaje polimórfico `(tipo_entidad, entidad_id)`.** Pierde integridad referencial, que
es lo caro de recuperar cuando ya hay datos. Dos FK nulables con
`num_nonnulls(...) = 1` la conservan.

**Supertipo `entidad_anotable`.** Más limpio si aparecieran más tipos anclables, pero
§5.3 fija exactamente dos y es una decisión teórica, no una lista que vaya a crecer. El
join extra no se paga.

**Atribuciones como `text[]` o `jsonb`.** Pierde la FK contra el catálogo versionado y
complica §6.3, que es precisamente cruzar atribuciones entre sí.

**`validez_desde` / `validez_hasta` en la anotación.** La anotación es un evento (§2.0a).

**Guardar el instante exacto en el dato consolidado.** Reconstituye sesiones por
proximidad temporal y anula el severamiento del identificador.

**PK `serial` o UUIDv7 en `anotacion.anotacion`.** El orden reconstituye sesiones.

**Guardar el departamento.** §7 y §9.4. La protección es **no recogerlo**: una columna
que no existe no se puede desanonimizar ni filtrar. `4.126` identifica a una persona.

**Consolidar sesión a sesión.** Devuelve la agrupación por autor a través de
`consolidada_en`.

**Vocabulario sin versionar.** Convierte la regla 6 de CLAUDE.md en una nota de
documentación. Versionado, mezclar cohortes exige un acto explícito.

## 4. Criterios de aceptación verificables

Todos sobre datos sintéticos. Ninguno requiere datos reales de anotación.

### Privilegios
1. Como `espazio_analisis`, `SELECT` sobre `anotacion.anotacion`, `captura.sesion` y
   `cualitativo.nota` falla con `42501 insufficient_privilege`.
2. Como `espazio_captura`, `INSERT` en `captura.anotacion_borrador` tiene éxito y
   `SELECT` sobre `anotacion.anotacion` falla con `42501`.
3. Como `espazio_analisis`, `SELECT` sobre cada vista de `analisis` tiene éxito.
4. Ninguna vista de `analisis` depende de `cualitativo` (consulta sobre `pg_depend`
   devuelve conjunto vacío).
5. Ninguna vista de `analisis` expone una columna `recinto_id` o `arista_id`
   (`information_schema.columns`).

### Umbral
6. Con 4 anotaciones sintéticas en `(campaña, zona, grupo_rol, franja)`,
   `analisis.perfil_zona_rol` devuelve 0 filas para esa celda. Con la quinta, devuelve 1.
7. `instrumento.umbral_k()` es `IMMUTABLE` y devuelve 5.
8. No existe ninguna columna en ninguna tabla cuyo valor determine el umbral: el valor 5
   aparece solo en definiciones de función y de vista (`pg_proc`, `pg_views`), nunca como
   dato.
9. Supresión complementaria, celdas `{38, 2}` en el mismo desglose: no se publica la
   celda de 2, no se publica la de 38 y sí se publica el total 40.
10. Supresión complementaria, celdas `{38, 2, 3}`: se publica la de 38 y el total 43; no
    se publica ninguna de las dos suprimidas.
11. Para todo par (vista, celda) de la superficie publicada, `n ≥ 5`. Test exhaustivo
    sobre un escenario sintético generado con semilla fija.

### No agrupabilidad por autor
12. Tras `consolidacion.consolidar(campana)`, ninguna columna de `anotacion.*` ni de
    `cualitativo.*` contiene ningún valor presente en los `captura.sesion.id` emitidos.
13. `captura.sesion` y `captura.anotacion_borrador` quedan vacías para esa campaña.
14. `anotacion.anotacion` no tiene columna `serial`, `identity` ni de tipo timestamp con
    resolución menor que día (`information_schema.columns`); su PK se genera con
    `gen_random_uuid()`.
15. Todas las filas consolidadas en un mismo lote comparten `consolidada_en`.
16. `captura.token` no tiene FK ni columna que referencie `captura.sesion`
    (`information_schema.table_constraints`).
17. Un lote de consolidación con menos de 5 sesiones pendientes y la ventana de recogida
    abierta no consolida nada.
18. Reconstitución: dado un escenario sintético de 30 sesiones, ninguna consulta sobre
    `anotacion.*` agrupa las filas en sus sesiones de origen mejor que el azar.

### Instrumento
19. `INSERT` de una anotación cuya etiqueta no pertenece a la versión de instrumento de
    su campaña falla por FK.
20. `UPDATE anotacion.campana SET version_instrumento = …` sobre una campaña con
    anotaciones falla por `ON UPDATE RESTRICT`.
21. `instrumento.version` no pasa a `'validado'` si falta cualquier traducción es/eu de
    cualquier etiqueta, atribución o franja.
22. `intensidad` fuera de `{1,2,3}` falla por `CHECK`.
23. `num_nonnulls(recinto_id, arista_id) = 1`: falla con ambos nulos y con ambos no
    nulos.
24. `captura.sesion.permutacion_etiquetas` es una permutación completa de las etiquetas
    de su versión, y sobre 200 sesiones sintéticas ninguna etiqueta ocupa la primera
    posición significativamente más que las demás.

### Encargo y zona
25. `INSERT` en `captura.sesion` con campaña fuera de su ventana de recogida falla
    (trigger).
26. Una campaña con `recogida_hasta` posterior a `encargo_vigencia_hasta` falla por
    `CHECK`.
27. Un recinto en dos zonas con intervalos de validez solapados falla por `EXCLUDE`.

### Viabilidad
28. `datos_sinteticos/` incluye un script determinista con semilla que, dados número de
    participantes, anotaciones por sesión, zonas y grupos de rol, informa la fracción de
    celdas `(zona × grupo_rol × franja)` que supera k=5. **Debe ejecutarse antes de
    diseñar la campaña real**, no después.

## 5. Qué queda explícitamente fuera

- El **esquema núcleo IMDF**. Aquí solo se declara el contrato de §2.7.
- El **motor de divergencia**, la matriz de desacople y la capa de traducción (§6, §6.1).
  Fase 1. Fase 0 publica perfiles y cobertura, y nada más.
- La **regla de §6.1** («nunca un número solo»). Fase 0 no emite métricas; cuando las
  emita, es contrato de la fase 1.
- **Anotación por punto libre.** Excluida por §5.3, no por olvido.
- **Escenarios y ramas** (fase 2). El anclaje por ID estable no lo impide.
- **Pseudónimo de participante y panel.** Excluidos. La vía aditiva está en §2.4 y su
  coste en R5.
- **Valores del vocabulario afectivo** y su codificación valencia/activación: el esquema
  los versiona; los valores son dato semilla pendiente de la validación de §5.2.
- **Lista de grupos de rol del piloto**: dato semilla, pendiente.
- **Definición de las zonas del piloto**: dato semilla, pendiente.
- **Horas de corte de las franjas**: propuesta de partida `manana` 07–12, `mediodia`
  12–15, `tarde` 15–19, `noche` 19–23, pendiente de confirmación. Cambiarlas después de
  recoger rompe la comparabilidad igual que cambiar el vocabulario.
- **El generador de datos sintéticos** en sí. Su especificación es otra decisión.
- **La interfaz de captura.** Aquí solo se fija qué queda registrado.

## 6. Riesgos y coste de reversión

**R1 — Que k=5 silencie el instrumento.** Si la n real deja la mayoría de celdas
`(zona × grupo_rol × franja)` por debajo de 5, se recoge y no se publica. No hay parche
técnico: bajar el umbral está prohibido y subir la n es trabajo de campo. **Mitigación:
criterio 28, ejecutado antes de diseñar la campaña.** Coste de detectarlo tarde: una
campaña entera y el encargo institucional gastado.

**R2 — `indiferente` codificada como valencia negativa es contestable.** §5.2 la lista
entre las cuatro negativas, pero es más plausiblemente valencia neutra y activación baja.
La matriz de §6.2 se apoya en el signo de la valencia, así que la clasificación decide en
qué celda cae un espacio. El esquema admite `0` para no forzar el signo, pero **la
decisión es teórica y está pendiente de la validación de §5.2**. Reversión: barata antes
de recoger, imposible después sin invalidar la cohorte.

**R3 — Semana + franja no elimina la reconstitución.** Si un grupo de rol tiene dos
participantes activos esa semana, sus anotaciones siguen co-ocurriendo. Está mitigado
porque el dato consolidado no sale de la zona restringida y solo salen agregados con
k≥5, no eliminado. Coarsenar más (mes, o eliminar la semana) mataría la variación
temporal, que §5.5 considera probablemente el hallazgo más accionable.

**R4 — La supresión complementaria solo cubre la gramática declarada.** Añadir una vista
nueva a `analisis` sin revisarla contra las existentes reabre el ataque por diferencia.
Es la parte del diseño que se degrada con el uso, y por eso el criterio 11 debe
re-ejecutarse en cada migración que toque `analisis`.

**R5 — El severamiento del identificador de sesión es irreversible por diseño.** Si en un
año resulta que hacía falta agrupar por autor, los datos ya consolidados no lo permitirán
y no habrá reconstrucción posible. **Es lo que se ha pedido explícitamente y queda
escrito aquí para que nadie lo redescubra como sorpresa.** Un panel futuro se hace por
campaña nueva, con su propia evaluación de impacto, ampliando el `CHECK` de
`regimen_pseudonimo` sin tocar el histórico.

**R6 — La restricción no protege frente a un superusuario de Postgres.** Puede reemplazar
cualquier vista o función. Protege frente a endpoints nuevos, exports descuidados, el rol
de análisis y el olvido, que es de donde vienen estas fugas en la práctica.

**R7 — El contrato del núcleo puede no cumplirse.** Si el esquema núcleo acaba anclando a
versiones en lugar de a identidades estables, esta capa se rompe entera. Coste de
reversión: alto, y crece con cada anotación recogida.

**R8 — Coste de reversión global.** Antes de recoger la primera anotación real: barato,
son migraciones sobre tablas vacías. Después: el vocabulario, la escala de intensidad, el
modo de anclaje y las franjas invalidan la cohorte; la estructura de zonas y la gramática
de celdas se pueden cambiar sin perder dato.
