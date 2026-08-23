#!/usr/bin/env fish

set -l root my-cfg
set -l restore_aur 0
set -l aur_helper yay

function usage
    echo "Использование:"
    echo "  "(status filename)" [путь-к-my-cfg] [--aur [helper]]"
    echo
    echo "Примеры:"
    echo "  "(status filename)
    echo "  "(status filename)" my-cfg --aur"
    echo "  "(status filename)" /mnt/backup/my-cfg --aur paru"
end

while test (count $argv) -gt 0
    switch $argv[1]
        case --aur
            set restore_aur 1
            set -e argv[1]

            if test (count $argv) -gt 0
                if not string match -qr '^--' -- $argv[1]
                    set aur_helper $argv[1]
                    set -e argv[1]
                end
            end

        case -h --help
            usage
            exit 0

        case '*'
            set root $argv[1]
            set -e argv[1]
    end
end

if not test -d "$root"
    echo "Ошибка: каталог не найден: $root" >&2
    exit 1
end

function install_repo_packages
    set -l list "$root/pacman-package/list.txt"

    if not test -f "$list"
        echo "Список репозиторных пакетов не найден: $list" >&2
        return
    end

    set -l tmp (mktemp)

    while read -l pkg
        set pkg (string trim -- "$pkg")

        test -z "$pkg"; and continue
        string match -qr '^#' -- "$pkg"; and continue

        if pacman -Si "$pkg" >/dev/null 2>&1
            echo "$pkg" >> "$tmp"
        else
            echo "Пропуск (не найден в репозиториях): $pkg" >&2
        end
    end < "$list"

    if test -s "$tmp"
        echo "Установка пакетов из официальных репозиториев..."
        xargs -r sudo pacman -S --needed < "$tmp"
    end

    rm -f "$tmp"
end

function install_aur_packages
    test "$restore_aur" -eq 1; or return

    set -l list "$root/aur-package/list.txt"

    if not test -f "$list"
        echo "Список AUR-пакетов не найден: $list" >&2
        return
    end

    if not command -q "$aur_helper"
        echo "Не найден AUR helper: $aur_helper" >&2
        exit 1
    end

    echo "Установка AUR-пакетов через $aur_helper..."

    while read -l pkg
        set pkg (string trim -- "$pkg")

        test -z "$pkg"; and continue
        string match -qr '^#' -- "$pkg"; and continue

        "$aur_helper" -S --needed "$pkg"
    end < "$list"
end

function restore_archives
    if not command -q unzip
        echo "Нужен пакет unzip." >&2
        exit 1
    end

    for archive in (find "$root" -type f -name cfg.zip -print)
        echo "Восстановление: $archive"
        set -l bad 0

        for entry in (zipinfo -1 "$archive")
            if not string match -qr '^home/[^/]+/' -- "$entry"
                echo "Небезопасный путь в архиве, пропуск: $entry" >&2
                set bad 1
                break
            end

            if string match -qr '(^|/)\.\.(/|$)' -- "$entry"
                echo "Небезопасный путь в архиве, пропуск: $entry" >&2
                set bad 1
                break
            end
        end

        test "$bad" -eq 0; or continue

        set -l tmp (mktemp -d)
        unzip -q "$archive" -d "$tmp"

        for home_dir in "$tmp"/home/*
            test -d "$home_dir"; or continue
            cp -a "$home_dir"/. "$HOME"/
        end

        rm -rf "$tmp"
    end
end

install_repo_packages
install_aur_packages
restore_archives

echo "Готово."
