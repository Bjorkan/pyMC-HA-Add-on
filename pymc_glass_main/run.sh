#!/bin/sh
set -eu

ADDON_CONFIG_ROOT="/config"
PERSISTENT_CONFIG_DIR="${ADDON_CONFIG_ROOT}"
PERSISTENT_CONFIG_FILE="${PERSISTENT_CONFIG_DIR}/config.yaml"
TEMPLATE_CONFIG_FILE="/usr/share/pymc-glass/config.yaml.example"
DATA_DIR="/var/lib/pymc_glass"
POSTGRES_DATA_DIR="${DATA_DIR}/postgres"
PKI_DIR="${DATA_DIR}/pki"
MOSQUITTO_DATA_DIR="${DATA_DIR}/mosquitto/data"
MOSQUITTO_LOG_DIR="${DATA_DIR}/mosquitto/log"
MOSQUITTO_CONFIG_FILE="${DATA_DIR}/mosquitto/mosquitto.conf"
PG_BIN="$(find /usr/lib/postgresql -maxdepth 4 -type f -name pg_ctl | sort | tail -n 1 | xargs dirname)"
CONFIG_SOURCE="unknown"

mkdir -p "${PERSISTENT_CONFIG_DIR}" "${DATA_DIR}" "${PKI_DIR}" "${MOSQUITTO_DATA_DIR}" "${MOSQUITTO_LOG_DIR}"
chmod 755 "${DATA_DIR}" "${MOSQUITTO_DATA_DIR}" "${MOSQUITTO_LOG_DIR}"
chown -R mosquitto:mosquitto "${DATA_DIR}/mosquitto"

if [ ! -f "${PERSISTENT_CONFIG_FILE}" ]; then
    cp "${TEMPLATE_CONFIG_FILE}" "${PERSISTENT_CONFIG_FILE}"
    echo "[pymc-glass-ha] created ${PERSISTENT_CONFIG_FILE} from bundled template"
    CONFIG_SOURCE="bundled template"
else
    CONFIG_SOURCE="existing persistent config"
fi

python3 - "${PERSISTENT_CONFIG_FILE}" > /tmp/pymc-glass.env <<'PY'
import pathlib
import shlex
import sys
from urllib.parse import quote

import yaml

config = yaml.safe_load(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")) or {}


def section(name):
    value = config.get(name, {})
    return value if isinstance(value, dict) else {}


def value(sec, key, default):
    return section(sec).get(key, default)


def emit(key, raw):
    if raw is None:
        raw = ""
    if isinstance(raw, bool):
        raw = "true" if raw else "false"
    print(f"export {key}={shlex.quote(str(raw))}")


db_password = value("database", "password", "pymc_glass")
mqtt_port = int(value("mqtt", "port", 8883))

emit("APP_NAME", "pyMC_Glass API")
emit("APP_ENV", "production")
emit("APP_HOST", "0.0.0.0")
emit("APP_PORT", "8080")
emit("APP_LOG_LEVEL", value("app", "log_level", "INFO"))
emit("DATABASE_URL", f"postgresql+psycopg://postgres:{quote(str(db_password), safe='')}@127.0.0.1:5432/pymc_glass")
emit("POSTGRES_PASSWORD", db_password)
emit("MQTT_BROKER_HOST", "127.0.0.1")
emit("MQTT_BROKER_PORT", mqtt_port)
emit("MQTT_BROKER_USERNAME", "")
emit("MQTT_BROKER_PASSWORD", "")
emit("MQTT_BASE_TOPIC", value("mqtt", "base_topic", "glass"))
emit("MQTT_TLS_ENABLED", True)
emit("MQTT_TLS_CA_CERT", "/var/lib/pymc_glass/pki/ca.crt.pem")
emit("MQTT_TLS_CLIENT_CERT", "/var/lib/pymc_glass/pki/mqtt-backend-client.crt.pem")
emit("MQTT_TLS_CLIENT_KEY", "/var/lib/pymc_glass/pki/mqtt-backend-client.key.pem")
emit("MQTT_TLS_INSECURE", False)
emit("MQTT_REPEATER_TLS_ENABLED", value("mqtt", "repeater_tls_enabled", True))
emit("MQTT_INGEST_ENABLED", value("mqtt", "ingest_enabled", True))
emit("MQTT_INGEST_QUEUE_MAXSIZE", value("mqtt", "ingest_queue_maxsize", 2000))
emit("PKI_STATE_DIR", "/var/lib/pymc_glass/pki")
emit("PKI_CA_COMMON_NAME", value("pki", "ca_common_name", "pyMC_Glass Local CA"))
emit("PKI_CA_VALID_DAYS", value("pki", "ca_valid_days", 3650))
emit("PKI_CLIENT_CERT_VALID_DAYS", value("pki", "client_cert_valid_days", 90))
emit("PKI_RENEW_BEFORE_DAYS", value("pki", "renew_before_days", 30))
emit("AUTH_TOKEN_TTL_MINUTES", value("auth", "token_ttl_minutes", 1440))
emit("AUTH_TOKEN_BYTES", value("auth", "token_bytes", 48))
emit("AUTH_PASSWORD_MIN_LENGTH", value("auth", "password_min_length", 12))
emit("BOOTSTRAP_SEED_ADMIN_ENABLED", value("bootstrap", "seed_admin_enabled", True))
emit("BOOTSTRAP_SEED_ADMIN_EMAIL", value("bootstrap", "seed_admin_email", "admin@pymc.glass"))
emit("BOOTSTRAP_SEED_ADMIN_PASSWORD", value("bootstrap", "seed_admin_password", "admin12345678"))
emit("BOOTSTRAP_SEED_ADMIN_DISPLAY_NAME", value("bootstrap", "seed_admin_display_name", "Admin"))
emit("ALERT_POLICY_MONITOR_ENABLED", value("alerts", "policy_monitor_enabled", True))
emit("ALERT_POLICY_MONITOR_INTERVAL_SECONDS", value("alerts", "policy_monitor_interval_seconds", 60))
emit("ALERT_ACTION_DISPATCHER_ENABLED", value("alerts", "action_dispatcher_enabled", True))
emit("ALERT_ACTION_DISPATCHER_INTERVAL_SECONDS", value("alerts", "action_dispatcher_interval_seconds", 10))
emit("ALERT_ACTION_DISPATCHER_BATCH_SIZE", value("alerts", "action_dispatcher_batch_size", 50))
emit("ALERT_ACTION_DISPATCHER_MAX_ATTEMPTS", value("alerts", "action_dispatcher_max_attempts", 5))
emit("ALERT_ACTION_DISPATCHER_BACKOFF_SECONDS", value("alerts", "action_dispatcher_backoff_seconds", 15))
emit("CONFIG_SNAPSHOT_ENCRYPTION_KEYS", value("config_snapshots", "encryption_keys", ""))
emit("CONFIG_SNAPSHOT_RETENTION_MAX_PER_REPEATER", value("config_snapshots", "retention_max_per_repeater", 20))
emit("CONFIG_SNAPSHOT_RETENTION_MAX_AGE_DAYS", value("config_snapshots", "retention_max_age_days", 90))
emit("CONFIG_SNAPSHOT_MAX_PAYLOAD_BYTES", value("config_snapshots", "max_payload_bytes", 2000000))
emit("CONTRACT_VERSION", "v1")
PY

. /tmp/pymc-glass.env
export PATH="${PG_BIN}:${PATH}"
export PYTHONPATH="/opt/pymc-glass/backend${PYTHONPATH:+:${PYTHONPATH}}"

echo "[pymc-glass-ha] effective config source: ${CONFIG_SOURCE}; admin=${BOOTSTRAP_SEED_ADMIN_EMAIL}; path=${PERSISTENT_CONFIG_FILE}"

if [ ! -s "${POSTGRES_DATA_DIR}/PG_VERSION" ]; then
    mkdir -p "${POSTGRES_DATA_DIR}"
    chown -R postgres:postgres "${POSTGRES_DATA_DIR}"
    su -s /bin/sh postgres -c "initdb -D '${POSTGRES_DATA_DIR}'"
    echo "listen_addresses = '127.0.0.1'" >> "${POSTGRES_DATA_DIR}/postgresql.conf"
    echo "host all all 127.0.0.1/32 scram-sha-256" >> "${POSTGRES_DATA_DIR}/pg_hba.conf"
fi

chown -R postgres:postgres "${POSTGRES_DATA_DIR}"
su -s /bin/sh postgres -c "pg_ctl -D '${POSTGRES_DATA_DIR}' -l '${POSTGRES_DATA_DIR}/postgres.log' -o '-c port=5432' start"

for _ in 1 2 3 4 5 6 7 8 9 10; do
    if su -s /bin/sh postgres -c "pg_isready -h 127.0.0.1 -p 5432" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

su -s /bin/sh postgres -c "psql -v ON_ERROR_STOP=1 -v password=\"${POSTGRES_PASSWORD}\" --dbname postgres" <<SQL
ALTER USER postgres WITH PASSWORD :'password';
SELECT 'CREATE DATABASE pymc_glass'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'pymc_glass')\gexec
SQL

python3 -m app.scripts.pki_init

cat > "${MOSQUITTO_CONFIG_FILE}" <<EOF
listener ${MQTT_BROKER_PORT} 0.0.0.0
cafile ${PKI_DIR}/ca.crt.pem
certfile ${PKI_DIR}/mqtt-broker.crt.pem
keyfile ${PKI_DIR}/mqtt-broker.key.pem
require_certificate true
use_identity_as_username true
allow_anonymous false
persistence true
persistence_location ${MOSQUITTO_DATA_DIR}/
log_dest stdout
EOF

mosquitto -c "${MOSQUITTO_CONFIG_FILE}" &
MOSQUITTO_PID="$!"

nginx -g "daemon off;" &
NGINX_PID="$!"

uvicorn app.main:app --host 0.0.0.0 --port 8080 &
BACKEND_PID="$!"

cleanup() {
    kill "${BACKEND_PID}" "${NGINX_PID}" "${MOSQUITTO_PID}" 2>/dev/null || true
    su -s /bin/sh postgres -c "pg_ctl -D '${POSTGRES_DATA_DIR}' stop -m fast" >/dev/null 2>&1 || true
}
trap cleanup INT TERM EXIT

while :; do
    for pid in "${BACKEND_PID}" "${NGINX_PID}" "${MOSQUITTO_PID}"; do
        if ! kill -0 "${pid}" 2>/dev/null; then
            echo "[pymc-glass-ha] process ${pid} exited; stopping add-on"
            exit 1
        fi
    done
    sleep 5
done
