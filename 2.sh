#!/bin/bash

set -euo pipefail

# ==========================================
# 0. Определяем пользователя
# ==========================================
if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    TARGET_USER="$SUDO_USER"
else
    TARGET_USER="$(id -un)"
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "$TARGET_USER")"

if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
    echo "❌ Не удалось определить домашний каталог: $TARGET_USER"
    exit 1
fi

SSH_DIR="$TARGET_HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"

# ==========================================
# 1. Получаем ключи в память
# ==========================================
KEYS="$(curl -fsSL https://github.com/megapro17.keys)" || {
    echo "❌ Ошибка: не удалось скачать ключи."
    exit 1
}

if [[ -z "$KEYS" ]]; then
    echo "❌ Ошибка: GitHub вернул пустой список ключей."
    exit 1
fi

# ==========================================
# 2. Проверяем ~/.ssh
# ==========================================
if [[ ! -d "$SSH_DIR" ]]; then
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    chown "$TARGET_USER:$TARGET_GROUP" "$SSH_DIR"
    echo "✅ Создан $SSH_DIR"
else
    SSH_MODE="$(stat -c '%a' "$SSH_DIR")"
    SSH_OWNER="$(stat -c '%U' "$SSH_DIR")"
    SSH_GROUP="$(stat -c '%G' "$SSH_DIR")"

    if [[ "$SSH_MODE" != "700" ]]; then
        chmod 700 "$SSH_DIR"
        echo "✅ Исправлены права $SSH_DIR"
    fi

    if [[ "$SSH_OWNER" != "$TARGET_USER" || "$SSH_GROUP" != "$TARGET_GROUP" ]]; then
        chown "$TARGET_USER:$TARGET_GROUP" "$SSH_DIR"
        echo "✅ Исправлен владелец $SSH_DIR"
    fi
fi

# ==========================================
# 3. Проверяем authorized_keys
# ==========================================
if [[ -f "$AUTHORIZED_KEYS" ]] &&
   [[ "$(cat "$AUTHORIZED_KEYS")" == "$KEYS" ]]; then
    echo "ℹ️ Ключи не изменились."
else
    printf '%s\n' "$KEYS" > "$AUTHORIZED_KEYS"
    echo "✅ Ключи обновлены."
fi

# Проверяем права/владельца только при необходимости
AK_MODE="$(stat -c '%a' "$AUTHORIZED_KEYS")"
AK_OWNER="$(stat -c '%U' "$AUTHORIZED_KEYS")"
AK_GROUP="$(stat -c '%G' "$AUTHORIZED_KEYS")"

if [[ "$AK_MODE" != "600" ]]; then
    chmod 600 "$AUTHORIZED_KEYS"
    echo "✅ Исправлены права authorized_keys"
fi

if [[ "$AK_OWNER" != "$TARGET_USER" || "$AK_GROUP" != "$TARGET_GROUP" ]]; then
    chown "$TARGET_USER:$TARGET_GROUP" "$AUTHORIZED_KEYS"
    echo "✅ Исправлен владелец authorized_keys"
fi

# ==========================================
# 4. Настройка SSH
# ==========================================
CONF_DIR="${PREFIX:-}/etc/ssh/sshd_config.d"
CONF_FILE="$CONF_DIR/01-keys-only.conf"

DESIRED_CONF=$(cat <<'EOF'
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthenticationMethods publickey
EOF
)

if [[ ! -d "$CONF_DIR" ]]; then
    mkdir -p "$CONF_DIR"
fi

if [[ -f "$CONF_FILE" ]]; then
    CURRENT_CONF="$(cat "$CONF_FILE")"
else
    CURRENT_CONF=""
fi

if [[ "$DESIRED_CONF" != "$CURRENT_CONF" ]]; then
    printf '%s\n' "$DESIRED_CONF" > "$CONF_FILE"
    echo "✅ Конфигурация SSH обновлена."
    echo "🔄 Перезапустите SSH сервер."
else
    echo "ℹ️ Конфигурация SSH не изменилась."
fi

# Проверяем права/владельца конфигурации только при необходимости
CONF_MODE="$(stat -c '%a' "$CONF_FILE")"
CONF_OWNER="$(stat -c '%U' "$CONF_FILE")"
CONF_GROUP="$(stat -c '%G' "$CONF_FILE")"

if [[ "$CONF_MODE" != "600" ]]; then
    chmod 600 "$CONF_FILE"
    echo "✅ Исправлены права $CONF_FILE"
fi

if [[ "$CONF_OWNER" != "root" || "$CONF_GROUP" != "root" ]]; then
    chown root:root "$CONF_FILE"
    echo "✅ Исправлен владелец $CONF_FILE"
fi
