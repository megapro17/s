#!/bin/bash
# bash <(curl -fsSL https://raw.githubusercontent.com/megapro17/s/refs/heads/master/2.sh)
set -euo pipefail

# ==========================================
# 0. Окружение и пользователь
# ==========================================
IS_TERMUX=false
if [[ -n "${TERMUX_VERSION:-}" || "${PREFIX:-}" == *"/com.termux/"* ]]; then
    IS_TERMUX=true
fi

if [[ "$IS_TERMUX" == true ]]; then
    TARGET_USER="$(id -un)"
    TARGET_GROUP="$(id -gn)"
    TARGET_HOME="${HOME:-/data/data/com.termux/files/home}"
else
    if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
        TARGET_USER="$SUDO_USER"
    else
        TARGET_USER="$(id -un)"
    fi

    if command -v getent >/dev/null 2>&1; then
        TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    else
        TARGET_HOME="${HOME:-}"
    fi
    TARGET_GROUP="$(id -gn "$TARGET_USER")"
fi

if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
    echo "❌ Не удалось определить домашний каталог: $TARGET_USER"
    exit 1
fi

SSH_DIR="$TARGET_HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"

# Функция безопасного chown (пропускается в Termux или без прав root)
safe_chown() {
    local owner_group="$1"
    local file_path="$2"

    if [[ "$IS_TERMUX" == false && "$(id -u)" -eq 0 ]]; then
        chown "$owner_group" "$file_path"
    fi
}

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
    safe_chown "$TARGET_USER:$TARGET_GROUP" "$SSH_DIR"
    echo "✅ Создан каталог $SSH_DIR"
else
    SSH_MODE="$(stat -c '%a' "$SSH_DIR" 2>/dev/null || stat -f '%Op' "$SSH_DIR" | tail -c 4)"
    if [[ "$SSH_MODE" != "700" ]]; then
        chmod 700 "$SSH_DIR"
        echo "✅ Исправлены права $SSH_DIR"
    fi
    safe_chown "$TARGET_USER:$TARGET_GROUP" "$SSH_DIR"
fi

# ==========================================
# 3. Проверяем authorized_keys
# ==========================================
if [[ -f "$AUTHORIZED_KEYS" ]] && [[ "$(cat "$AUTHORIZED_KEYS")" == "$KEYS" ]]; then
    echo "ℹ️ Ключи не изменились."
else
    printf '%s\n' "$KEYS" > "$AUTHORIZED_KEYS"
    echo "✅ Ключи обновлены."
fi

AK_MODE="$(stat -c '%a' "$AUTHORIZED_KEYS" 2>/dev/null || stat -f '%Op' "$AUTHORIZED_KEYS" | tail -c 4)"
if [[ "$AK_MODE" != "600" ]]; then
    chmod 600 "$AUTHORIZED_KEYS"
    echo "✅ Исправлены права authorized_keys"
fi
safe_chown "$TARGET_USER:$TARGET_GROUP" "$AUTHORIZED_KEYS"

# ==========================================
# 4. Настройка SSH
# ==========================================
SYS_PREFIX="${PREFIX:-}"
CONF_DIR="$SYS_PREFIX/etc/ssh/sshd_config.d"
CONF_FILE="$CONF_DIR/01-keys-only.conf"

DESIRED_CONF=$(cat <<'EOF'
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthenticationMethods publickey
EOF
)

# PermitRootLogin не имеет смысла внутри Termux, добавляем только на Linux
if [[ "$IS_TERMUX" == false ]]; then
    DESIRED_CONF="PermitRootLogin no"$'\n'"$DESIRED_CONF"
fi

mkdir -p "$CONF_DIR"

CURRENT_CONF=""
if [[ -f "$CONF_FILE" ]]; then
    CURRENT_CONF="$(cat "$CONF_FILE")"
fi

if [[ "$DESIRED_CONF" != "$CURRENT_CONF" ]]; then
    printf '%s\n' "$DESIRED_CONF" > "$CONF_FILE"
    echo "✅ Конфигурация SSH обновлена."
    echo "🔄 Перезапустите SSH сервер (в Termux: pkill sshd && sshd)."
else
    echo "ℹ️ Конфигурация SSH не изменилась."
fi

chmod 600 "$CONF_FILE"

# В Termux владельцем конфига должен оставаться текущий UID, на Linux — root
if [[ "$IS_TERMUX" == false ]]; then
    safe_chown "root:root" "$CONF_FILE"
fi
