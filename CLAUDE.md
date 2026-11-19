# Cami Gym — guía del proyecto

App web para el celular de **Camila Lasa · Entrenamientos** (camilasa.fitness). La profe arma rutinas para sus alumnos; cada alumno ve la suya, mira los videos de YouTube dentro de la app, anota si subió de peso, deja comentarios y suma puntos y niveles.

## Archivos
- `index.html`: la app completa en un solo archivo (HTML + CSS + JS, sin build ni dependencias de npm). Configurada para producción con Supabase (constante `CFG` al principio del script).
- `demo.html`: el mismo código con `CFG` vacío, así funciona en modo demo con datos de ejemplo guardados en `localStorage`. Si cambiás `index.html`, regenerá `demo.html` copiándolo y dejando `const CFG={url:'',key:''};`.
- `db/schema.sql`: tablas, funciones y permisos de Supabase (las migraciones posteriores están agregadas al final).
- `db/seed.sql`: biblioteca inicial de 75 ejercicios con su video y un plan de ejemplo.
- `ejemplos/plan-ejemplo.pdf`: planilla real en el formato de Camila, sirve para probar "Importar rutina desde PDF".

## Cómo se usa
- Alumno: `https://agustinvignera.github.io/camigym/?a=TOKEN_DEL_ALUMNO` (sin contraseña).
- Profe: `https://agustinvignera.github.io/camigym/?p=TOKEN_DE_LA_PROFE` (link secreto; quien lo tenga puede editar todo).
- Sin parámetros: pantalla "Pedile tu link a Camila".
- Los tokens NO están en este proyecto. Se consultan en Supabase → SQL Editor: `select v from config where k='profe_token';` y `select nombre, token from alumnos;`.

## Arquitectura
- Hosting: GitHub Pages, repo `agustinvignera/camigym`, rama `main`, raíz. Publicar = commit + push a `main` (tarda ~1 minuto).
- Datos: Supabase, proyecto `camigym` (id `wrpdawwxtwpsgwiptdzz`, plan gratuito). La app usa la clave publicable (pública por diseño) y llama por HTTP a funciones RPC: `POST {url}/rest/v1/rpc/{funcion}`.
- Seguridad: todas las tablas tienen RLS activado y ninguna política, así que no se pueden leer directo. Todo pasa por funciones `SECURITY DEFINER` que validan el token:
  - Alumno: `alumno_load`, `alumno_sesion`, `alumno_peso`, `alumno_comentar`.
  - Profe: `profe_load`, `profe_alumno_nuevo`, `profe_alumno_guardar`, `profe_alumno_foto`, `profe_ex_guardar`, `profe_ex_borrar`.
  - Helpers internos sin permiso para anon: `_alumno`, `_profe`, `_ex_json`, `_alumno_json`.
  - Los avisos del linter de Supabase sobre "SECURITY DEFINER ejecutable por anon" son esperados: es el diseño.
- El plan de cada alumno se guarda como JSON en `alumnos.plan`:
  `{weeks:[{days:[{t:"Rutina 1", s:"Upper body · pecho + bíceps", b:[{x:"3", wu:true, i:[{e:"u1", n:"nota", s:[{r:"1×10", p:"50kg"}]}]}]}]}]}`
  (`b` = bloques que comparten series, `x` = series, `wu` = bloque de entrada en calor, `e` = id del ejercicio, `s` = series con reps y peso).
- Claves de progreso: sesión `"semana-día"` (p. ej. `0-2`); peso `"semana-día-bloque-ejercicio-serie"`. Si se reordena un plan ya en uso, los pesos anotados pueden quedar desfasados.
- La foto del alumno se guarda como data URL JPEG chica (máx. 250 KB) en `alumnos.foto`.

## Reglas de puntos (función `score` en index.html)
- +10 por rutina hecha, +5 por cada ejercicio en que el alumno subió el peso, −10 por cada día del plan no hecho al cerrar la semana (lunes a domingo, desde la fecha de inicio).
- Cada 100 puntos un nivel: Bronce, Plata, Oro, Platino, Diamante. Si pierde puntos baja. Mínimo 0.
- El ranking solo lo ve la profe.

## Importar rutina desde PDF (función `parseRoutinePdf`)
- Usa pdf.js 3.11.174 desde cdnjs, cargado a demanda.
- Espera el formato de las planillas de Camila: páginas "semana N" y páginas "rutina N" con la tabla EJERCICIO / SERIES / REP / PESO. Cada ejercicio es un link a YouTube; las series se asignan al bloque más cercano en vertical; las reps y pesos apilados se convierten en series distintas; el texto después del primer punto del nombre es la nota (drop sets).
- Los ejercicios se reconocen por el id del video (o por el nombre); los nuevos se agregan a la biblioteca con una categoría estimada (`guessCat`).

## Pendiente / ideas
- Objetivos del mes definidos por la profe.
- Plan gratuito de Supabase: pausa el proyecto tras 7 días sin uso (se reactiva desde el panel). Si se vuelve un servicio pago a alumnos, conviene pasar a Supabase Pro y a un hosting que permita uso comercial (Netlify o Cloudflare Pages).

## Al trabajar en este proyecto
- Probá los cambios en `demo.html` (o con un servidor local) antes de publicar.
- Para cambiar la base, agregá la migración al final de `db/schema.sql` y aplicala en Supabase.
- Nunca publiques ni guardes en el repo los tokens de la profe o de los alumnos.
