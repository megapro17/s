#!/bin/bash

# ==========================================
# 1. ОБНОВЛЕНИЕ КЛЮЧЕЙ
# ==========================================
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

KEYS=$(curl -fsSL https://github.com/megapro17.keys)

if [ -n "$KEYS" ]; then
    if [ "$KEYS" != "$(cat ~/.ssh/authorized_keys)" ]; then
        printf "%s\n" "$KEYS" > ~/.ssh/authorized_keys
        echo "✅ Ключи успешно обновлены."
    else
        echo "ℹ️ Ключи не изменились. Запись пропущена."
    fi
else
    echo "❌ Ошибка: не удалось скачать ключи."
    exit 1
fi

# ==========================================
# 2. НАСТРОЙКА SSH (С ПРОВЕРКОЙ СОДЕРЖИМОГО)
# ==========================================
CONF_DIR="${PREFIX:-}/etc/ssh/sshd_config.d"
CONF_FILE="$CONF_DIR/01-keys-only.conf"

# Сохраняем нужный нам эталонный конфиг в переменную в памяти
DESIRED_CONF=$(cat << 'EOF'
# Отключаем все типы авторизации, кроме публичных ключей
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthenticationMethods publickey
EOF
)

mkdir -p "$CONF_DIR"

# Читаем текущий конфиг с диска (если он существует), иначе оставляем пустым
CURRENT_CONF=""
if [ -f "$CONF_FILE" ]; then
    CURRENT_CONF=$(cat "$CONF_FILE")
fi

# Сравниваем эталон с тем, что сейчас в файле
if [ "$DESIRED_CONF" != "$CURRENT_CONF" ]; then
    printf "%s\n" "$DESIRED_CONF" > "$CONF_FILE"
    echo "✅ Конфигурация SSH обновлена: $CONF_FILE"
    echo "🔄 Не забудьте перезапустить SSH сервер (например: systemctl restart ssh)."
else
    echo "ℹ️ Конфигурация SSH актуальна. Запись пропущена."
fi
