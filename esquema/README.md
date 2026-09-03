# esquema

Migraciones de la capa de anotación afectiva, contra la especificación
`decisiones/2026-09-03-esquema-capa-anotacion.md`.

Una por cambio conceptual, numeradas, con su reversión al lado
(`NNNN_nombre.revertir.sql`). **Una migración aplicada no se edita**: se añade otra.

## Levantar y aplicar

```sh
esquema/bd_local.sh arrancar          # imprime las variables de conexión
export PGHOST=/var/run/postgresql PGPORT=5433 PGUSER=postgres
createdb espazio_dev
esquema/aplicar.sh espazio_dev
esquema/aplicar.sh espazio_dev revertir   # en orden inverso
```

Requiere PostgreSQL 16 y `btree_gist`. **No requiere PostGIS**: la capa de anotación no
guarda geometría, la guarda el esquema núcleo, que es otra decisión y otra migración.

## Suite

```sh
python -m pytest tests -v
```

Corre contra un Postgres real, sobre una base efímera que se crea y se destruye por
ejecución. No hay dobles: lo que se comprueba es que la separación de privilegios y el
umbral los hace cumplir el motor, y eso contra un mock no significa nada.
`ESPAZIO_BASE=<base>` la ejecuta contra una base ya preparada, que es como se comprueba
que los tests detectan un esquema alterado.

## Orden y por qué

| # | qué | por qué ahí |
|---|---|---|
| 0001 | `btree_gist` | lo necesita el `EXCLUDE` de la zonificación |
| 0002 | los cinco roles | son de clúster; creación idempotente |
| 0003 | contrato del núcleo | solo lo que la anotación necesita para que sus FK resuelvan |
| 0004 | instrumento | catálogos versionados y `umbral_k()` |
| 0005 | campaña, roles, zonas | las zonas van **antes** que la campaña: con recogida abierta quedan congeladas |
| 0006 | captura | zona efímera; único sitio con identificador de sesión |
| 0007 | dato consolidado | sin sesión, sin instante, sin etiqueta de lote |
| 0008 | notas libres | esquema propio: k=5 no las protege |
| 0009 | consolidación | severa la sesión y calcula `n_sesiones` mientras existe |
| 0010 | vistas publicadas | umbral doble y supresión complementaria |
| 0011 | privilegios | aquí es donde el umbral deja de ser una norma de uso |

## Lo que este esqueleto todavía no tiene

Solo están implementados los objetos que necesitan los criterios P1–P5, U1 y A6. No hay
API, ni frontend, ni el resto de vistas, ni el esquema núcleo real.
