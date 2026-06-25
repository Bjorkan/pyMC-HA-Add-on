# Home Assistant Add-on: pyMC Glass Main

## About

This add-on builds and wraps the upstream `pyMC-Glass` `main` branch as a
single Home Assistant add-on.

Glass is normally shipped as a Docker Compose stack. The Home Assistant wrapper
runs the same core pieces inside one add-on container:

- pyMC Glass frontend served by nginx on port `5173`
- pyMC Glass FastAPI backend on internal port `8080`
- local PostgreSQL database persisted under `/var/lib/pymc_glass`
- local TLS-enabled Mosquitto broker exposed on port `8883`
- local PKI material persisted under `/var/lib/pymc_glass/pki`

This is the main-tracking add-on. It is built from the upstream `main` branch.

The first time the add-on starts it will create:

- `/config/config.yaml`
- `/var/lib/pymc_glass/postgres`
- `/var/lib/pymc_glass/pki`
- `/var/lib/pymc_glass/mosquitto`

Inside the add-on, `/config` is the add-on's private config mount. On the host,
those files are stored in the add-on's own `addon_config` directory, separate
from Home Assistant's main `/config` folder.

## Install

1. Add this repository to Home Assistant.
2. Install the `pyMC Glass Main` add-on.
3. Open your Home Assistant file editor, such as Studio Code Server.
4. Edit the add-on config file `config.yaml` in the add-on's own config folder.
   You are looking for a folder matching `addon_config/*_pymc_glass_main`.
5. Start the add-on and open the web UI on port `5173`.

## Default Login

The bundled starter config seeds an admin account when the Glass database is
empty:

- Email: `admin@pymc.glass`
- Password: `admin12345678`

Change `bootstrap.seed_admin_email` and `bootstrap.seed_admin_password` before
first start if you want different initial credentials. Seeding only runs when
the users table is empty.

## Configuration

This add-on uses a real YAML file at `/config/config.yaml`.
The add-on seeds that file on first start and then treats it as the source of
truth for wrapper-level Glass settings.

At minimum, review:

- `database.password`
- `bootstrap.seed_admin_email`
- `bootstrap.seed_admin_password`
- `mqtt.base_topic`
- `mqtt.port`

The local MQTT broker uses mutual TLS and exposes port `8883` on the Home
Assistant host. Glass-generated PKI files are stored in
`/var/lib/pymc_glass/pki`.

## Hardware Access

This add-on currently runs with `full_access: true` and AppArmor disabled to
match the access style used by the pyMC add-ons in this repository.

## Web UI

The add-on exposes the Glass web interface on port `5173`.

## Upstream Project

- Upstream repo: <https://github.com/pyMC-dev/pyMC-Glass>
- Upstream branch used by this add-on: `main`
