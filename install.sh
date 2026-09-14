cat > /tmp/install.sh << 'ENDOFSCRIPT'
#!/bin/sh
REPO="AT-Lee/MAX-for-OpenIPC"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

MAJESTIC="/etc/majestic.yaml"
HEADER="/var/www/cgi-bin/p/header.cgi"
MENU_ANCHOR='<ul aria-labelledby="dropdownExtensions" class="dropdown-menu dropdown-menu-lg-end">'
MENU_ITEM='<li><a class="dropdown-item" href="/cgi-bin/ext-max.cgi">MAX</a></li>'

HAS_CURL=0
if command -v curl >/dev/null 2>&1; then
    HAS_CURL=1
fi
if [ "$HAS_CURL" = "0" ]; then
    if ! command -v wget >/dev/null 2>&1; then
        echo "ERROR: need curl or wget"
        exit 1
    fi
fi

download() {
    if [ "$HAS_CURL" = "1" ]; then
        curl -fsSL "$1" -o "$2"
    else
        wget -q "$1" -O "$2"
    fi
}

mkdir -p /usr/sbin /etc/webui /var/www/cgi-bin

echo "-> downloading max"
if [ -f /usr/sbin/max ]; then cp /usr/sbin/max /usr/sbin/max.bak; fi
download "${BASE_URL}/max" "/usr/sbin/max"

echo "-> downloading max.conf"
if [ -f /etc/webui/max.conf ]; then cp /etc/webui/max.conf /etc/webui/max.conf.bak; fi
download "${BASE_URL}/max.conf" "/etc/webui/max.conf"

echo "-> downloading ext-max.cgi"
if [ -f /var/www/cgi-bin/ext-max.cgi ]; then cp /var/www/cgi-bin/ext-max.cgi /var/www/cgi-bin/ext-max.cgi.bak; fi
download "${BASE_URL}/ext-max.cgi" "/var/www/cgi-bin/ext-max.cgi"

chmod +x /usr/sbin/max /var/www/cgi-bin/ext-max.cgi

if [ -f "$MAJESTIC" ]; then
    echo "-> enabling hls and motionDetect in $MAJESTIC"
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
        echo "   OK"
    else
        rm -f "${MAJESTIC}.tmp"
        echo "   WARN: could not process $MAJESTIC"
    fi
else
    echo "WARN: $MAJESTIC not found"
fi

if [ -f "$HEADER" ]; then
    if grep -q 'ext-max.cgi' "$HEADER"; then
        echo "-> menu item already present in header.cgi"
    else
        echo "-> adding menu item to header.cgi"
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
            echo "   OK"
        else
            rm -f "${HEADER}.tmp"
            echo "   WARN: could not process $HEADER"
        fi
    fi
else
    echo "WARN: $HEADER not found"
fi

echo ""
echo "DONE. Restart majestic and open Extensions -> MAX."
ENDOFSCRIPT
sh /tmp/install.sh
