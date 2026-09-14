#!/bin/sh
# install.sh — установка MAX-for-OpenIPC на камеру с OpenIPC (BusyBox ash)
# Запуск (рекомендуется):
#   curl -fsSL https://raw.githubusercontent.com/AT-Lee/MAX-for-OpenIPC/main/install.sh -o /tmp/install.sh && sh /tmp/install.sh

REPO="AT-Lee/MAX-for-OpenIPC"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

MAJESTIC="/etc/majestic.yaml"
HEADER="/var/www/cgi-bin/p/header.cgi"

MENU_ANCHOR='<ul aria-labelledby="dropdownExtensions" class="dropdown-menu dropdown-menu-lg-end">'
MENU_ITEM='<li><a class="dropdown-item" href="/cgi-bin/ext-max.cgi">MAX</a></li>'

# --- выбор загрузчика ---
DOWNLOAD=""
if command -v curl >/dev/null 2>&1; then
    DOWNLOAD="curl -fsSL"
elif command -v wget >/dev/null 2>&1; then
    DOWNLOAD="wget -q -O"
else
    echo "Ошибка: необходим curl или wget" >&2
    exit 1
fi

download() {
    # $1 — URL, $2 — путь назначения
    if echo "$DOWNLOAD" | grep -q curl; then
        curl -fsSL "$1" -o "$2"
    else
        wget -q "$1" -O "$2"
    fi
}

mkdir -p /usr/sbin /etc/webui /var/www/cgi-bin || {
    echo "Ошибка: не удалось создать директории" >&2
    exit 1
}

# --- загрузка файлов ---
echo "→ Загрузка max..."
[ -f /usr/sbin/max ] && cp /usr/sbin/max /usr/sbin/max.bak
download "${BASE_URL}/max" "/usr/sbin/max" || {
    echo "Ошибка загрузки max" >&2
    exit 1
}

echo "→ Загрузка max.conf..."
[ -f /etc/webui/max.conf ] && cp /etc/webui/max.conf /etc/webui/max.conf.bak
download "${BASE_URL}/max.conf" "/etc/webui/max.conf" || {
    echo "Ошибка загрузки max.conf" >&2
    exit 1
}

echo "→ Загрузка ext-max.cgi..."
[ -f /var/www/cgi-bin/ext-max.cgi ] && cp /var/www/cgi-bin/ext-max.cgi /var/www/cgi-bin/ext-max.cgi.bak
download "${BASE_URL}/ext-max.cgi" "/var/www/cgi-bin/ext-max.cgi" || {
    echo "Ошибка загрузки ext-max.cgi" >&2
    exit 1
}

chmod +x /usr/sbin/max /var/www/cgi-bin/ext-max.cgi

# --- включение hls и motionDetect в majestic.yaml ---
if [ -f "$MAJESTIC" ]; then
    echo "→ Включение hls и motionDetect в $MAJESTIC..."
    cp "$MAJESTIC" "${MAJESTIC}.bak"

    awk '
    BEGIN { in_hls=0; in_md=0; hls_done=0; md_done=0; hls_present=0; md_present=0 }

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

    in_hls && /^[ \t]+enabled:/ {
        match($0, /^[ \t]+/)
        indent = substr($0, 1, RLENGTH)
        print indent "enabled: true"
        hls_done=1
        next
    }

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
        echo "   ✓ hls и motionDetect включены"
    else
        rm -f "${MAJESTIC}.tmp"
        echo "⚠ Не удалось обработать $MAJESTIC — оставлен без изменений" >&2
    fi
else
    echo "⚠ Файл $MAJESTIC не найден — пропускаем настройку"
fi

# --- добавление пункта меню в header.cgi ---
if [ -f "$HEADER" ]; then
    if grep -q 'ext-max.cgi' "$HEADER"; then
        echo "→ Пункт меню MAX уже присутствует в header.cgi"
    else
        echo "→ Добавление пункта меню в header.cgi..."
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
