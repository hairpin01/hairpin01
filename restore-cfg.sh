#!/usr/bin/env bash
set -euo pipefail

ROOT="my-cfg"
RESTORE_AUR=0
AUR_HELPER="yay"

usage() {
    cat <<EOF
Использование:
  $0 [путь-к-my-cfg] [--aur [helper]]

Примеры:
  $0
  $0 my-cfg --aur
  $0 /mnt/backup/my-cfg --aur paru
EOF
}

while (($#)); do
    case "$1" in
        --aur)
            RESTORE_AUR=1
            shift
            if (($#)) && [[ "$1" != --* ]]; then
                AUR_HELPER="$1"
                shift
            fi
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            ROOT="$1"
            shift
            ;;
    esac
done

[[ -d "$ROOT" ]] || {
    echo "Ошибка: каталог не найден: $ROOT" >&2
    exit 1
}

install_repo_packages() {
    local list="$ROOT/pacman-package/list.txt"
    local tmp pkg

    [[ -f "$list" ]] || {
        echo "Список репозиторных пакетов не найден: $list" >&2
        return
    }

    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' RETURN

    while IFS= read -r pkg || [[ -n "$pkg" ]]; do
        pkg="${pkg#"${pkg%%[![:space:]]*}"}"
        pkg="${pkg%"${pkg##*[![:space:]]}"}"
        [[ -z "$pkg" || "$pkg" == \#* ]] && continue

        if pacman -Si "$pkg" &>/dev/null; then
            printf '%s\n' "$pkg" >> "$tmp"
        else
            echo "Пропуск (не найден в репозиториях): $pkg" >&2
        fi
    done < "$list"

    if [[ -s "$tmp" ]]; then
        echo "Установка пакетов из официальных репозиториев..."
        xargs -r sudo pacman -S --needed < "$tmp"
    fi
}

install_aur_packages() {
    local list="$ROOT/aur-package/list.txt"

    (( RESTORE_AUR )) || return

    [[ -f "$list" ]] || {
        echo "Список AUR-пакетов не найден: $list" >&2
        return
    }

    command -v "$AUR_HELPER" &>/dev/null || {
        echo "Не найден AUR helper: $AUR_HELPER" >&2
        exit 1
    }

    echo "Установка AUR-пакетов через $AUR_HELPER..."
    grep -Ev '^[[:space:]]*(#|$)' "$list" |
        xargs -r "$AUR_HELPER" -S --needed
}

restore_archives() {
    local archive tmp entry bad home_dir

    command -v unzip &>/dev/null || {
        echo "Нужен пакет unzip." >&2
        exit 1
    }

    while IFS= read -r -d '' archive; do
        echo "Восстановление: $archive"
        bad=0

        while IFS= read -r entry; do
            if [[ ! "$entry" =~ ^home/[^/]+/ ]] ||
               [[ "$entry" =~ (^|/)\.\.(/|$) ]] ||
               [[ "$entry" == /* ]]; then
                echo "Небезопасный путь в архиве, пропуск: $entry" >&2
                bad=1
                break
            fi
        done < <(zipinfo -1 "$archive")

        (( bad == 0 )) || continue

        tmp="$(mktemp -d)"
        unzip -q "$archive" -d "$tmp"

        for home_dir in "$tmp"/home/*; do
            [[ -d "$home_dir" ]] || continue
            cp -a "$home_dir"/. "$HOME"/
        done

        rm -rf "$tmp"
    done < <(find "$ROOT" -type f -name 'cfg.zip' -print0)
}

install_repo_packages
install_aur_packages
restore_archives

echo "Готово."
