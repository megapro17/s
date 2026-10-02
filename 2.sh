#!/bin/bash
set -euo pipefail
#curl -fsSL https://raw.githubusercontent.com/megapro17/s/refs/heads/master/2.sh | bash

main() {
    # ==========================================
    # 0. Окружение и пользователь
    # ==========================================
    local is_termux=false
    if [[ -d "/data/data/com.termux" || "$(uname -o 2>/dev/null)" == "Android" || -n "${TERMUX_VERSION:-}" || "${PREFIX:-}" == *"/com.termux/"* ]]; then
        is_termux=true
        echo "ℹ️ Обнаружен Termux."
    fi

    local target_user target_group target_home
    if [[ "$is_termux" == true ]]; then
        target_user="$(id -un)"
        target_group="$(id -gn)"
        target_home="${HOME:-/data/data/com.termux/files/home}"
    else
        if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
            target_user="$SUDO_USER"
        else
            target_user="$(id -un)"
        fi

        if command -v getent >/dev/null 2>&1; then
            target_home="$(getent passwd "$target_user" | cut -d: -f6)"
        else
            target_home="${HOME:-}"
        fi
        target_group="$(id -gn "$target_user")"
    fi

    if [[ -z "$target_home" || ! -d "$target_home" ]]; then
        echo "❌ Не удалось определить домашний каталог: $target_user" >&2
        exit 1
    fi

    local ssh_dir="$target_home/.ssh"
    local authorized_keys="$ssh_dir/authorized_keys"

    # ==========================================
    # Вспомогательные функции (без лишних записей на диск)
    # ==========================================
    apply_mode() {
        local expected_mode="$1"
        local path="$2"
        local current_mode
        current_mode="$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Op' "$path" 2>/dev/null | tail -c 4 || true)"

        if [[ "$current_mode" != "$expected_mode" ]]; then
            chmod "$expected_mode" "$path"
            echo "✅ Исправлены права ($expected_mode): $path"
        fi
    }

    apply_owner() {
        local expected_owner_group="$1"
        local path="$2"

        # В Termux или без root вызов chown пропускается
        if [[ "$is_termux" == false && "$(id -u)" -eq 0 ]]; then
            local current_owner_group
            current_owner_group="$(stat -c '%U:%G' "$path" 2>/dev/null || true)"

            if [[ "$current_owner_group" != "$expected_owner_group" ]]; then
                chown "$expected_owner_group" "$path"
                echo "✅ Исправлен владелец ($expected_owner_group): $path"
            fi
        fi
    }

    # ==========================================
    # 1. Получаем ключи в оперативную память
    # ==========================================
    local keys
    keys="$(curl -fsSL https://github.com/megapro17.keys)" || {
        echo "❌ Ошибка: не удалось скачать ключи." >&2
        exit 1
    }

    if [[ -z "$keys" ]]; then
        echo "❌ Ошибка: GitHub вернул пустой список ключей." >&2
        exit 1
    fi

    # ==========================================
    # 2. Каталог ~/.ssh
    # ==========================================
    if [[ ! -d "$ssh_dir" ]]; then
        mkdir -p "$ssh_dir"
        echo "✅ Создан каталог $ssh_dir"
    fi

    apply_mode 700 "$ssh_dir"
    apply_owner "$target_user:$target_group" "$ssh_dir"

    # ==========================================
    # 3. Файл authorized_keys
    # ==========================================
    local current_keys=""
    if [[ -f "$authorized_keys" ]]; then
        current_keys="$(cat "$authorized_keys")"
    fi

    if [[ "$current_keys" == "$keys" ]]; then
        echo "ℹ️ Ключи не изменились."
    else
        printf '%s\n' "$keys" > "$authorized_keys"
        echo "✅ Ключи обновлены."
    fi

    apply_mode 600 "$authorized_keys"
    apply_owner "$target_user:$target_group" "$authorized_keys"

    # ==========================================
    # 4. Конфигурация SSH
    # ==========================================
    local sys_prefix="${PREFIX:-}"
    local conf_dir="$sys_prefix/etc/ssh/sshd_config.d"
    local conf_file="$conf_dir/01-keys-only.conf"

    local desired_conf
    desired_conf=$(cat <<'EOF'
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthenticationMethods publickey
EOF
    )

    if [[ "$is_termux" == false ]]; then
        desired_conf="PermitRootLogin no"$'\n'"$desired_conf"
    fi

    if [[ ! -d "$conf_dir" ]]; then
        mkdir -p "$conf_dir"
    fi

    local current_conf=""
    if [[ -f "$conf_file" ]]; then
        current_conf="$(cat "$conf_file")"
    fi

    if [[ "$desired_conf" != "$current_conf" ]]; then
        printf '%s\n' "$desired_conf" > "$conf_file"
        echo "✅ Конфигурация SSH обновлена."
        if [[ "$is_termux" == true ]]; then
            echo "🔄 Перезапустите SSH в Termux: pkill sshd && sshd"
        else
            echo "🔄 Перезапустите SSH сервер (например: systemctl restart ssh / sshd)."
        fi
    else
        echo "ℹ️ Конфигурация SSH не изменилась."
    fi

    apply_mode 600 "$conf_file"
    if [[ "$is_termux" == false ]]; then
        apply_owner "root:root" "$conf_file"
    fi
}

main "$@"
