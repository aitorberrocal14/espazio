# CLAUDE.md — ESPAZIO

Contexto operativo del repositorio. Se carga en cada sesión de Claude Code.
La razón de ser del proyecto está en `PROYECTO.md`; **léelo antes de cualquier tarea que
toque el modelo de datos, el instrumento de anotación o el motor de análisis.**

---

## Qué es esto

Plataforma de cartografía y análisis de espacios interiores. Modela un edificio como un
**grafo semántico versionado**, cruza su estructura topológica con la experiencia
declarada de quienes lo habitan, y hace visible el desacople entre ambas.

Fase actual: **0 — núcleo**.

## Los dos roles

El trabajo está dividido en dos modos. No los mezcles en la misma sesión.

**Arquitecto** (`.claude/skills/arquitectura-espazio/`) — decide estructura, modelo de
datos y especificaciones. Produce especificaciones con criterios de aceptación
verificables. No escribe código de producción.

**Implementador** (`.claude/skills/implementacion-espazio/`) — escribe código y los tests
que demuestran los criterios de aceptación. No decide arquitectura ni toca el esquema
sin especificación previa.

Si estás implementando y descubres que la especificación es incoherente o insuficiente:
**para y dilo**. No la completes por tu cuenta.

## Reglas duras

Estas no se negocian, no se relajan «solo por esta vez» y no se resuelven pidiendo
disculpas después.

1. **Nada toca el esquema de la base de datos sin especificación aprobada.** Es el único
   sitio donde un error es caro de deshacer.
2. **Migraciones destructivas requieren aprobación humana explícita** en el mensaje
   inmediatamente anterior. `DROP`, `TRUNCATE`, `ALTER ... DROP COLUMN`, borrados
   masivos. Si tienes que preguntar si cuenta, cuenta.
3. **Nunca commitees datos.** `data/`, planos, exports, `.env`, dumps. Si un archivo
   contiene una anotación real de una persona, no entra en git bajo ninguna
   circunstancia.
4. **Nunca accedas a datos reales de anotación** sin permiso explícito. Para desarrollo
   hay generador de datos sintéticos.
5. **El umbral de agregación (k = 5) es una restricción del sistema**, no una opción de
   configuración ni un parámetro que el usuario final pueda bajar. Cualquier endpoint,
   consulta o export que pueda devolver un desglose por debajo del umbral es un bug de
   seguridad, no una mejora pendiente.
6. **El instrumento de anotación no se modifica sin revisión.** Vocabulario afectivo,
   orden de los pasos, escala de intensidad y modo de anclaje son decisiones teóricas
   documentadas en `PROYECTO.md` §5. Cambiarlas invalida los datos ya recogidos.
7. **Las métricas nunca se emiten como número solo.** Toda salida lleva a quién afecta,
   comparación contra el resto del edificio y delta respecto al estado actual
   (`PROYECTO.md` §6.1).

## Estructura

```
espazio/
├── PROYECTO.md              # documento maestro — la fuente de verdad
├── CLAUDE.md                # este archivo
├── decisiones/              # una decisión por archivo, fechada, con alternativas
├── extraccion/              # parseo de planos → modelo semántico
├── esquema/                 # migraciones versionadas
├── api/
├── web/
├── analisis/                # métricas estructurales y de divergencia
├── datos_sinteticos/        # generador para desarrollo
└── data/                    # IGNORADO POR GIT. Planos y anotaciones reales.
```

## Convenciones

**Idioma.** Documentación, nombres de tabla, columnas y variables de dominio en
castellano. Palabras clave del lenguaje y librerías en inglés, obviamente. Un `unit` es
un `recinto`; un `occupant`, un `ocupante`. No mezcles los dos idiomas dentro de un
mismo identificador.

**Identificadores.** Todo espacio tiene un ID interno estable e inmutable. Los códigos
del plano (`4.126`, `MM3`, `Aula 12`) son **alias**, nunca claves primarias. Los planos
reales usan esquemas incompatibles entre plantas; contar con ello es parte del diseño.

**Geometría.** Sistema de coordenadas explícito siempre. Los planos de partida están en
puntos de PDF **sin georreferenciar**; nada que dependa de coordenadas reales puede
asumir que ya lo están.

**Tiempo.** Toda entidad del modelo lleva validez temporal. «El estado actual» es una
consulta con fecha, no una tabla aparte.

**Migraciones.** Versionadas, reversibles, una por cambio conceptual. Nunca editar una
migración ya aplicada.

**Tests.** Un cambio sin test que demuestre su criterio de aceptación no está terminado.
La verificación primaria es la suite, no el resumen que escribas.

## Cómo entregas trabajo

**No escribas informes en prosa sobre tu propio trabajo.** Un informe que dice que todo
salió bien no es verificable y no sirve para revisar nada.

Entrega, en este orden:

1. El **diff**.
2. Los **tests** que demuestran los criterios de aceptación de la especificación.
3. Un resumen de **cinco líneas como máximo**: qué decidiste, qué dejaste fuera, qué te
   pareció dudoso.

El punto 3 vale por lo que admite, no por lo que afirma. Si algo quedó a medias, mal
resuelto o adivinado, ese es exactamente el contenido útil del resumen. Si no hay nada
dudoso que contar, escribe una línea y ya.

## Lo que no debes hacer

- Ampliar el alcance. Si una tarea sugiere una funcionalidad nueva, anótala en
  `decisiones/` como pendiente; no la implementes.
- Construir para necesidades futuras hipotéticas. Fase 0 es fase 0.
- Implementar posicionamiento indoor, captura 3D o reconstrucción. Están fuera de alcance
  (`PROYECTO.md` §3) y no por olvido.
- Sustituir una restricción de privacidad por un aviso al usuario. La restricción se
  implementa; el aviso no la reemplaza.
- Suavizar un problema que encuentres. Si el enfoque especificado no funciona, dilo
  claro y explica por qué.
