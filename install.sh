#!/bin/sh
# install.sh — установка MAX-for-OpenIPC на камеру с OpenIPC
# Использование:
#   curl -fsSL https://raw.githubusercontent.com/AT-Lee/MAX-for-OpenIPC/main/install.sh | sh

set -e

REPO="AT-Lee/MAX-for-OpenIPC"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

MAJESTIC="/etc/majestic.yaml"
HEADER="/var/www/cgi-bin/p/header.cgi"

MENU_ANCHOR='<ul aria-labelledby="dropdownExtensions" class="dropdown-menu dropdown-menu-lg-end">'
MENU_ITEM='<li><a class="dropdown-item" href="/cgi-bin/ext-max.cgi">MAX</a></li>'

# --- проверка утилит для скачивания ---
if command -v curl >/dev/null 2>&1; then
    download() { curl -fsSL "$1" -o "$2"; }
elif command -v wget >/dev/null 2>&1; then
    download() { wget -q "$1" -O "$2"; }
else
    echo "Ошибка: необходим curl или wget" >&2
    exit 1
fi

mkdir -p /usr/sbin /etc/webui /var/www/cgi-bin

# --- загрузка файлов ---
echo "→ Загрузка max..."
if [ -f /usr/sbin/max ]; then cp /usr/sbin/max /usr/sbin/max.bak; fi
download "${BASE_URL}/max" "/usr/sbin/max"

echo "→ Загрузка max.conf..."
if [ -f /etc/webui/max.conf ]; then cp /etc/webui/max.conf /etc/webui/max.conf.bak; fi
download "${BASE_URL}/max.conf" "/etc/webui/max.conf"

echo "→ Загрузка ext-max.cgi..."
if [ -f /var/www/cgi-bin/ext-max.cgi ]; then cp /var/www/cgi-bin/ext-max.cgi /var/www/cgi-bin/ext-max.cgi.bak; fi
download "${BASE_URL}/ext-max.cgi" "/var/www/cgi-bin/ext-max.cgi"

chmod +x /usr/sbin/max
chmod +x /var/www/cgi-bin/ext-max.cgi

# --- включение hls и motionDetect в majestic.yaml ---
if [ -f "$MAJESTIC" ]; then
    echo "→ Включение hls и motionDetect в $MAJESTIC..."
    cp "$MAJESTIC" "${MAJESTIC}.bak"

    awk '
    BEGIN { in_hls=0; in_md=0; hls_done=0; md_done=0; hls_present=0; md_present=0 }

    # топ-уровневые ключи YAML (без ведущих пробелов)
    /^[A-Za-z][A-Za-z0-9_]*:/ {
        if (in_hls && !hls_done) { print "  enabled: true"; hls_done=1 }
        if (in_md  && !md_done)  { print "  enabled: true"; md_done=1  }
        in_hls = ($0 ~ /^hls:/)
        in_md  = ($0 ~ /^motionDetect:/)
        if (in_hls) hls_present=1
        if (in_md)  md_present=1
        print
        next
    }

    # внутри секции hls — заменяем enabled на true (сохраняя отступ)
    in_hls && /^[ \t]+enabled:/ {
        match($0, /^[ \t]+/)
        indent = substr($0, 1, RLENGTH)
        print indent "enabled: true"
        hls_done=1
        next
    }

    # внутри секции motionDetect — аналогично
    in_md && /^[ \t]+enabled:/ {
        match($0, /^[ \t]+/)
        indent = substr($0, 1, RLENGTH)
        print indent "enabled: true"
        md_done=1
        next
    }

    { print }

    END {
        if (in_hls && !hls_done) print "  enabled: true"
        if (in_md  && !md_done)  print "  enabled: true"
        if (!hls_present) { print ""; print "hls:";          print "  enabled: true" }
        if (!md_present)  { print ""; print "motionDetect:"; print "  enabled: true" }
    }
    ' "$MAJESTIC" > "${MAJESTIC}.tmp"

    if [ -s "${MAJESTIC}.tmp" ]; then
        mv "${MAJESTIC}.tmp" "$MAJESTIC"
    else
        rm -f "${MAJESTIC}.tmp"
        echo "⚠ Не удалось обработать $MAJESTIC — оставлен без изменений" >&2
    fi
else
    echo "⚠ Файл $MAJESTIC не найден — пропускаем настройку"
fi

# --- добавление пункта меню в header.cgi после открывающего <ul> Extensions ---
if [ -f "$HEADER" ]; then
    if grep -q 'ext-max.cgi' "$HEADER"; then
        echo "→ Пункт меню MAX уже присутствует в header.cgi"
    else
        echo "→ Добавление пункта меню в header.cgi после строки Extensions..."
        cp "$HEADER" "${HEADER}.bak"

        awk -v anchor="$MENU_ANCHOR" -v item="$MENU_ITEM" '
            !inserted && index($0, anchor) > 0 {
                print
                print "                    " item
                inserted = 1
                next
            }
            { print }
        ' "$HEADER" > "${HEADER}.tmp"

        if [ -s "${HEADER}.tmp" ]; then
            mv "${HEADER}.tmp" "$HEADER"
            echo "   ✓ Пункт меню добавлен"
        else
            rm -f "${HEADER}.tmp"
            echo "⚠ Не удалось обработать $HEADER" >&2
        fi
    fi
else
    echo "⚠ Файл $HEADER не найден — пропускаем добавление меню"
fi

echo ""
echo "✅ Установка MAX-for-OpenIPC завершена."
echo "   • max          → /usr/sbin/max"
echo "   • max.conf     → /etc/webui/max.conf"
echo "   • ext-max.cgi  → /var/www/cgi-bin/ext-max.cgi"
echo "   • hls и motionDetect включены в $MAJESTIC"
echo ""
echo "Резервные копии сохранены рядом с изменёнными файлами (*.bak)."
echo "Перезапустите majestic (например, через веб-UI или killall -HUP majestic)."
echo "Далее откройте: Extensions → MAX и укажите токен бота и ID чата."