# ESPAZIO

**Documento maestro del proyecto.** Recoge qué es, qué no es, qué está decidido y qué
sigue abierto. Cualquier decisión que contradiga este documento se discute aquí primero
y se modifica aquí antes de tocar código.

> El nombre `ESPAZIO` es provisional. Aparece solo como nombre de repositorio y de
> paquete; ningún identificador de dominio depende de él.

Autor: Aitor Berrocal Lorda
Estado: fase 0 (núcleo)
Última revisión: pendiente de primer commit

---

## 1. Tesis

Un edificio no es un plano ni un inventario. Es **un grafo semántico versionado en el
tiempo**, donde cada espacio tiene a la vez geometría, uso, ocupación y posición
topológica.

Hoy esas dimensiones viven separadas: la geometría en AutoCAD, la ocupación en una hoja
de cálculo de gerencia, el proyecto de reforma en Revit, el escaneo en Matterport. Nadie
las reconcilia, y por eso cada decisión sobre el espacio vuelve a medir lo que ya estaba
medido.

Si el objeto es único, las funcionalidades no se pegan unas a otras: se derivan.

- Gestionar espacios es **leer** el estado actual del grafo.
- Proyectar una reforma es **bifurcar** el grafo y comparar ramas.
- Capturar un espacio real es **poblar** el grafo.
- Cartografiar la experiencia es **añadir una segunda capa** sobre los mismos nodos.

## 2. Qué hace el software

Hace visibles las consecuencias de una decisión espacial antes de tomarla, y hace
visible la distancia entre **cómo está estructurado** un espacio y **cómo lo viven**
quienes lo habitan.

El mecanismo central es un bucle de una sola frase: **se edita la geometría o la
asignación y el análisis se recalcula.** Todo lo demás es infraestructura para sostener
ese bucle.

### 2.1 Las dos capas

**Capa estructural.** Métricas derivadas de la geometría y del grafo de accesos.
Profundidad, integración, elección (*choice*), adyacencia, reparto de superficie por
unidad organizativa. Se computa sola, sin preguntar a nadie.

**Capa experiencial.** Anotaciones afectivas georreferenciadas a entidades del edificio,
aportadas por quienes lo usan, con su rol funcional como atributo.

### 2.2 El hallazgo

**No es ninguna de las dos capas por separado: es su desacople.** Un espacio
topológicamente central que todo el mundo evita. Un espacio periférico que se valora
como refugio. Donde la geometría deja de explicar, empieza lo social.

Y dentro de la capa experiencial, lo que interesa no es la media sino **la divergencia
entre roles**: dónde el mismo espacio significa cosas distintas según quién lo habita.
La entrada que para dirección es representación y para administración es control de
acceso. La sala común que unos leen como encuentro y otros como interrupción.

El output nunca es una media. Es una medida de dispersión o de divergencia entre
distribuciones por grupo.

## 3. Alcance

### Dentro

- Ingesta de planos (PDF vectorial, DXF, IFC) a modelo semántico.
- Editor de corrección humana del modelo extraído.
- Gestión y versionado de espacios, usos y asignaciones.
- Motor de métricas estructurales sobre el grafo.
- Instrumento de captura de anotación afectiva.
- Motor de análisis cruzado entre ambas capas.
- Visualización web multiplanta.

### Fuera, explícitamente

- **Posicionamiento indoor** (el punto azul que se mueve con el usuario). Requiere BLE,
  huella WiFi, fusión inercial y calibración física por edificio. Es el foso de otros.
  El usuario se sitúa solo, como en un directorio de centro comercial.
- **Hardware y captura propia.** Ni escáneres ni cámaras. Si hay splat o nube de puntos,
  la sube el cliente.
- **Reconstrucción 3D.** Si en algún momento se procesan nubes de puntos, la aportación
  es la *segmentación semántica*, no la reconstrucción.
- **Cálculo normativo con valor técnico.** Se pueden estimar aforos y recorridos de
  evacuación como indicadores; no se emite nada con validez ante la administración ni
  se sustituye a un técnico competente.

## 4. Modelo de datos

Base: **IMDF** (*Indoor Mapping Data Format*), que es GeoJSON, está documentado y es lo
que consume Apple Maps. No se inventa una ontología propia. Entidades: `venue`,
`building`, `level`, `unit`, `opening`, `fixture`, `occupant`, `anchor`, `relationship`.

Si el output es IMDF válido, hay interoperabilidad y exportabilidad gratis, y eso es
argumento ante una institución pública.

### 4.1 Extensiones propias sobre IMDF

- **Versionado temporal.** Toda entidad lleva validez temporal. El estado del edificio en
  una fecha es una consulta, no un backup. Sin esto, comparar escenarios es imposible.
- **Grafo de navegación.** Nodos y aristas por planta más conectores verticales
  (escaleras, ascensores, rampas) con coste. Sostiene tanto el cálculo de rutas como
  todas las métricas topológicas.
- **Capa de anotación.** Ver sección 5.
- **Normalización de identificadores.** Los planos reales usan esquemas incompatibles
  entre plantas. Todo espacio tiene un ID interno estable e inmutable, y los códigos del
  plano son alias.

### 4.2 Persistencia

PostGIS. Geometrías indexadas, nivel como columna, grafo en tablas propias, rutas con
pgRouting. Migraciones versionadas desde el primer commit.

## 5. El instrumento de anotación

Es una decisión **teórica**, no de interfaz. No se modifica sin revisión.

### 5.1 Estructura de una anotación

Cuatro pasos, en este orden y no en otro:

1. **Dónde** — la entidad: una `unit` o una arista del grafo.
2. **Qué siento** — una etiqueta afectiva de una lista cerrada.
3. **Por qué** — atribución estructurada, multiselección (limpieza, ruido, luz, gente,
   temperatura, orientación, privacidad, seguridad).
4. **Nota libre** — opcional, siempre.

El paso 3 es el que hace computable lo que el 2 deja en bruto: «incómodo por exceso de
gente» e «incómodo por falta de privacidad» son fenómenos distintos que exigen
intervenciones opuestas. El paso 4 es material cualitativo: **no se agrega, se lee**.

**El afecto va antes que la atribución.** Preguntar primero por limpieza o ruido le dice
a la persona en qué fijarse, y devuelve evaluación de mantenimiento en vez de
experiencia del espacio.

### 5.2 Vocabulario afectivo

Lista cerrada, corta, equilibrada: cuatro etiquetas de valencia positiva y cuatro
negativa, cubriendo distintos niveles de activación. Punto de partida:

`agradable` · `tranquilo` · `estimulante` · `seguro`
`incómodo` · `agobiante` · `tenso` · `indiferente`

Cada etiqueta lleva codificados internamente **valencia** y **activación** (modelo
circumplejo de Russell). El usuario elige una palabra; el sistema guarda dos ejes.

Intensidad de **tres** niveles, no de siete. Con la n prevista, más precisión es falsa.

Requisitos:
- El orden de presentación **se aleatoriza** en cada sesión: el primer elemento de una
  lista se elige desproporcionadamente.
- El vocabulario **se valida antes** con cinco o seis personas de perfiles distintos. Si
  «estimulante» no significa lo mismo para conserjería que para dirección, la métrica
  está rota en el origen.
- Bilingüe euskera/castellano. Traducir no basta: hay que revalidar en cada lengua.

### 5.3 Anclaje

**No se permite clicar un punto libre sobre el plano.** Un punto sugiere una precisión
que la percepción no tiene y obliga después a agregarlo a algo.

Se selecciona la entidad directamente: una estancia (polígono) o un tramo de recorrido
(arista). Escaleras, pasillos y accesos son aristas, y es donde se concentra buena parte
de lo que la gente quiere decir.

Consecuencia técnica: la agregación es limpia, sin densidad de kernel, y la anotación
queda unida al mismo nodo sobre el que se calcula integración y profundidad. Las dos
capas hablan del mismo objeto.

> Si en algún momento se admitiera anotación por punto libre, la agregación **debe** ser
> por distancia geodésica sobre el grafo, nunca euclidiana: dos puntos separados por un
> tabique están a dos metros en línea recta y a cuarenta pasos de recorrido real. La
> densidad euclidiana atraviesa paredes y produce zonas calientes que no existen.

### 5.4 Modos de captura

- **In situ** — QR en la pared, el móvil resuelve el espacio, anotación en menos de un
  minuto. Captura respuesta encarnada. Es la única vía realista para conserjería,
  limpieza y mantenimiento.
- **Retrospectivo** — plano completo en pantalla, la persona anota lo que le viene.
  Captura saliencia: lo que resulta memorable.

El modo se guarda como campo. Comparar ambos es en sí un resultado: los espacios que
solo aparecen in situ son los invisibles en el relato del edificio.

### 5.5 Reglas de interfaz que condicionan la validez

- **Nadie ve los resultados antes de anotar.** Si ves un pasillo ya marcado en rojo, tu
  anotación deja de ser tuya.
- **Lo positivo se pide explícitamente.** Sin ello sale un buzón de quejas. Cerrar la
  sesión con «¿hay algún sitio donde estés a gusto?».
- **Se registra el momento.** Un aula a las nueve y a las cinco no es el mismo espacio.
  Con timestamp y franja horaria la variación temporal sale gratis, y es probablemente
  el hallazgo más accionable del instrumento.

## 6. Análisis

Tres bloques. Ninguno es un promedio.

1. **Divergencia entre roles.** Para cada espacio, cuánto difieren los perfiles de
   valoración de dos colectivos (varianza, entropía, o divergencia de Jensen-Shannon
   entre perfiles). El output ordena espacios por conflictividad interpretativa. Ese
   ranking es el hallazgo.
2. **Desacople con la topología.** Cruce de valoración con métricas estructurales.
   Matriz interpretativa de partida:

   | | valencia + | valencia − |
   |---|---|---|
   | **integración alta** | centralidad lograda | exposición / vigilancia |
   | **integración baja** | refugio | abandono |

3. **Estructura de las dimensiones.** Qué atribuciones covarían, y si esa covariación es
   la misma para todos los roles o cambia según quién mira.

**Dos redes distintas, no confundirlas.** La espacial (grafo del edificio) y la bipartita
**actor–espacio** (nodos: roles y espacios; aristas: valoraciones). Proyectar la segunda
da qué espacios se valoran parecido y qué roles comparten mirada.

### 6.1 Traducción

Es lo que decide si esto es un producto o es depthmapX con mejor CSS.

Un valor de integración de 0,73 no es accionable. La misma información como «la reforma
deja a las doce personas de administración en el 15 % más segregado del edificio, cuando
ahora están en la media» sí lo es.

**Regla:** toda métrica se emite acompañada de (a) a quién afecta, (b) comparada contra
el resto del edificio, (c) con el delta respecto al estado actual. **Nunca un número
solo.**

## 7. Restricciones no negociables

Estas se implementan como **restricciones del sistema**, no como normas de uso.

- **Umbral mínimo de agregación.** No se muestra ningún resultado desglosado por debajo
  de 5 anotaciones por celda. El sistema lo impide; no depende de la buena voluntad de
  quien consulta.
- **Roles agrupados por función amplia**, nunca por departamento pequeño ni por persona.
  En una organización con roles poco poblados, el rol identifica.
- **Asignación por unidad organizativa por defecto.** Vincular espacio con personas
  identificables activa RGPD y, en institución pública, evaluación de impacto. Lo
  individual es opción explícita, nunca el defecto.
- **Los datos no se versionan con el código.** `data/` en `.gitignore` desde el primer
  commit. Los planos pesan; las anotaciones son datos de personas sobre su lugar de
  trabajo o estudio.
- **Migraciones destructivas y acceso a datos reales de anotación requieren aprobación
  humana explícita.** Sin excepción.
- **Encargo institucional explícito** antes de recoger una sola anotación en cualquier
  organización. No permiso informal.

## 8. Límites epistemológicos

Van aquí porque condicionan el diseño, no porque queden bonitos.

- **Space syntax mide potencial de encuentro y accesibilidad topológica, no
  comportamiento.** Correlaciona razonablemente con flujo peatonal en entornos urbanos y
  bastante peor dentro de edificios institucionales, donde horarios, jerarquía y
  protocolo pesan más que la geometría. El sistema **no promete detectar aglomeraciones
  reales**. Promete hacer explícita la estructura y comparar escenarios.
- **Sesgo de selección.** Quien participa no es quien más sabe del espacio, sino quien
  tiene tiempo o incentivo. El personal de limpieza y mantenimiento, que mejor conoce el
  edificio físicamente, es el que menos margen tiene para rellenar formularios. Si la
  captación no se diseña específicamente para ellos, el resultado dirá «el edificio» y
  significará «quienes tienen despacho».
- **Sesgo de negatividad.** Se anota lo que molesta.
- **Reactividad.** En cuanto se sabe que las valoraciones se leen, se vuelven
  estratégicas: un departamento que quiere despachos mejores tiene incentivo para
  puntuar el suyo mal. No es un fallo a corregir; es una propiedad del instrumento que
  hay que interpretar.
- **El silencio no es neutralidad.** Los espacios sobre los que nadie espera influir se
  quedan en blanco. Ese vacío merece interpretación, no relleno.
- **Escala.** Con decenas o pocos cientos de participantes y muchos espacios habrá celdas
  con dos o tres anotaciones. Esto es cartografía cualitativa densa con apoyo
  cuantitativo, **no estadística inferencial**. El riesgo del formato es que un mapa de
  calor bonito sugiera una robustez que la n no tiene.
- **La herramienta no decide.** Qué es un punto negro y qué es una zona fantasma
  deseable sigue siendo una cuestión política. Una sala vacía puede ser mala
  planificación o el único sitio tranquilo del edificio.

## 9. Caso piloto

**Facultad de Ciencias Sociales y de la Comunicación, UPV/EHU (Leioa).**

Razones: planos de orientación públicos, espacio cerrado, actores muy diversos
(alumnado, PDI de ocho o nueve departamentos, administración, conserjería, limpieza,
personal del MEDIALAB), y sin implicación con la situación laboral del autor.

### 9.1 Estado del dato de partida

Cinco plantas en PDF vectorial de Illustrator (plantas 0–2 y 4 de julio de 2021, planta
3 de enero de 2024). Extracción automática ya realizada: **501 recintos**.

| planta | recintos | con código | con ocupante por color |
|---|---|---|---|
| 0 | 45 | 56 % | 33 % |
| 1 | 63 | 54 % | 3 % |
| 2 | 58 | 3 % | 10 % |
| 3 | 115 | 57 % | 46 % |
| 4 | 220 | 72 % | 45 % |

La planta 4 es la más rica: ~200 despachos con código y color departamental
simultáneamente. Es la única con ambas capas densas.

Particularidad aprovechable: en las plantas 2 y 4 **la atribución departamental está
codificada en el color de relleno**, y la leyenda la traduce. La capa de ocupación viene
servida en el propio dibujo.

### 9.2 Lo que estos planos no dan

- **No hay puertas.** Las estancias son polígonos cerrados sin huecos de paso. Permite
  derivar adyacencia, no accesibilidad. **Sin aberturas no hay grafo, y sin grafo no hay
  space syntax.** Es el bloqueo duro del motor topológico.
- **No hay escala.** Sin cotas ni barra de escala no hay m². Apaño razonable: anclar a la
  huella del edificio vía Catastro (INSPIRE) y derivar transformación afín. Superficies
  aproximadas, suficientes para comparar reparto, no catastrales.
- **Cobertura parcial.** La planta 2 solo dibuja lo que su leyenda explica.
- **Esquemas de identificación incompatibles** entre plantas (números sueltos, códigos
  `4.126`, nombres funcionales, colores). De ahí la normalización de la sección 4.1.
- **Vintages distintos.** Tres años de diferencia entre plantas. Los departamentos se
  mueven. Es el argumento empírico del versionado temporal.

### 9.3 Vía de desbloqueo

Solicitar DWG o IFC al Servicio de Obras y Mantenimiento o al vicerrectorado de
infraestructuras. Con el IFC llegan puertas, cotas y usos de una sola vez. Petición
pequeña, retorno enorme.

### 9.4 Advertencia sobre granularidad

`4.126` es un identificador de puerta de despacho, y en una facultad el despacho
identifica a la persona con bastante fiabilidad. **La granularidad que hace valiosa la
planta 4 para el análisis distributivo es la misma que la hace peligrosa para el análisis
de percepción.** Al colgar la capa afectiva, la unidad de agregación sube a zona o
departamento.

## 10. Fases

**Fase 0 — Núcleo.** Extractor de planos a modelo semántico. Editor de corrección.
Esquema IMDF extendido en PostGIS con migraciones. Un formulario mínimo que guarde una
anotación real de punta a punta. *Sin esto no hay nada.*

**Fase 1 — Análisis.** Gestión y versionado de asignaciones. Motor de métricas
estructurales. Motor de divergencia entre roles. Capa de traducción a lenguaje
accionable. *Aquí salen las publicaciones.*

**Fase 2 — Reformas.** Bifurcación de escenarios y comparación. La capa geométrica
(recálculo de superficies, aforos, ocupación) antes que la visual. La visual es una
llamada a una API generativa: impresiona en demo y no pertenece al proyecto.

**Fase 3 — Captura.** Ingesta de splats y nubes de punto subidos por el cliente.
Segmentación semántica hacia el modelo. *Scan-to-BIM automático, pregunta de
investigación por sí sola.*

### Orden de construcción

**Se empieza por la traducción, no por el motor.** Coger un edificio real, calcular tres
métricas a mano y escribir el informe que se entregaría. Si ese informe no le dice nada a
un gerente, ningún motor lo arregla. Si le dice algo, ya se sabe exactamente qué tiene
que calcular el motor y todo lo demás sobra.

Y **no se construye el backend completo antes de saber cómo se anota.** El esquema de la
anotación es una decisión teórica; tomarla después de tener migraciones, API y modelos
significa tomarla condicionada por lo ya construido.

## 11. Stack

| capa | elección | motivo |
|---|---|---|
| extracción | Python + pdfplumber | los planos son PDF vectorial: es parseo, no visión |
| datos | PostgreSQL + PostGIS | geometría indexada, estándar, sin licencias |
| grafo | pgRouting | evita reimplementar Dijkstra |
| API | Next.js / Python | por decidir en fase 0 |
| mapa | MapLibre GL JS + teselas vectoriales | sin dependencia de Google |
| formato | IMDF (GeoJSON) | interoperabilidad y argumento institucional |

## 12. Decisiones abiertas

- Nombre definitivo.
- Repositorio público o privado. Público da credibilidad investigadora y artefacto
  citable; privado deja limpia la vía comercial. **Se puede empezar privado y abrir
  después; al revés no.**
- Titularidad del dataset y de lo derivado si hay convenio o financiación pública.
  Resolver **antes** de empezar, no después: es lo que arruina la transición de
  investigación a producto cuando se mira tarde.
- Lengua por defecto del instrumento y estrategia de validación bilingüe.
- Vocabulario afectivo definitivo, tras validación con perfiles diversos.
- Comprador objetivo si llega la fase comercial: gerencia, servicios generales o
  vicerrectorado de infraestructuras. **No RRHH**: gestiona personas, no metros, y no
  tiene ni el presupuesto ni los planos.
