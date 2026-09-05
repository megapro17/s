```bash
#!/bin/bash

set -e

# ==========================================
# Определяем целевого пользователя
# ==========================================
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    TARGET_USER="$SUDO_USER"
else
    TARGET_USER="$(id -un)"
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
    echo "❌ Не удалось определить домашний каталог пользователя: $TARGET_USER"
    exit 1
fi

SSH_DIR="$TARGET_HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"

# ==========================================
# 1. ОБНОВЛЕНИЕ КЛЮЧЕЙ
# ==========================================
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

touch "$AUTHORIZED_KEYS"
chmod 600 "$AUTHORIZED_KEYS"

KEYS=$(curl -fsSL https://github.com/megapro17.keys)

if [ -n "$KEYS" ]; then
    if printf "%s\n" "$KEYS" | cmp -s - "$AUTHORIZED_KEYS"; then
        echo "ℹ️ Ключи не изменились. Запись пропущена."
    else
        printf "%s\n" "$KEYS" > "$AUTHORIZED_KEYS"
        chown "$TARGET_USER:$TARGET_USER" "$AUTHORIZED_KEYS"
        chown "$TARGET_USER:$TARGET_USER" "$SSH_DIR"
        echo "✅ Ключи успешно обновлены для пользователя: $TARGET_USER"
    fi
else
    echo "❌ Ошибка: не удалось скачать ключи."
    exit 1
fi

# ==========================================
# 2. НАСТРОЙКА SSH
# ==========================================
CONF_DIR="${PREFIX:-}/etc/ssh/sshd_config.d"
CONF_FILE="$CONF_DIR/01-keys-only.conf"

DESIRED_CONF=$(cat << 'EOF'
# Отключаем все типы авторизации, кроме публичных ключей
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthenticationMethods publickey
EOF
)

mkdir -p "$CONF_DIR"

CURRENT_CONF=""
if [ -f "$CONF_FILE" ]; then
    CURRENT_CONF=$(cat "$CONF_FILE")
fi

if [ "$DESIRED_CONF" != "$CURRENT_CONF" ]; then
    printf "%s\n" "$DESIRED_CONF" > "$CONF_FILE"
    echo "✅ Конфигурация SSH обновлена: $CONF_FILE"
    echo "🔄 Не забудьте перезапустить SSH сервер."
else
    echo "ℹ️ Конфигурация SSH актуальна. Запись пропущена."
fi
```
