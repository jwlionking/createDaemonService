#!/usr/bin/env bash
# Create, preview, enable, or remove a systemd service for a daemon.
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
UNIT_DIR="${UNIT_DIR:-/etc/systemd/system}"

usage() {
  cat <<EOF
Usage:
  sudo $SCRIPT_NAME [options]              Interactive if required fields are missing
  sudo $SCRIPT_NAME --name NAME --exec PATH [options]
  $SCRIPT_NAME --dry-run --name NAME --exec PATH [options]
  sudo $SCRIPT_NAME --remove NAME

Options:
  -n, --name NAME          systemd unit name (without .service)
  -x, --exec PATH          daemon binary (absolute path, or a name on PATH)
  -a, --args ARGS          extra arguments passed to ExecStart
  -u, --user USER          Unix user to run as (default: root)
  -g, --group GROUP        Unix group (default: same as --user)
  -d, --description TEXT   unit Description
      --workdir DIR        WorkingDirectory=
      --datadir DIR        append -datadir=DIR (coin-style daemons)
      --conf FILE          append -conf=FILE
      --type TYPE          simple (default), forking, or notify
      --pidfile FILE       PIDFile= (forking)
      --limit-nofile N     LimitNOFILE= (default: 65535)
      --harden             add PrivateTmp/PrivateDevices/MemoryDenyWriteExecute
      --no-harden          disable extra hardening (default)
      --enable             enable on boot
      --no-enable          do not enable
      --start              start immediately after install
      --dry-run            print the unit to stdout; do not write
      --output FILE        write unit to FILE instead of $UNIT_DIR
      --force              overwrite an existing unit
      --remove NAME        stop, disable, and delete the unit
  -h, --help               show this help

Examples:
  sudo $SCRIPT_NAME --name realichaind --exec /usr/local/bin/realichaind --user realichain --enable --start
  $SCRIPT_NAME --dry-run --name myapp --exec ./myapp --args "--port 8080" --user www-data
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

confirm() {
  local prompt="$1"
  local default="${2:-n}"
  local reply
  if [[ ! -t 0 ]]; then
    [[ "$default" == "y" ]]
    return
  fi
  if [[ "$default" == "y" ]]; then
    read -r -p "$prompt [Y/n] " reply || true
    [[ -z "$reply" || "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
  else
    read -r -p "$prompt [y/N] " reply || true
    [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
  fi
}

valid_unit_name() {
  [[ "$1" =~ ^[A-Za-z0-9:_.@\\-]+$ ]] || return 1
  [[ "$1" != "." && "$1" != ".." ]]
}

resolve_exec() {
  local candidate="$1"
  local found=""
  if [[ -z "$candidate" ]]; then
    return 1
  fi
  if [[ "$candidate" == /* ]]; then
    [[ -x "$candidate" && -f "$candidate" ]] || return 1
    printf '%s\n' "$candidate"
    return 0
  fi
  if [[ -x "$candidate" && -f "$candidate" ]]; then
    readlink -f "$candidate"
    return 0
  fi
  found="$(command -v "$candidate" 2>/dev/null || true)"
  if [[ -n "$found" && -x "$found" ]]; then
    printf '%s\n' "$found"
    return 0
  fi
  local dir
  for dir in /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin; do
    if [[ -x "$dir/$candidate" ]]; then
      printf '%s\n' "$dir/$candidate"
      return 0
    fi
  done
  return 1
}

systemd_quote() {
  # Quote a token for systemd ExecStart (whitespace / quotes).
  local value="$1"
  if [[ "$value" =~ [[:space:]\'\"\\] ]]; then
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
  else
    printf '%s' "$value"
  fi
}

user_exists() {
  id -u "$1" >/dev/null 2>&1
}

group_exists() {
  getent group "$1" >/dev/null 2>&1
}

strip_trailing_d() {
  local name="$1"
  if [[ "$name" == *d && "$name" != "d" ]]; then
    printf '%s\n' "${name%d}"
  else
    printf '%s\n' "$name"
  fi
}

title_case() {
  local name="$1"
  printf '%s%s\n' "$(printf '%s' "${name:0:1}" | tr '[:lower:]' '[:upper:]')" "${name:1}"
}

generate_unit() {
  local exec_line description after
  exec_line="$(systemd_quote "$EXEC_PATH")"
  if [[ -n "$ARGS" ]]; then
    exec_line="$exec_line $ARGS"
  fi
  if [[ -n "$CONF" ]]; then
    exec_line="$exec_line $(systemd_quote "-conf=${CONF}")"
  fi
  if [[ -n "$DATADIR" ]]; then
    exec_line="$exec_line $(systemd_quote "-datadir=${DATADIR}")"
  fi

  description="${DESCRIPTION:-$(title_case "$BASE_NAME") daemon}"
  after="network-online.target"
  [[ "$TYPE" == "notify" ]] && after="network-online.target nss-lookup.target"

  cat <<EOF
[Unit]
Description=${description}
Documentation=man:systemd.service(5)
After=${after}
Wants=network-online.target

[Service]
Type=${TYPE}
User=${RUN_USER}
Group=${RUN_GROUP}
ExecStart=${exec_line}
Restart=on-failure
RestartSec=10
TimeoutStartSec=300
TimeoutStopSec=120
KillMode=mixed
KillSignal=SIGTERM
LimitNOFILE=${LIMIT_NOFILE}
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${NAME}
EOF

  if [[ -n "$WORKDIR" ]]; then
    printf 'WorkingDirectory=%s\n' "$WORKDIR"
  fi
  if [[ "$TYPE" == "forking" && -n "$PIDFILE" ]]; then
    printf 'PIDFile=%s\n' "$PIDFILE"
  fi
  if [[ "$HARDEN" == "1" ]]; then
    cat <<'EOF'
PrivateTmp=true
PrivateDevices=true
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
MemoryDenyWriteExecute=true
EOF
  else
    cat <<'EOF'
PrivateTmp=true
NoNewPrivileges=true
EOF
  fi

  cat <<'EOF'

[Install]
WantedBy=multi-user.target
EOF
}

remove_unit() {
  local name="$1"
  local unit="${UNIT_DIR}/${name}.service"
  need_cmd systemctl
  [[ "$(id -u)" -eq 0 ]] || die "removing a system unit requires root (try sudo)"
  valid_unit_name "$name" || die "invalid unit name: $name"

  if systemctl list-unit-files "${name}.service" >/dev/null 2>&1; then
    systemctl stop "${name}.service" 2>/dev/null || true
    systemctl disable "${name}.service" 2>/dev/null || true
  fi
  if [[ -f "$unit" ]]; then
    rm -f "$unit"
    systemctl daemon-reload
    echo "Removed ${unit}"
  else
    die "unit file not found: $unit"
  fi
}

NAME=""
EXEC=""
EXEC_PATH=""
ARGS=""
RUN_USER="root"
RUN_GROUP=""
DESCRIPTION=""
WORKDIR=""
DATADIR=""
CONF=""
TYPE="simple"
PIDFILE=""
LIMIT_NOFILE="65535"
HARDEN="0"
ENABLE=""
START="0"
DRY_RUN="0"
OUTPUT=""
FORCE="0"
REMOVE=""
BASE_NAME=""
USER_FROM_CLI="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--name)
      [[ -n "${2:-}" ]] || die "$1 requires a value"
      NAME="$2"; shift 2 ;;
    -x|--exec)
      [[ -n "${2:-}" ]] || die "$1 requires a value"
      EXEC="$2"; shift 2 ;;
    -a|--args)
      [[ -n "${2:-}" ]] || die "$1 requires a value"
      ARGS="$2"; shift 2 ;;
    -u|--user)
      [[ -n "${2:-}" ]] || die "$1 requires a value"
      RUN_USER="$2"; USER_FROM_CLI="1"; shift 2 ;;
    -g|--group)
      [[ -n "${2:-}" ]] || die "$1 requires a value"
      RUN_GROUP="$2"; shift 2 ;;
    -d|--description)
      [[ -n "${2:-}" ]] || die "$1 requires a value"
      DESCRIPTION="$2"; shift 2 ;;
    --workdir)
      [[ -n "${2:-}" ]] || die "$1 requires a value"
      WORKDIR="$2"; shift 2 ;;
    --datadir)
      [[ -n "${2:-}" ]] || die "$1 requires a value"
      DATADIR="$2"; shift 2 ;;
    --conf)
      [[ -n "${2:-}" ]] || die "$1 requires a value"
      CONF="$2"; shift 2 ;;
    --type)
      [[ -n "${2:-}" ]] || die "$1 requires a value"
      TYPE="$2"; shift 2 ;;
    --pidfile)
      [[ -n "${2:-}" ]] || die "$1 requires a value"
      PIDFILE="$2"; shift 2 ;;
    --limit-nofile)
      [[ -n "${2:-}" ]] || die "$1 requires a value"
      LIMIT_NOFILE="$2"; shift 2 ;;
    --harden) HARDEN="1"; shift ;;
    --no-harden) HARDEN="0"; shift ;;
    --enable) ENABLE="1"; shift ;;
    --no-enable) ENABLE="0"; shift ;;
    --start) START="1"; shift ;;
    --dry-run) DRY_RUN="1"; shift ;;
    --output)
      [[ -n "${2:-}" ]] || die "$1 requires a value"
      OUTPUT="$2"; shift 2 ;;
    --force) FORCE="1"; shift ;;
    --remove)
      [[ -n "${2:-}" ]] || die "$1 requires a value"
      REMOVE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

if [[ -n "$REMOVE" ]]; then
  remove_unit "$REMOVE"
  exit 0
fi

if [[ -z "$NAME" && -t 0 ]]; then
  read -r -p "Daemon / service name (e.g. realichaind): " NAME
fi
[[ -n "$NAME" ]] || die "service name is required"
valid_unit_name "$NAME" || die "invalid systemd unit name '$NAME' (use letters, digits, : _ . @ -)"

BASE_NAME="$(strip_trailing_d "$NAME")"

if [[ -z "$EXEC" && -t 0 ]]; then
  read -r -p "Binary path or name on PATH [${NAME}]: " EXEC
  EXEC="${EXEC:-$NAME}"
fi
[[ -n "$EXEC" ]] || die "binary (--exec) is required"

if ! EXEC_PATH="$(resolve_exec "$EXEC")"; then
  if [[ "$DRY_RUN" == "1" ]]; then
    if [[ "$EXEC" == /* ]]; then
      EXEC_PATH="$EXEC"
    else
      EXEC_PATH="/usr/local/bin/${EXEC}"
    fi
    echo "warning: binary '$EXEC' not found; using $EXEC_PATH for dry-run" >&2
  else
    die "cannot find executable '$EXEC'. Pass an absolute path with --exec."
  fi
fi

if [[ -z "$ARGS" && -t 0 ]]; then
  read -r -p "Extra arguments (optional): " ARGS || true
fi

if [[ "$USER_FROM_CLI" != "1" && -t 0 ]]; then
  read -r -p "Run as user [root]: " tmp_user || true
  RUN_USER="${tmp_user:-$RUN_USER}"
fi

if [[ -z "$RUN_GROUP" ]]; then
  RUN_GROUP="$RUN_USER"
fi

if [[ -t 0 && "$DRY_RUN" != "1" && -z "$OUTPUT" ]]; then
  if [[ -z "${DESCRIPTION}" ]]; then
    read -r -p "Description [$(title_case "$BASE_NAME") daemon]: " DESCRIPTION || true
  fi
  if [[ "$ENABLE" == "" ]]; then
    if confirm "Enable on boot?" y; then ENABLE="1"; else ENABLE="0"; fi
  fi
  if [[ "$START" == "0" ]]; then
    if confirm "Start the service now?" n; then START="1"; fi
  fi
fi

[[ "$TYPE" == "simple" || "$TYPE" == "forking" || "$TYPE" == "notify" ]] || die "--type must be simple, forking, or notify"
[[ "$LIMIT_NOFILE" =~ ^[0-9]+$ ]] || die "--limit-nofile must be a number"

if [[ "$TYPE" == "forking" && -z "$PIDFILE" ]]; then
  if [[ "$RUN_USER" == "root" ]]; then
    PIDFILE="/root/.${BASE_NAME}/${BASE_NAME}.pid"
  else
    PIDFILE="/run/${NAME}.pid"
  fi
fi

if [[ "$DRY_RUN" != "1" && -z "$OUTPUT" ]]; then
  [[ "$(id -u)" -eq 0 ]] || die "installing a system unit requires root (use sudo, or --dry-run / --output)"
  need_cmd systemctl
  if [[ "$RUN_USER" != "root" ]]; then
    user_exists "$RUN_USER" || die "user '$RUN_USER' does not exist"
  fi
  if [[ "$RUN_GROUP" != "root" ]]; then
    group_exists "$RUN_GROUP" || die "group '$RUN_GROUP' does not exist"
  fi
  if [[ -n "$WORKDIR" && ! -d "$WORKDIR" ]]; then
    die "working directory does not exist: $WORKDIR"
  fi
fi

UNIT_TEXT="$(generate_unit)"
TARGET="${OUTPUT:-${UNIT_DIR}/${NAME}.service}"

if [[ "$DRY_RUN" == "1" ]]; then
  printf '%s\n' "$UNIT_TEXT"
  exit 0
fi

if [[ -t 0 && -z "$OUTPUT" && "$FORCE" != "1" ]]; then
  echo
  echo "----- ${TARGET} -----"
  printf '%s\n' "$UNIT_TEXT"
  echo "---------------------"
  confirm "Write this unit file?" y || { echo "Canceled."; exit 1; }
fi

if [[ -e "$TARGET" && "$FORCE" != "1" ]]; then
  if [[ -t 0 ]]; then
    confirm "Overwrite existing $TARGET?" n || die "refusing to overwrite $TARGET (use --force)"
  else
    die "refusing to overwrite $TARGET (use --force)"
  fi
fi

umask 022
mkdir -p "$(dirname "$TARGET")"
printf '%s\n' "$UNIT_TEXT" > "$TARGET"
chmod 644 "$TARGET"
echo "Wrote $TARGET"

if [[ -z "$OUTPUT" ]]; then
  systemctl daemon-reload
  if [[ "${ENABLE:-0}" == "1" ]]; then
    systemctl enable "${NAME}.service"
    echo "Enabled ${NAME}.service"
  fi
  if [[ "$START" == "1" ]]; then
    systemctl start "${NAME}.service"
    echo "Started ${NAME}.service"
    systemctl --no-pager --full status "${NAME}.service" || true
  fi
  echo
  echo "Logs:    journalctl -u ${NAME} -f"
  echo "Status:  systemctl status ${NAME}"
  echo "Stop:    systemctl stop ${NAME}"
  echo "Remove:  sudo $SCRIPT_NAME --remove ${NAME}"
fi
