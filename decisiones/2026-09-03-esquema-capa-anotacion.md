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
6. **Resolución afectiva mínima.** El perfil publicado se emite sobre los ejes de
   **valencia y activación**, nunca sobre el desglose de las ocho etiquetas. Publicar `n`
   junto a ocho proporciones es publicar ocho recuentos exactos: con `n = 5`, una
   proporción de 0,2 es una persona. La granularidad de etiqueta se almacena y se explota
   en análisis interno dentro de la zona restringida; no sale por `analisis`.
7. **El umbral cuenta personas, no anotaciones.** Una sola persona que anote cinco
   espacios de una misma zona produce una celda de `n = 5` que es una única respondente:
   el umbral, contado sobre anotaciones, no protege ahí nada. `analisis` exige
   `n_sesiones ≥ 5` **además** de `n_anotaciones ≥ 5`. Como el identificador de sesión se
   destruye al consolidar, `n_sesiones` se calcula **durante** la consolidación —cuando
   las sesiones todavía existen— y se acumula en `anotacion.celda_recuento`; es aditivo
   entre lotes porque cada sesión se consolida exactamente una vez. Es más estricto que la
   letra de §7, que habla de anotaciones, y por eso no la contradice.

Lo que esto **no** protege: un superusuario de Postgres puede reemplazar cualquier vista
o función. La restricción protege frente a endpoints nuevos, exports descuidados, el rol
de análisis y el olvido; no frente a un DBA decidido. No hay diseño que lo haga, y decir
lo contrario sería vender humo.

### 2.3 No hay forma de agrupar por autor en el dato consolidado

La sesión existe durante la recogida y se destruye al consolidar. Severar el
identificador **no basta**: hay cuatro vías por las que las sesiones se reconstituyen
solas, y se cierran todas juntas.

| vía de reconstitución | cierre |
|---|---|
| `sesion_id` en la fila consolidada | no existe la columna; `captura.sesion` se borra en la misma transacción |
| timestamp exacto (diez anotaciones en cuatro minutos son una sesión) | el dato consolidado guarda `semana_iso` + `franja`, nunca el instante |
| orden de inserción (PK secuencial) | PK `uuid` aleatoria —**prohibida** cualquier columna `serial`/`identity`/UUIDv7— e inserción en orden aleatorizado |
| etiqueta de lote (`consolidada_en` por fila) | **la columna no existe.** Un lote agrupa más fino que semana + franja, y conservarla como fecha devolvería por la puerta de atrás la resolución diaria que se acaba de quitar. La auditoría vive en `anotacion.lote_consolidacion`, sin vínculo con las filas |
| grupo compuesto por una sola sesión | la consolidación no emite ningún grupo `(campana, venue, grupo_rol, semana_iso, franja)` que provenga de una sola sesión |

Además, el **token de un solo uso** que resuelve la deduplicación no se guarda asociado a
la sesión: `captura.token` registra emisión y consumo y **no tiene FK ni columna que
referencie `captura.sesion`**. Si la guardara, y los tokens se repartieran nominalmente,
el token sería un pseudónimo con otro nombre.

La consolidación se ejecuta por **lotes de ≥ 5 sesiones**, o al cerrar la ventana de
recogida de la campaña. Consolidar sesión a sesión devolvería la agrupación por la puerta
de atrás.

**Grupos unitarios.** Si una sesión es la única de su grupo `(campana, venue, grupo_rol,
semana_iso, franja)`, consolidarla deja en la zona restringida un grupo que **es** esa
sesión, íntegra. Esas anotaciones se **retienen** en `captura` hasta que otra sesión entre
en su grupo; si al cerrar la campaña siguen solas, **no se consolidan y se descartan**, y
el descarte queda registrado **por grupo de rol** en `anotacion.descarte`. Se registra así
y no como total porque el descarte no es neutral: cae sobre los roles con menos
participación, que son justo los que §8 identifica como estructuralmente
infrarrepresentados. Es pérdida de dato, es visible, va al informe, y es preferible a
conservar una sesión reconstruible.

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

### 2.6 La posición mostrada viaja con la anotación, y §5.2 cambia con ella

La anotación consolidada lleva `posicion_etiqueta`: el índice, base 1, en el que apareció
la etiqueta elegida dentro de la lista que se mostró. Sin arrastrarlo, `permutacion_*` se
destruye con la sesión y el control del efecto de posición se vuelve imposible después de
consolidar.

Ese ordinal solo es seguro si el orden se aleatoriza **por anotación**. Con la
aleatorización por sesión que decía §5.2 en su redacción original, todas las anotaciones
de una sesión comparten una única correspondencia etiqueta → posición, y esa aplicación
parcial es una huella: dentro de un grupo `(campana, venue, grupo_rol, semana_iso,
franja)` se pueden agrupar por consistencia de esa correspondencia y reconstruir sesiones,
que es exactamente lo que §2.3 existe para impedir.

**Decidido y aprobado el 2026-09-03: se aleatoriza en cada anotación.** `PROYECTO.md` §5.2
queda modificado en consecuencia, antes de escribir código, como exige su propio
preámbulo. El cambio no invalida datos porque todavía no hay ninguno; después de la
primera campaña sí los invalidaría. Metodológicamente además es preferible: promedia el
sesgo de presentación en lugar de fijarlo durante toda la sesión.

Queda descartada la alternativa de degradar el campo a `en_primera_posicion boolean`
manteniendo la aleatorización por sesión.

**Consecuencia sobre el esquema:** si el orden se sortea por anotación, `permutacion_etiquetas`
y `permutacion_atribuciones` **dejan de ser campos de sesión** y bajan a
`captura.anotacion_borrador`. Lo que sobrevive a la consolidación sigue siendo solo el
ordinal de la etiqueta elegida.

La posición de las **atribuciones** se registra durante la captura pero no se arrastra a la
anotación consolidada: en una multiselección el efecto de posición es otra pregunta y no
está planteada. Queda anotada como pendiente en §5.

### 2.7 Esbozo del esquema

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

-- La zonificación es una PARTICIÓN, no solo una familia disyunta. El EXCLUDE de arriba
-- da la disyunción; la cobertura y la congelación son las otras dos mitades:

CREATE FUNCTION anotacion.zona_particion_completa(p_venue uuid, p_ventana daterange)
  RETURNS boolean LANGUAGE sql STABLE AS $$ /* ningún recinto ni arista del venue queda
  fuera de toda zona en ningún instante de p_ventana */ $$;

-- Trigger en anotacion.campana: no se abre la recogida si la partición no cubre el venue
--   durante toda la ventana.
-- Trigger en captura.anotacion_borrador: la entidad anclada debe pertenecer a una zona
--   vigente en ese momento. Cierra el hueco de un recinto añadido a mitad de campaña, que
--   de otro modo produciría anotaciones estructuralmente impublicables.
-- CONGELACIÓN — trigger en anotacion.zona, zona_recinto y zona_arista: se rechaza
--   cualquier INSERT/UPDATE/DELETE cuya validez solape la ventana de recogida de una
--   campaña abierta. Repartir las zonas a mitad de recogida cambia retroactivamente la
--   unidad de publicación y, con ella, qué celdas superan el umbral.

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
  posicion_etiqueta    smallint NOT NULL CHECK (posicion_etiqueta >= 1),  -- §2.6
  semana_iso           date     NOT NULL,            -- lunes ISO. NUNCA el instante.
  franja               text     NOT NULL,
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
-- NO existe columna de sesión, de participante, de departamento, de instante exacto
-- ni de lote de consolidación.

CREATE TABLE anotacion.celda_recuento (              -- §2.2 punto 7: el umbral cuenta personas
  campana_id     uuid    NOT NULL,
  zona_id        uuid    NOT NULL REFERENCES anotacion.zona(id),
  grupo_rol      text    NOT NULL,
  franja         text    NOT NULL,
  n_anotaciones  integer NOT NULL CHECK (n_anotaciones >= 0),
  n_sesiones     integer NOT NULL CHECK (n_sesiones    >= 0),
  PRIMARY KEY (campana_id, zona_id, grupo_rol, franja),
  CHECK (n_sesiones <= n_anotaciones)
);
-- Se acumula por lote durante la consolidación, mientras las sesiones aún existen.
-- Guarda recuentos, nunca identificadores.

CREATE TABLE anotacion.lote_consolidacion (          -- auditoría sin etiqueta por fila
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campana_id     uuid NOT NULL REFERENCES anotacion.campana(id),
  momento        timestamptz NOT NULL DEFAULT now(),
  n_sesiones     integer NOT NULL,
  n_anotaciones  integer NOT NULL
);
-- No existe FK desde anotacion.anotacion hacia aquí: sería la etiqueta de lote otra vez.

CREATE TABLE anotacion.descarte (                    -- §2.3 y R10: quién se queda fuera
  lote_id        uuid    NOT NULL REFERENCES anotacion.lote_consolidacion(id),
  campana_id     uuid    NOT NULL REFERENCES anotacion.campana(id),
  venue_id       uuid    NOT NULL,
  grupo_rol      text    NOT NULL,
  n_sesiones     integer NOT NULL CHECK (n_sesiones    > 0),
  n_anotaciones  integer NOT NULL CHECK (n_anotaciones > 0),
  PRIMARY KEY (lote_id, grupo_rol),
  FOREIGN KEY (venue_id, grupo_rol) REFERENCES anotacion.grupo_rol (venue_id, codigo)
);
-- El descarte se registra POR GRUPO DE ROL, no como total. Que se hayan descartado cuatro
-- sesiones de limpieza y ninguna de PDI es un resultado, no una nota de auditoría: el
-- sesgo no es aleatorio. Vive en la zona restringida; llevarlo a un informe es una
-- decisión humana, no una publicación automática.

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
  permutacion_etiquetas     text[] NOT NULL,          -- §5.2: se sortea POR ANOTACIÓN
  permutacion_atribuciones  text[] NOT NULL,
  CHECK (num_nonnulls(recinto_id, arista_id) = 1),
  UNIQUE (sesion_id, recinto_id, elicitacion),       -- NULLS DISTINCT: no colisionan
  UNIQUE (sesion_id, arista_id, elicitacion)
);
-- captura.atribucion_borrador y captura.nota_borrador: análogas, ON DELETE CASCADE.
```

`permutacion_etiquetas` guarda el orden que se mostró de verdad, y vive en el borrador
porque el sorteo es por anotación (§2.6). §5.2 exige aleatorizar porque el primer elemento
se elige desproporcionadamente; guardar la permutación es lo único que permite
**comprobar** que la aleatorización ocurrió. Lo que sobrevive a la consolidación es
`anotacion.posicion_etiqueta`.

La unicidad incluye `elicitacion` a propósito: §5.5 cierra la sesión preguntando «¿hay
algún sitio donde estés a gusto?», y la persona puede perfectamente nombrar un espacio que
ya anotó espontáneamente. Sin `elicitacion` en la clave, el esquema prohibiría justo la
respuesta que §5.5 va a buscar.

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

Fase 0 publica lo mínimo para demostrar que el umbral se sostiene, y lo publica sobre los
**ejes de valencia y activación**, nunca sobre el desglose de etiquetas:

- `analisis.perfil_zona_rol` — una fila por `(campana, zona, grupo_rol, franja)` con
  `n_anotaciones`, `valencia_media`, `activacion_media` e `intensidad_media`, tras aplicar
  el umbral doble de §2.2 (puntos 6 y 7) y la supresión complementaria.
- `analisis.perfil_zona` — la marginal sobre `grupo_rol`, sujeta a la misma regla.

Y nada más.

**Por qué no se publica el desglose por etiqueta.** Ocho proporciones junto a `n` son ocho
recuentos exactos: con `n = 5`, una proporción de 0,2 es una persona diciendo `agobiante`
sobre esa zona. Los dos ejes reducen el soporte publicado de ocho categorías nominales a
dos escalas ordenadas cortas, y publican sumas en lugar de la distribución. La
granularidad de etiqueta **se almacena** en `anotacion.anotacion` y se explota en análisis
interno dentro de la zona restringida, por la vía de aprobación explícita de la regla 4 de
CLAUDE.md; no sale por `analisis` ni alimenta ninguna vista.

**Por qué tampoco se publica dispersión dentro de la celda.** §6 pide divergencia *entre*
grupos, que se calcula a partir de los perfiles de grupo; la dispersión *dentro* de la
celda no hace falta ni para §6.1 ni para §6.2, y con `n` pequeña la terna (n, media,
varianza) sobre un soporte discreto corto identifica el multiconjunto con frecuencia. Se
omite por eso, no por olvido.

**Por qué `cobertura_campana` sale de la superficie publicada.** Era una marginal sobre
zona y franja a la vez: el total por rol menos sus celdas publicadas devuelve la suma de
sus celdas suprimidas, y con una sola suprimida la devuelve exacta. Es decir, el segundo
eje de marginalización que el punto 3 de §2.2 y R4 dicen evitar, colado en la propia
superficie que los invoca. La cobertura de campaña es una necesidad **operativa** de quien
gestiona la recogida, no un resultado de análisis: vive en la zona restringida y la lee
`espazio_consolidacion`. De ahí se sigue una regla de separación de funciones que no es
opcional: **`espazio_analisis` y `espazio_consolidacion` no pueden concederse al mismo
principal**, porque juntos rehacen la diferencia.

**La franja va siempre en la clave.** Fase 0 no publica ninguna marginal sobre franja, y
por eso el único eje de marginalización de la superficie es `grupo_rol`, que es
exactamente lo que cubre la regla de §2.2. Con dos ejes marginalizables a la vez, la
supresión habría que resolverla sobre el retículo completo de agregaciones y la regla de
§2.2 se quedaría corta. **Añadir después una vista marginal sobre franja no es añadir una
vista: obliga a reescribir la regla de supresión.**

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
CREATE INDEX ON anotacion.celda_recuento (campana_id, zona_id);
CREATE INDEX ON captura.anotacion_borrador (sesion_id);
CREATE INDEX ON captura.sesion (campana_id) WHERE cerrada_en IS NOT NULL;
```

La restricción `EXCLUDE` de `zona_recinto` crea su propio índice GiST y exige
`btree_gist`.

### 2.8 Contrato con el esquema núcleo

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

**Consolidar sesión a sesión.** Devuelve la agrupación por autor a través del lote.

**Publicar el desglose por las ocho etiquetas.** Con `n` al lado son recuentos exactos, y
con `n = 5` un recuento de 1 es una persona. Los ejes de valencia y activación publican lo
que §6.2 necesita —el signo y el nivel de activación— sin publicar la distribución.

**Publicar `cobertura_campana` con supresión coordinada.** Se podría, resolviendo la
supresión sobre el retículo completo de agregaciones. Es trabajo de fase 1 como mínimo, y
meterlo en fase 0 para una cifra operativa que no es un resultado de análisis es cambiar
riesgo por comodidad. Fuera de la superficie publicada.

**Conservar `consolidada_en` como fecha.** Restauraría por la puerta de atrás la
resolución diaria que `semana_iso` acaba de quitar. Si el lote no puede etiquetar la fila,
tampoco puede hacerlo su fecha.

**Contar el umbral sobre anotaciones y no sobre sesiones.** Una persona que anota cinco
espacios de una zona produce una celda de cinco que es una sola respondente. La letra de
§7 dice anotaciones; contar sesiones es más estricto, así que la cumple.

**El índice de Rand ajustado como prueba de no reconstitución.** Mide el caso medio y
esconde justo el caso que importa: un grupo formado por una única sesión queda diluido en
una media que sale buena. La prueba es de peor caso (criterio A6).

**Vocabulario sin versionar.** Convierte la regla 6 de CLAUDE.md en una nota de
documentación. Versionado, mezclar cohortes exige un acto explícito.

## 4. Criterios de aceptación verificables

Todos sobre datos sintéticos. Ninguno requiere datos reales de anotación.

Los criterios llevan identificador estable en vez de número correlativo, para que añadir
uno no rompa las referencias del resto del documento. Equivalencias con la revisión
anterior: **V1** era el criterio 28, **A6** sustituye al 18 y **U8** era el 11.

### Privilegios (P)

- **P1.** Como `espazio_analisis`, `SELECT` sobre `anotacion.anotacion`,
  `anotacion.celda_recuento`, `captura.sesion` y `cualitativo.nota` falla con
  `42501 insufficient_privilege`.
- **P2.** Como `espazio_captura`, `INSERT` en `captura.anotacion_borrador` tiene éxito y
  `SELECT` sobre `anotacion.anotacion` falla con `42501`.
- **P3.** Como `espazio_analisis`, `SELECT` sobre cada vista de `analisis` tiene éxito.
- **P4.** Ninguna vista de `analisis` depende de `cualitativo` (`pg_depend` devuelve
  conjunto vacío).
- **P5.** Ninguna vista de `analisis` expone columna `recinto_id` ni `arista_id`.
- **P6.** Ninguna vista de `analisis` expone la etiqueta afectiva ni recuento alguno por
  etiqueta: no hay columna cuyo nombre o dependencia remita a
  `instrumento.etiqueta_afectiva` (`information_schema.columns` + `pg_depend`).
- **P7.** Ningún principal es miembro simultáneo de `espazio_analisis` y
  `espazio_consolidacion` (`pg_auth_members`, recursivo).

### Umbral (U)

- **U1.** Con 4 anotaciones de 4 sesiones distintas en `(campaña, zona, grupo_rol,
  franja)`, `analisis.perfil_zona_rol` devuelve 0 filas para esa celda. Con la quinta,
  procedente de una quinta sesión, devuelve 1.
- **U2.** Con 5 anotaciones procedentes de solo 4 sesiones, devuelve 0 filas.
- **U3.** Con 8 anotaciones procedentes de 2 sesiones, devuelve 0 filas.
- **U4.** `instrumento.umbral_k()` es `IMMUTABLE` y devuelve 5.
- **U5.** El umbral no es dato: el valor aparece en `pg_proc` y `pg_views`, y en ninguna
  columna de ninguna tabla.
- **U6.** Supresión complementaria con celdas `{38, 2}`: no se publica la de 2, no se
  publica la de 38, y sí se publica el total 40.
- **U7.** Supresión complementaria con celdas `{38, 2, 3}`: se publica la de 38 y el total
  43; no se publica ninguna de las dos suprimidas.
- **U8.** Para todo par (vista, celda) de la superficie publicada, `n_anotaciones ≥ 5`
  **y** `n_sesiones ≥ 5`. Exhaustivo sobre un escenario sintético con semilla fija.
- **U9.** Toda vista de `analisis` lleva `zona_id` y `franja` entre sus columnas de
  agrupación: no existe ninguna que marginalice sobre el eje espacial ni sobre el
  temporal. Es lo que mantiene en un solo eje la marginalización que cubre §2.2.

### No agrupabilidad por autor (A)

- **A1.** Tras consolidar, ninguna columna de `anotacion.*` ni de `cualitativo.*` contiene
  ningún valor presente en los `captura.sesion.id` emitidos.
- **A2.** Cerrada la ventana de recogida y ejecutada la consolidación final,
  `captura.sesion` y `captura.anotacion_borrador` quedan vacías para esa campaña.
- **A3.** `anotacion.anotacion` no tiene columna `serial` ni `identity`, ni columna de
  tipo `timestamp`/`timestamptz`, ni columna de fecha con resolución menor que
  `semana_iso`. Su PK se genera con `gen_random_uuid()`.
- **A4.** No existe columna `consolidada_en` ni ninguna otra etiqueta de lote en
  `anotacion.anotacion`, y no existe FK ni columna que relacione
  `anotacion.lote_consolidacion` con filas individuales.
- **A5.** `captura.token` no tiene FK ni columna que referencie `captura.sesion`.
- **A6.** **Peor caso, no caso medio.** Sobre un escenario sintético con semilla fija y
  verdad conocida por el generador, **ningún** grupo `(campana_id, venue_id, grupo_rol,
  semana_iso, franja)` presente en `anotacion.anotacion` procede de una sola sesión.
- **A7.** `anotacion.posicion_etiqueta` coincide con el índice de la etiqueta elegida
  dentro de `captura.anotacion_borrador.permutacion_etiquetas` de **esa anotación**.
  `captura.sesion` no tiene columna de permutación: el sorteo es por anotación (§2.6).
- **A8.** Un lote con menos de 5 sesiones pendientes y la ventana de recogida abierta no
  consolida nada, y las anotaciones retenidas siguen en `captura`.
- **A9.** Las descartadas al cierre quedan en `anotacion.descarte` **desglosadas por grupo
  de rol**: un escenario sintético con 4 sesiones unitarias de `limpieza` y ninguna de
  `pdi` produce una fila para `limpieza` con `n_sesiones = 4` y ninguna para `pdi`. La
  suma de `anotacion.descarte` sobre un lote es el total descartado en ese lote.

### Instrumento (I)

- **I1.** `INSERT` de una anotación cuya etiqueta no pertenece a la versión de instrumento
  de su campaña falla por FK.
- **I2.** `UPDATE anotacion.campana SET version_instrumento = …` sobre una campaña con
  anotaciones falla por `ON UPDATE RESTRICT`.
- **I3.** `instrumento.version` no pasa a `'validado'` si falta cualquier traducción es/eu
  de cualquier etiqueta, atribución o franja.
- **I4.** `intensidad` fuera de `{1,2,3}` falla por `CHECK`.
- **I5.** `num_nonnulls(recinto_id, arista_id) = 1`: falla con ambos nulos y con ambos no
  nulos.
- **I6.** `captura.anotacion_borrador.permutacion_etiquetas` es una permutación completa
  de las etiquetas de su versión, y sobre 200 **anotaciones** sintéticas ninguna etiqueta
  ocupa la primera posición significativamente más que las demás. Dos anotaciones de una
  misma sesión no comparten permutación más a menudo que dos de sesiones distintas: es lo
  que impide que la posición sirva para reagrupar (§2.6).
- **I7.** Dentro de una misma sesión, una segunda anotación sobre el mismo recinto con la
  misma `elicitacion` falla por `UNIQUE`; con `elicitacion` distinta —`cierre_positivo`
  frente a `espontanea`— tiene éxito. Es la respuesta que §5.5 va a buscar al cerrar.

### Encargo y zona (Z)

- **Z1.** `INSERT` en `captura.sesion` con campaña fuera de su ventana de recogida falla.
- **Z2.** Una campaña con `recogida_hasta` posterior a `encargo_vigencia_hasta` falla por
  `CHECK`.
- **Z3.** Un recinto en dos zonas con intervalos de validez solapados falla por `EXCLUDE`.
- **Z4.** **Cobertura.** No se puede abrir la recogida de una campaña si algún recinto o
  alguna arista del venue queda fuera de toda zona en algún instante de la ventana.
- **Z5.** **Congelación.** Cualquier `INSERT`/`UPDATE`/`DELETE` sobre `anotacion.zona`,
  `zona_recinto` o `zona_arista` cuya validez solape la ventana de recogida de una campaña
  abierta falla.
- **Z6.** `INSERT` en `captura.anotacion_borrador` sobre una entidad que no pertenece a
  ninguna zona vigente en ese momento falla.

### Viabilidad (V)

- **V1.** `datos_sinteticos/` incluye un script determinista con semilla que, dados número
  de participantes, anotaciones por sesión, zonas y grupos de rol, informa la fracción de
  celdas `(zona × grupo_rol × franja)` que supera k=5. **Debe ejecutarse antes de diseñar
  la campaña real**, no después.

## 5. Qué queda explícitamente fuera

- El **esquema núcleo IMDF**. Aquí solo se declara el contrato de §2.8.
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
- **`cobertura_campana` como vista publicada.** Sale de `analisis` y queda en la zona
  restringida como cifra operativa.
- **La dispersión dentro de la celda** y el desglose por etiqueta en la superficie
  publicada. Se almacenan; no se publican.
- **La posición mostrada de las atribuciones.** Se registra durante la captura pero no se
  arrastra a la anotación consolidada. En una multiselección el efecto de posición es otra
  pregunta, y no está planteada.
- **La entrevista para roles poco poblados.** Apuntada como mitigación de R10 y como la
  única vía realista para los grupos que R9 deja permanentemente por debajo del umbral. Es
  material cualitativo, no capa de anotación, y diseñarla es otra decisión.
- **El generador de datos sintéticos** en sí. Su especificación es otra decisión.
- **La interfaz de captura.** Aquí solo se fija qué queda registrado.

## 6. Riesgos y coste de reversión

**R1 — Que k=5 silencie el instrumento.** Si la n real deja la mayoría de celdas
`(zona × grupo_rol × franja)` por debajo de 5, se recoge y no se publica. No hay parche
técnico: bajar el umbral está prohibido y subir la n es trabajo de campo. **Mitigación:
criterio 28 —ahora V1—, ejecutado antes de diseñar la campaña.** Coste de detectarlo tarde: una
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
El caso concreto que hay que vigilar es una **marginal sobre franja**: introduciría un
segundo eje de marginalización y la regla de §2.2, escrita para uno solo, dejaría de
cubrir la superficie. Ya ocurrió una vez: `cobertura_campana` era exactamente eso, y
estaba dentro de la superficie que invoca esta regla. Es la parte del diseño que se
degrada con el uso, y por eso los criterios U8 y U9 deben re-ejecutarse en cada migración
que toque `analisis`.

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

**R9 — El doble umbral restringe cuántas zonas y cuántas franjas puede tener el diseño.**
No es solo que estreche lo publicable: fija un techo aritmético que ninguna decisión de
esquema mueve, y conviene saberlo antes de ejecutar V1 y no después.

Exigir `n_sesiones ≥ 5` por `(zona × grupo_rol × franja)` significa que cada grupo de rol
necesita **del orden de 15 a 20 respondentes activos por zona** para publicar: con cuatro
franjas y reparto uniforme harían falta 20, y con el reparto real —la gente anota en una o
dos franjas, no en las cuatro— siguen haciendo falta 15 para que publiquen más de una.

De ahí sale el techo. Con `P` respondentes activos de un grupo de rol, cada uno anotando
`z` zonas distintas, `Z` zonas y `F` franjas:

> `Z ≤ P · z / (5F)`

Con `P = 60`, `z = 5` y `F = 4`: **como mucho 15 zonas**. Con un grupo poco poblado,
`P = 12`: **tres zonas**, y eso suponiendo reparto uniforme, que no ocurre.

Y aquí está lo que de verdad muerde: **la divergencia entre roles de §6.1 exige que pasen
el umbral los dos perfiles que se comparan**, así que quien manda no es el grupo grande
sino el pequeño. El hallazgo del proyecto —dónde el mismo espacio significa cosas
distintas según quién lo habita— es precisamente el que primero se queda sin publicar.

Consecuencias prácticas, todas anteriores a la recogida: `Z` y `F` son variables de diseño
y hay que fijarlas contra `P`, no al revés; reducir de cuatro franjas a dos casi duplica
el techo de zonas; y agrupar zonas más gruesas compra publicabilidad a costa de
resolución espacial. Ninguna de las tres se puede corregir después, porque `F` está
versionada con el instrumento y `Z` queda congelada durante la recogida (Z5).

V1 debe ejecutarse con el doble umbral, no con el de anotaciones, o dará una viabilidad
que no existe.

**R10 — El descarte de grupos unitarios cae donde más duele, y por eso se registra con
nombre.** Las anotaciones que se descartan al cierre por venir de una sesión sola son, por
construcción, las de los roles con menos participación: conserjería, limpieza,
mantenimiento. Es §8 otra vez, amplificado por el propio mecanismo de protección.

El sesgo **no es aleatorio**, así que un recuento total no sirve: `anotacion.descarte`
guarda el grupo de rol de cada descarte. Que se hayan descartado cuatro sesiones de
limpieza y ninguna de PDI es un resultado que va al informe, junto al análisis y con el
mismo peso, no una nota de auditoría. Sin él, el resultado dirá «el edificio» y
significará «quienes tienen despacho», y ninguna cifra publicada lo delatará.

**Mitigación apuntada, no diseñada:** para los roles poco poblados la vía no es la
anotación agregada —que R9 demuestra que nunca alcanzará el umbral— sino la **entrevista**.
Es material cualitativo, se lee y no se agrega, como la nota libre de §5.1. Queda como
pendiente en §5; diseñarla es otra decisión y no toca ahora.

**R11 — Sin etiqueta de lote por fila no hay remediación selectiva.** Si aparece un error
de consolidación, no habrá forma de saber qué filas vinieron del lote defectuoso: habrá
que revisar la campaña entera o descartarla. Es el precio de quitar `consolidada_en` y se
paga a sabiendas.

**R12 — `posicion_etiqueta` vuelve a ser una huella si alguien deshace §5.2.** Resuelto de
raíz el 2026-09-03 al pasar la aleatorización a por anotación (§2.6), pero el riesgo
sobrevive como dependencia: el ordinal es seguro **porque** el sorteo es por anotación. Si
en algún momento se vuelve a sortear por sesión —por rendimiento, por simplificar el
cliente, por copiar un formulario existente—, la correspondencia etiqueta → posición se
vuelve constante dentro de la sesión y reabre la vía que §2.3 cierra, sin que ningún
criterio del esquema falle. Lo vigila I6.

**R13 — Coste de reversión global.** Antes de recoger la primera anotación real: barato,
son migraciones sobre tablas vacías. Después: el vocabulario, la escala de intensidad, el
modo de anclaje y las franjas invalidan la cohorte; la estructura de zonas y la gramática
de celdas se pueden cambiar sin perder dato.
