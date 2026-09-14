#!/usr/bin/env bash
# ============================================================================
#  Installer for the "economy" project on Ubuntu/Debian (no Docker).
#
#  Creates a fully namespaced, self-contained deployment so it never collides
#  with other projects on the same server (e.g. knight):
#     system user : economy
#     directories : /opt/economy
#     database    : economy  (role economy)
#     service     : economy.service   (gunicorn on a unix socket)
#     web         : one nginx server block named "economy" (by domain)
#     management  : economyctl
#
#  Run ON the server as root/sudo:
#     sudo bash deploy/install.sh --domain economy.example.ir --email you@example.com
#  Or without a domain (HTTP-only, IP test mode — admin panel is NOT secure):
#     sudo bash deploy/install.sh --no-ssl
#  Update after code changes:
#     sudo economyctl update
# ============================================================================
set -euo pipefail

APP="economy"
REPO="${ECONOMY_REPO:-https://github.com/Mahdi-Shafiei-IRAN/economyreporter.git}"
BRANCH="main"
BASE="/opt/$APP"
APPDIR="$BASE/app"
BACKEND="$APPDIR/backend"
VENV="$BASE/venv"
ENVFILE="$BASE/.env"
SVC="/etc/systemd/system/$APP.service"
NGINX_SITE="/etc/nginx/sites-available/$APP"
SOCK="/run/$APP/gunicorn.sock"
SETTINGS="config.settings.production"
WORKERS="${WORKERS:-3}"
SOURCE="${SOURCE:-}"
PIP_INDEX="${PIP_INDEX:-}"

DOMAIN=""
EMAIL=""
USE_SSL=1

log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  \xe2\x9c\x93\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m\xe2\x9c\x97 %s\033[0m\n' "$*" >&2; exit 1; }
trap 'die "Install aborted at line $LINENO."' ERR

while [ $# -gt 0 ]; do
  case "$1" in
    --domain) DOMAIN="${2:-}"; shift 2;;
    --email)  EMAIL="${2:-}";  shift 2;;
    --branch) BRANCH="${2:-}"; shift 2;;
    --no-ssl) USE_SSL=0; shift;;
    --source) SOURCE="${2:-}"; shift 2;;
    --pip-index) PIP_INDEX="${2:-}"; shift 2;;
    -h|--help) grep -E '^#' "$0" | sed -E 's/^# ?//'; exit 0;;
    *) die "Unknown argument: $1";;
  esac
done

[ "$(id -u)" -eq 0 ] || die "Run as root or with sudo."
command -v apt-get >/dev/null || die "This installer targets Ubuntu/Debian (apt)."

if [ -n "$DOMAIN" ] && [ "$USE_SSL" -eq 1 ] && [ -z "$EMAIL" ]; then
  if [ -t 0 ]; then read -rp "Email for Let's Encrypt certificate: " EMAIL; fi
  [ -n "$EMAIL" ] || die "SSL needs --email (or pass --no-ssl)."
fi

# If no --source given, use the checkout this script runs from (offline / blocked github).
if [ -z "$SOURCE" ]; then
  _self="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
  [ -n "$_self" ] && [ -f "$_self/backend/manage.py" ] && SOURCE="$_self"
fi

# --- 1) system packages ---
log "Installing system packages (Python, PostgreSQL, nginx, ...)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  python3 python3-venv python3-dev build-essential libpq-dev \
  postgresql nginx git curl ufw openssl rsync >/dev/null
if [ -n "$DOMAIN" ] && [ "$USE_SSL" -eq 1 ]; then
  apt-get install -y -qq certbot python3-certbot-nginx >/dev/null
fi
ok "Packages installed"

# --- 2) system user + directories ---
if ! id "$APP" >/dev/null 2>&1; then
  adduser --system --group --home "$BASE" --shell /usr/sbin/nologin "$APP" >/dev/null
  ok "System user '$APP' created"
fi
mkdir -p "$BASE"
usermod -aG "$APP" www-data          # nginx must read the gunicorn socket
chown "$APP:$APP" "$BASE"

# --- 3) fetch / update code ---
log "Placing project code into $APPDIR"
mkdir -p "$APPDIR"
if [ -n "$SOURCE" ]; then
  # Copy from a local checkout (works when the server can't reach github).
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude='.env' --exclude='mobile/build' "$SOURCE"/ "$APPDIR"/
  else
    cp -a "$SOURCE/." "$APPDIR/"
  fi
  chown -R "$APP:$APP" "$APPDIR"
  echo "$SOURCE" > "$BASE/.source"; chown "$APP:$APP" "$BASE/.source"
  ok "Code copied from local source: $SOURCE"
elif [ -d "$APPDIR/.git" ]; then
  sudo -u "$APP" git -C "$APPDIR" fetch --depth 1 origin "$BRANCH" -q
  sudo -u "$APP" git -C "$APPDIR" reset --hard "origin/$BRANCH" -q
  ok "Code updated from git"
else
  sudo -u "$APP" git clone --depth 1 -b "$BRANCH" "$REPO" "$APPDIR" -q
  ok "Code cloned from git"
fi

# --- 4) python venv ---
log "Creating venv and installing dependencies"
[ -d "$VENV" ] || sudo -u "$APP" python3 -m venv "$VENV"
pip_flags=""; [ -n "$PIP_INDEX" ] && pip_flags="-i $PIP_INDEX"
sudo -u "$APP" "$VENV/bin/pip" install -q $pip_flags -U pip wheel
sudo -u "$APP" "$VENV/bin/pip" install -q $pip_flags -r "$BACKEND/requirements/production.txt"
ok "Dependencies installed"

# --- 5) PostgreSQL ---
log "Preparing PostgreSQL database"
DB_PASSWORD="$(grep -oP '(?<=^DB_PASSWORD=).*' "$ENVFILE" 2>/dev/null || true)"
[ -n "$DB_PASSWORD" ] || DB_PASSWORD="$(openssl rand -hex 24)"
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$APP'" | grep -q 1; then
  sudo -u postgres psql -qc "CREATE ROLE $APP LOGIN PASSWORD '$DB_PASSWORD';"
  ok "DB role '$APP' created"
else
  sudo -u postgres psql -qc "ALTER ROLE $APP PASSWORD '$DB_PASSWORD';"
fi
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$APP'" | grep -q 1; then
  sudo -u postgres createdb -O "$APP" "$APP"
  ok "Database '$APP' created"
fi

# --- 6) .env (existing values are preserved) ---
log "Writing environment file ($ENVFILE)"
get_env() { grep -oP "(?<=^$1=).*" "$ENVFILE" 2>/dev/null || true; }
SECRET_KEY="$(get_env SECRET_KEY)"
[ -n "$SECRET_KEY" ] || SECRET_KEY="$("$VENV/bin/python" -c 'import secrets;print(secrets.token_urlsafe(64))')"

if [ -n "$DOMAIN" ]; then
  case "$DOMAIN" in www.*) HOSTS="$DOMAIN";; *) HOSTS="$DOMAIN,www.$DOMAIN";; esac
else
  IP="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
  HOSTS="$IP,127.0.0.1"
fi
if [ -n "$DOMAIN" ] && [ "$USE_SSL" -eq 1 ]; then SEC=True; else SEC=False; fi

umask 077
cat > "$ENVFILE" <<ENV
# Generated by deploy/install.sh — safe to edit by hand, then: economyctl restart
SECRET_KEY=$SECRET_KEY
DEBUG=False
ALLOWED_HOSTS=$HOSTS

DB_ENGINE=postgres
DB_NAME=$APP
DB_USER=$APP
DB_PASSWORD=$DB_PASSWORD
DB_HOST=127.0.0.1
DB_PORT=5432

FAMILY_MAX_MEMBERS=3

# Security (keep True behind HTTPS; auto-False in HTTP-only mode)
SECURE_SSL_REDIRECT=$SEC
SESSION_COOKIE_SECURE=$SEC
CSRF_COOKIE_SECURE=$SEC
ENV
umask 022
chown "$APP:$APP" "$ENVFILE"; chmod 640 "$ENVFILE"
sudo -u "$APP" ln -sfn "$ENVFILE" "$BACKEND/.env"   # Django reads .env next to BASE_DIR
ok ".env written"

# --- 7) migrate + static ---
log "Running migrate and collectstatic"
run_dj() { sudo -u "$APP" env DJANGO_SETTINGS_MODULE="$SETTINGS" "$VENV/bin/python" "$BACKEND/manage.py" "$@"; }
run_dj migrate --noinput
run_dj collectstatic --noinput >/dev/null
ok "Database migrated, static files collected"

# --- 8) systemd service (gunicorn) ---
log "Installing systemd service: $APP.service"
cat > "$SVC" <<UNIT
[Unit]
Description=economy Django (gunicorn)
After=network.target postgresql.service
Requires=postgresql.service

[Service]
User=$APP
Group=$APP
WorkingDirectory=$BACKEND
Environment=DJANGO_SETTINGS_MODULE=$SETTINGS
RuntimeDirectory=$APP
RuntimeDirectoryMode=0750
ExecStart=$VENV/bin/gunicorn config.wsgi:application \\
    --name $APP --workers $WORKERS --umask 007 \\
    --bind unix:$SOCK --access-logfile - --error-logfile -
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable -q "$APP"
systemctl restart "$APP"
sleep 1
systemctl is-active --quiet "$APP" || { journalctl -u "$APP" -n 30 --no-pager; die "Service failed to start."; }
ok "Service is active"

# --- 9) nginx ---
log "Configuring nginx"
mkdir -p "$BASE/updates"; chown "$APP:$APP" "$BASE/updates"   # APK + version.json for in-app updates
if [ -n "$DOMAIN" ]; then
  case "$DOMAIN" in www.*) SERVER_NAME="$DOMAIN";; *) SERVER_NAME="$DOMAIN www.$DOMAIN";; esac
else
  SERVER_NAME="_"
fi
cat > "$NGINX_SITE" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $SERVER_NAME;

    client_max_body_size 10m;

    location /static/ {
        alias $BACKEND/staticfiles/;
        access_log off;
        expires 7d;
    }

    location /updates/ {
        alias $BASE/updates/;   # به‌روزرسانی درون‌برنامه (version.json + APK)
        access_log off;
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:$SOCK;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX
ln -sfn "$NGINX_SITE" "/etc/nginx/sites-enabled/$APP"
[ -e /etc/nginx/sites-enabled/default ] && rm -f /etc/nginx/sites-enabled/default
nginx -t >/dev/null 2>&1 || { nginx -t; die "Invalid nginx config."; }
systemctl restart nginx   # restart (not reload) so www-data picks up the economy group
ok "nginx ready"

# --- 10) firewall ---
log "Configuring firewall (ufw)"
# Allow the ACTUAL SSH port(s) first so a custom port (e.g. 9011) never locks you out.
ssh_ports="$( { sshd -T 2>/dev/null | awk '/^port /{print $2}'; echo "${SSH_CONNECTION##* }"; } | grep -E '^[0-9]+$' | sort -u )"
[ -n "$ssh_ports" ] || ssh_ports=22
for p in $ssh_ports; do ufw allow "$p/tcp" >/dev/null 2>&1 || true; done
ufw allow 'Nginx Full' >/dev/null 2>&1 || true
ufw status | grep -q "Status: active" || yes | ufw enable >/dev/null 2>&1 || true
ok "Firewall: SSH ($(echo $ssh_ports | tr ' ' ',')) and web (80/443) allowed"

# --- 11) SSL certificate ---
if [ -n "$DOMAIN" ] && [ "$USE_SSL" -eq 1 ]; then
  log "Obtaining HTTPS certificate for $DOMAIN"
  CERT_DOMS=(-d "$DOMAIN"); case "$DOMAIN" in www.*) ;; *) CERT_DOMS+=(-d "www.$DOMAIN");; esac
  if certbot --nginx "${CERT_DOMS[@]}" --non-interactive --agree-tos -m "$EMAIL" --redirect; then
    ok "HTTPS enabled (auto-renew via certbot.timer)"
  else
    warn "Certificate failed (does the domain's DNS point to this server's IP?)."
    warn "After DNS is correct: sudo economyctl renew-cert"
  fi
fi

# --- 12) management CLI ---
install -m 0755 "$APPDIR/deploy/economyctl" /usr/local/bin/economyctl
ok "economyctl installed"

# --- summary ---
if [ -n "$DOMAIN" ] && [ "$USE_SSL" -eq 1 ]; then URL="https://$DOMAIN"; else URL="http://$(echo "$HOSTS" | cut -d, -f1)"; fi
printf '\n\033[1;32m========================================\033[0m\n'
printf ' Done.  Admin panel:  %s/admin/\n' "$URL"
printf ' Mobile API base:     %s/api/v1/\n\n' "$URL"
printf ' Next — create the admin account (phone + password):\n'
printf '     sudo economyctl superuser\n\n'
printf ' Management:\n'
printf '     economyctl status | logs | update | backup | help\n'
printf '\033[1;32m========================================\033[0m\n'
[ -n "$DOMAIN" ] || warn "No domain: admin login over HTTP is not secure. For real use, get a domain and re-run with --domain."
