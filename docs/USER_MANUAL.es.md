# Manual de usuario de CoinTracker

> **Documentación:** [English](USER_MANUAL.md) · **Español**

Una guía visual para usar CoinTracker — desde el registro hasta el seguimiento de
posiciones, la lectura de señales y la gestión de tu cuenta.

> **No es asesoría financiera.** CoinTracker agrega y muestra datos on-chain e
> indicadores de mercado. Nada aquí constituye asesoría de inversión. Haz tu
> propia investigación; tú eres responsable de tus propias operaciones.

---

## Tabla de contenidos

1. [Primeros pasos](#1-primeros-pasos)
2. [El plan gratuito](#2-el-plan-gratuito)
3. [Funciones Pro](#3-funciones-pro)
4. [Gestión de posiciones](#4-gestión-de-posiciones)
5. [Alertas de Telegram](#5-alertas-de-telegram)
6. [Configuración de la cuenta](#6-configuración-de-la-cuenta)
7. [Panel de administración (para operadores)](#7-panel-de-administración-para-operadores)

---

## 1. Primeros pasos

### La página de inicio

La primera vez que visites CoinTracker, verás la página de inicio con un resumen
de las funciones y un botón **Comenzar**.

![Página de inicio](screenshots/01_landing.png)

### Registrar una cuenta

Haz clic en **Comenzar** para llegar a la página de registro. CoinTracker usa
**autenticación sin contraseña** — solo necesitas proporcionar una dirección de
correo electrónico. Tras hacer clic en **Crear una cuenta**, se envía un correo
de confirmación.

![Página de registro](screenshots/02_register.png)

### Confirmar mediante magic link

En lugar de una contraseña, inicias sesión con un magic link enviado a tu
correo. En desarrollo, los correos llegan al **buzón de desarrollo** en
`http://localhost:4000/dev/mailbox`. Abre el correo de confirmación y haz clic
en el enlace dentro.

![Buzón de desarrollo](screenshots/04_mailbox.png)

El enlace te lleva a una página de confirmación. Haz clic en **Confirmar y
mantener la sesión iniciada** para completar el registro.

![Página de confirmación](screenshots/05_confirmation.png)

### Iniciar sesión

Tras el registro, puedes iniciar sesión en cualquier momento desde la página
**Iniciar sesión**. Introduce tu correo y haz clic en **Iniciar sesión con
correo** para recibir un nuevo magic link, o usa los campos de contraseña si has
definido una en Configuración.

![Página de inicio de sesión](screenshots/03_login.png)

---

## 2. El plan gratuito

Tras registrarte, empiezas en el plan **gratuito**. La app te redirige a la
**página de precios** en `/upgrade`, donde puedes ver las funciones del plan
Pro.

![Página de precios/upgrade](screenshots/06_upgrade_pricing.png)

### Qué puedes usar gratuitamente

| Función | ¿Disponible en gratuito? |
|---------|--------------------------|
| Seguimiento de posiciones (crear, editar, cerrar) | Sí |
| Señales históricas (limitado a >7 días tras la salida) | Sí |
| Tutorial | Sí |
| Configuración de la cuenta | Sí |
| Gestión de claves API del exchange | Sí |
| **Señales (Top 10 en tiempo real)** | **Solo Pro** |
| **Estado del mercado** | **Solo Pro** |

### Señales históricas (vista gratuita)

La página **Histórico** en `/historical` muestra cada símbolo que ha aparecido
en el top 10. En el plan gratuito, solo ves las señales que salieron del top 10
**hace más de 7 días** — los datos recientes son exclusivos de Pro.

![Señales históricas (gratuito, vacío)](screenshots/07_historical.png)

> **Nota:** con datos recientes, la página histórica gratuita puede parecer
> vacía porque todas las señales siguen activas o salieron hace menos de 7 días.
> Una vez en Pro, los más de 60 símbolos aparecen inmediatamente.

### Tutorial

La página **Tutorial** en `/tutorial` te guía através del flujo completo:
evaluar señales, comprar en tu exchange, crear una posición y conectar
Telegram.

![Página de tutorial](screenshots/11_tutorial.png)

---

## 3. Funciones Pro

Una vez que tu cuenta esté actualizada a Pro (consulta [Panel de
administración](#7-panel-de-administración-para-operadores) o pídelo al
operador de tu instancia), tendrás acceso a las dos funciones principales.

### Señales

La página **Señales** en `/signals` es el núcleo de CoinTracker. Muestra el
**Top 10 actual** — monedas que CoinScanX ha identificado con actividad
on-chain alcista — junto con una sección de **Período de gracia** para las
monedas que hace poco salieron del top 10.

![Página de señales — Top 10](screenshots/14_signals_top10.png)

Cada tarjeta de señal muestra:

- **Símbolo** (enlaza a CoinMarketCap para investigación externa)
- **Historial** (enlaza a la página histórica interna de ese símbolo)
- Botón **Vigilar** (añade la moneda a tu pestaña Vigiladas para acceso rápido)
- Un ticker de precio en vivo arriba (impulsado por Binance) con cambio de 24h
  y un gráfico sparkline

La pestaña **Vigiladas** muestra solo las monedas que has vigilado. Úsala para
mantener un ojo en señales específicas sin desplazarte por la lista completa.

![Página de señales — pestaña Vigiladas](screenshots/15_signals_watched.png)

### Página de detalle de señal

Haz clic en cualquier señal para ver su **página de detalle** en
`/signals/:id`. Muestra métricas de rendimiento (precio inicial, precio actual,
precio máximo, % máximo de subida), un gráfico de precio, volumen de 24h,
historial de posiciones en el top 10 y ocurrencias anteriores del mismo
símbolo.

![Página de detalle de señal](screenshots/16_signals_show.png)

### Operar desde una señal

La página **Operar** en `/signals/:id/trade` te permite actuar sobre una señal
directamente. Si has guardado tus claves API de Binance (consulta [Claves API
del exchange](#claves-api-del-exchange)), puedes colocar una orden desde esta
página. De lo contrario, te solicita configurar las claves API primero.

![Página de operar desde señal](screenshots/17_signals_trade.png)

### Estado del mercado

La página **Estado del mercado** en `/market-status` muestra si el mercado está
alcista, bajista o lateral, según la cantidad de señales activas. Un gráfico de
tendencia histórica te permite alternar entre vistas de 24h, 7 días y 30 días
para sincronizar tu estrategia.

![Página de estado del mercado](screenshots/18_market_status.png)

### Señales históricas (vista Pro)

Con Pro, la página Histórico se llena con todos los símbolos — incluidos los
activos. Puedes filtrar por Todos / Activos / Inactivos / Recién salidos, y
buscar por símbolo o nombre.

![Señales históricas (Pro, con datos)](screenshots/18b_historical_pro.png)

Haz clic en cualquier símbolo para ver su historial completo de ocurrencias:

![Página de histórico de detalle](screenshots/19_historical_show.png)

---

## 4. Gestión de posiciones

### Crear una posición

Ve a **Posiciones** → **+ Añadir posición** (o `/positions/new`) para registrar
una operación. Rellena:

| Campo | Descripción |
|-------|-------------|
| **Símbolo** | El símbolo del par de trading (p. ej. `BTC`, `ETH`, `SOL`) |
| **Exchange** | Binance Spot, Bitget Spot o MEXC Spot |
| **Precio de entrada** | Tu precio de compra |
| **Alertar cada %** | Cada cuánto recibir alertas de precio por Telegram (predeterminado: 2%) |
| **Stop loss %** | Alerta automática cuando el precio cae esta cantidad por debajo de la entrada |
| **Take profit %** | Alerta automática cuando el precio sube esta cantidad por encima de la entrada |
| **Monto invertido** | Opcional — cuánto capital invertiste |

El formulario muestra una **Vista previa de la orden** en vivo con los precios
de take-profit y stop-loss calculados mientras escribes.

![Formulario de nueva posición](screenshots/10_positions_new.png)

### Ver tus posiciones

La página **Posiciones** en `/positions` lista todas las posiciones abiertas,
ordenadas por rentabilidad por defecto. Cada tarjeta de posición muestra:

- Símbolo y exchange
- Porcentaje actual de P&L
- Progreso hacia tu objetivo de take-profit
- Precio de entrada vs. precio actual
- Tiempo mantenido
- Si la moneda está actualmente en el top 10

![Lista de posiciones con datos](screenshots/20_positions_list.png)

Si aún no tienes posiciones, verás un estado vacío con un enlace **Crear
posición**.

![Estado vacío de posiciones](screenshots/09_positions_empty.png)

### Editar una posición

Haz clic en el triángulo de divulgación en una tarjeta de posición para
expandir sus acciones, o ve a `/positions/:id/edit` para modificar el precio de
entrada, los umbrales de alerta u otros campos.

![Página de editar posición](screenshots/21_positions_edit.png)

### Posiciones cerradas

La pestaña **Historial** en `/positions/closed` muestra todas las posiciones
que has cerrado, con el P&L final. Este es tu diario de trading.

![Página de posiciones cerradas](screenshots/22_positions_closed.png)

---

## 5. Alertas de Telegram

CoinTracker envía notificaciones de Telegram para:

- **Nuevas señales** — cuando una moneda entra al top 10 con actividad alcista
- **Alertas de posición** — cuando tus posiciones alcanzan el umbral de
  alerta-cada, stop-loss o take-profit
- **Cambios de estado del mercado** — cuando el mercado cambia entre
  alcista/bajista

Para conectar Telegram:

1. Crea un bot vía [@BotFather](https://t.me/BotFather) en Telegram
2. Obtén tu chat ID (escribe a [@userinfobot](https://t.me/userinfobot))
3. Pide al operador de tu instancia que configure `TELEGRAM_BOT_TOKEN` y tu
   chat ID

Una vez conectado, recibirás alertas en tiempo real en tu teléfono cuando algo
necesite tu atención. Consulta `docs/telegram-alerts.md` para detalles técnicos
sobre cómo se disparan las alertas.

---

## 6. Configuración de la cuenta

### Ajustes de usuario

La página **Configuración** en `/users/settings` te permite:

- Ver tu estado de suscripción (plan actual, fecha de vencimiento)
- Cambiar tu dirección de correo (requiere confirmación vía magic link)
- Establecer o cambiar tu contraseña
- Alternar entre temas claro/oscuro
- Cambiar tu preferencia de idioma

![Página de configuración](screenshots/12_settings.png)

### Claves API del exchange

La página **Claves API del exchange** en `/settings/exchange-keys` te permite
guardar credenciales cifradas de Binance API para operar directamente desde las
páginas de señales. Las claves API se cifran en reposo usando
[Cloak](https://github.com/danielberkompas/cloak).

![Página de claves API del exchange](screenshots/13_exchange_keys.png)

> **Seguridad:** solo guarda claves API con permisos de **lectura + trading**.
> Nunca guardes claves con permisos de retiro en ningún servicio de terceros.

---

## 7. Panel de administración (para operadores)

Si tu cuenta tiene el nivel **admin**, verás un enlace **Admin** en la
navegación. El panel de administración está impulsado por
[Backpex](https://backpex.live) y proporciona acceso CRUD completo a usuarios,
posiciones y señales.

### Tablero de administración

El tablero en `/admin` muestra tarjetas de acción rápida para cada área de
gestión.

![Tablero de administración](screenshots/23_admin_dashboard.png)

### Gestión de usuarios

El panel **Usuarios** en `/admin/users` lista todos los usuarios registrados
con su nivel de suscripción, vencimiento y detalles de cuenta.

![Lista de usuarios admin](screenshots/24_admin_users.png)

Desde la página de edición (`/admin/users/:id/edit`), un admin puede:

- Cambiar el **nivel de suscripción** (Gratis → Pro → Admin) usando el menú
  desplegable
- Establecer la fecha **Subscription Expires At**
- Ver (pero no editar) el token de Telegram del usuario y su estado de
  confirmación

Así es como los operadores **otorgan acceso Pro** a usuarios sin un proveedor
de pagos.

![Edición de usuario admin](screenshots/25_admin_users_edit.png)

### Gestión de posiciones

El panel **Posiciones** en `/admin/positions` muestra todas las posiciones de
todos los usuarios, con la capacidad de ver, editar o eliminar cualquier
posición.

![Posiciones admin](screenshots/26_admin_positions.png)

### Gestión de señales

El panel **Señales** en `/admin/signals` muestra todas las señales ingeridas
con detalle completo (precio inicial, precio tras 7d/14d, precio máximo, %
máximo de subida, volumen, estado activo/inactivo). Los admins pueden buscar,
filtrar y editar señales directamente.

![Señales admin](screenshots/27_admin_signals.png)

### Pagos

La página **Pagos** en `/admin/payments` actualmente muestra un marcador "No
configurado". El sistema original de pagos USDT TRC-20 se eliminó para el
lanzamiento público. Los operadores de forks pueden conectar su propio
proveedor de pagos y usar esta área para gestionar suscripciones.

![Pagos admin](screenshots/28_admin_payments.png)

---

## Referencia rápida: acceso a rutas

| Ruta | Gratis | Pro | Admin |
|------|--------|-----|-------|
| `/` (inicio) | Público | Público | Público |
| `/historical` | Limitado (>7d de retraso) | Completo | Completo |
| `/positions` | Sí | Sí | Sí |
| `/tutorial` | Sí | Sí | Sí |
| `/users/settings` | Sí | Sí | Sí |
| `/settings/exchange-keys` | Sí | Sí | Sí |
| `/upgrade` | Página de precios | Página de estado | Página de estado |
| `/signals` | Redirige a `/upgrade` | Sí | Sí |
| `/market-status` | Redirige a `/upgrade` | Sí | Sí |
| `/admin/*` | Redirige a `/upgrade` | Redirige a `/upgrade` | Sí |
