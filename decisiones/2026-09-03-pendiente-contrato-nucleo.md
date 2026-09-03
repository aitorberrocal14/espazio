# Pendiente: el contrato con el esquema núcleo está declarado, no verificado

Fecha: 2026-09-03
Estado: **pendiente**, sin decidir
Relacionado: `2026-09-03-esquema-capa-anotacion.md` §2.8 y riesgo R7

---

## Qué pasa

La migración `0003_nucleo_contrato.sql` crea `nucleo.venue`, `nucleo.recinto` y
`nucleo.arista` con lo mínimo para que las claves ajenas de la capa de anotación
resuelvan. **Eso no es el esquema núcleo y no verifica su contrato.** Es un esqueleto que
satisface las FK.

El contrato de §2.8 pide más que identidades:

- identidad estable e **inmutable**, sin atributos que cambien con el tiempo;
- tablas de versión aparte, con validez temporal;
- resolución `(entidad_id, fecha) → versión vigente`;
- geometría con sistema de coordenadas explícito;
- los códigos de plano como alias, nunca como clave.

De todo eso, el esqueleto solo tiene las identidades. No hay tabla de versión, no hay
geometría —este entorno no tiene PostGIS y la capa de anotación no lo necesita—, no hay
alias y no hay función de resolución temporal. Nada de la suite comprueba que el núcleo
vaya a cumplir el contrato, porque no hay núcleo que comprobar.

## Por qué importa

R7 dice que si el núcleo acaba anclando la anotación a **versiones** en vez de a
identidades estables, la capa entera se rompe, y el coste crece con cada anotación
recogida. Ese riesgo hoy está **enunciado y no vigilado**: ningún test se pondría rojo si
el núcleo se diseñara mal, porque el esqueleto que hay no representa el problema.

Dicho de otro modo: la parte cara de deshacer es justo la que no está cubierta.

## Qué lo cerraría

No es trabajo de esta decisión, sino de la del esquema núcleo, pero conviene dejar
apuntado qué haría falta para que R7 deje de estar a ciegas:

1. Un test de contrato que, dado el esquema núcleo real, compruebe que
   `nucleo.recinto` no tiene columnas mutables, que existe tabla de versión con validez
   temporal sin solapes, y que la resolución `(id, fecha)` devuelve exactamente una
   versión.
2. Un test que anote sobre un recinto, parta ese recinto en dos en una versión
   posterior, y compruebe que la anotación anterior sigue resolviendo a la versión que
   existía cuando se hizo. Es el caso que motivó todo el diseño temporal y ahora mismo no
   está demostrado en ninguna parte.
3. PostGIS en el entorno, para lo anterior no hace falta, pero sí para el núcleo real.

## Qué NO es esto

No es un fallo del trabajo entregado: la especificación deja el núcleo explícitamente
fuera (§5 de la decisión) y el esqueleto es lo que había que hacer para probar los siete
criterios. Es deuda declarada, para que no se descubra como sorpresa el día que alguien
escriba el núcleo y dé por hecho que el contrato estaba comprobado.
