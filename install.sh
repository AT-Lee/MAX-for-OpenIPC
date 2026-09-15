#!/bin/sh
# ============================================================================
# MAX-for-OpenIPC — one-command installer
#
# Install on an OpenIPC camera (SSH console, as root):
#   curl -fsSL https://raw.githubusercontent.com/AT-Lee/MAX-for-OpenIPC/refs/heads/main/install.sh | sh -s --
#   wget -qO-  https://raw.githubusercontent.com/AT-Lee/MAX-for-OpenIPC/refs/heads/main/install.sh | sh -s --
#
# Re-run the same command to update an existing installation.
#
# Options (after "sh -s --"):
#   --uninstall   remove MAX-for-OpenIPC from the camera
#   --no-motion   do not create/patch the /usr/sbin/motion.sh hook
#   --no-menu     do not patch the web UI menu (header.cgi)
#   --no-restart  do not restart majestic (even if majestic.yaml was changed)
#   --force       suppress environment warnings
#   -h, --help    show this help
#
# Environment (advanced / testing):
#   REPO, BRANCH      install from another repository or branch
#   SRC_DIR=/path     install files from a local directory (offline install,
#                     e.g. from an SD card mounted at /mnt/mmcblk0p1)
#   ROOT=/path        install into a different root (for testing)
# ============================================================================

REPO="${REPO:-AT-Lee/MAX-for-OpenIPC}"
BRANCH="${BRANCH:-main}"
SRC_DIR="${SRC_DIR:-}"
ROOT="${ROOT:-}"

F_MAX="$ROOT/usr/sbin/max"
F_CONF="$ROOT/etc/webui/max.conf"
F_CGI="$ROOT/var/www/cgi-bin/ext-max.cgi"
F_YAML="$ROOT/etc/majestic.yaml"
F_HEADER="$ROOT/var/www/cgi-bin/p/header.cgi"
F_MOTION="$ROOT/usr/sbin/motion.sh"
F_CRON="$ROOT/etc/crontabs/root"

MARK_BEGIN="# >>> MAX-for-OpenIPC"
MARK_END="# <<< MAX-for-OpenIPC"
MOTION_LINE="/usr/sbin/max >/dev/null 2>&1 &"

TMPD="/tmp/.max-install.$$"
YAML_CHANGED=0
ROLLED_BACK=0

ok()   { printf '[ ok ] %s\n' "$*"; }
skip() { printf '[skip] %s\n' "$*"; }
warn() { printf '[warn] %s\n' "$*"; }
die()  { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

usage() {
        cat <<'EOF'
MAX-for-OpenIPC installer — sends motion video clips to the MAX messenger

One-command install on an OpenIPC camera (SSH, as root):
  curl -fsSL https://raw.githubusercontent.com/AT-Lee/MAX-for-OpenIPC/refs/heads/main/install.sh | sh -s --
  wget -qO-  https://raw.githubusercontent.com/AT-Lee/MAX-for-OpenIPC/refs/heads/main/install.sh | sh -s --

Options:
  --uninstall   remove MAX-for-OpenIPC from the camera
  --no-motion   do not create/patch the /usr/sbin/motion.sh hook
  --no-menu     do not patch the web UI menu (header.cgi)
  --no-restart  do not restart majestic (even if majestic.yaml was changed)
  --force       suppress environment warnings
  -h, --help    show this help

Environment (advanced):
  REPO=user/repo BRANCH=branch   install from another repository or branch
  SRC_DIR=/path                  install from a local directory (offline install)
  ROOT=/path                     install into a different root (testing)

Re-running the same install command updates an existing installation.
EOF
}

# ----------------------------------------------------------------------------
# argument parsing
# ----------------------------------------------------------------------------
OPT_UNINSTALL=0; OPT_NO_MOTION=0; OPT_NO_MENU=0; OPT_NO_RESTART=0; OPT_FORCE=0
while [ $# -gt 0 ]; do
        case "$1" in
                --uninstall)  OPT_UNINSTALL=1 ;;
                --no-motion)  OPT_NO_MOTION=1 ;;
                --no-menu)    OPT_NO_MENU=1 ;;
                --no-restart) OPT_NO_RESTART=1 ;;
                --force)      OPT_FORCE=1 ;;
                -h|--help)    usage; exit 0 ;;
                --) ;;
                *) usage; printf '\nUnknown option: %s\n' "$1" >&2; exit 1 ;;
        esac
        shift
done

# ----------------------------------------------------------------------------
# pre-flight
# ----------------------------------------------------------------------------
[ "$(id -u)" = "0" ] || [ -n "$ROOT" ] || die "please run as root (SSH to the camera: ssh root@<camera-ip>)"

trap 'rm -rf "$TMPD"' EXIT
trap 'rm -rf "$TMPD"; exit 130' INT
trap 'rm -rf "$TMPD"; exit 143' TERM
mkdir -p "$TMPD"

printf 'MAX-for-OpenIPC installer\n'
printf 'source: https://github.com/%s (branch: %s)\n\n' "$REPO" "$BRANCH"

# soft environment check (warn only)
if [ "$OPT_FORCE" != "1" ] && [ ! -f "$ROOT/etc/majestic.yaml" ] && ! grep -qi openipc "$ROOT/etc/os-release" 2>/dev/null; then
        warn "this does not look like an OpenIPC camera (/etc/os-release and /etc/majestic.yaml not found)"
        warn "continuing anyway — use --force to silence this warning"
fi

if [ -z "$ROOT" ]; then
        y=$(date -u +%Y 2>/dev/null)
        case "$y" in
                20[2-9][0-9]) ;;
                *) warn "system clock looks wrong (year: ${y:-unknown}) — TLS downloads will fail until the clock is set (NTP)" ;;
        esac
        free_kb=$(df -k / 2>/dev/null | awk 'NR==2{print $4}')
        case "$free_kb" in
                ''|*[!0-9]*) ;;
                *) [ "$free_kb" -lt 200 ] && warn "less than 200 KB free on the root filesystem — installation may fail" ;;
        esac
fi

FETCH=""
if [ -n "$SRC_DIR" ]; then
        FETCH="local"
elif command -v curl >/dev/null 2>&1; then
        FETCH="curl"
elif command -v wget >/dev/null 2>&1; then
        FETCH="wget"
else
        die "neither curl nor wget found — cannot download files"
fi

# ----------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------
fetch_one() { # $1 = repo file name, $2 = destination
        if [ "$FETCH" = "local" ]; then
                [ -f "$SRC_DIR/$1" ] || die "SRC_DIR: file not found: $SRC_DIR/$1"
                cp "$SRC_DIR/$1" "$2" || die "cannot copy $SRC_DIR/$1"
                return 0
        fi
        if [ "$FETCH" = "curl" ]; then
                curl -fsSL --retry 2 --retry-delay 1 --connect-timeout 15 --max-time 60 \
                        "https://raw.githubusercontent.com/${REPO}/${BRANCH}/$1" -o "$2"
        else
                wget -q -T 15 -O "$2" "https://raw.githubusercontent.com/${REPO}/${BRANCH}/$1"
        fi
        [ -s "$2" ] || die "download failed: $1 (check the network/DNS on the camera)"
}

get_sources() {
        mkdir -p "$ROOT/usr/sbin" "$ROOT/etc/webui" "$ROOT/var/www/cgi-bin"
        if [ "$FETCH" = "local" ]; then
                ok "using local files from $SRC_DIR"
        else
                ok "downloading files from GitHub..."
        fi
        fetch_one max         "$TMPD/max"         || exit 1
        fetch_one max.conf    "$TMPD/max.conf"    || exit 1
        fetch_one ext-max.cgi "$TMPD/ext-max.cgi" || exit 1

        grep -q '^#!' "$TMPD/max"                || die "downloaded 'max' is not a script — aborting"
        grep -q '^max_enabled=' "$TMPD/max.conf" || die "downloaded 'max.conf' is not a MAX config — aborting"
        grep -q '^#!' "$TMPD/ext-max.cgi"        || die "downloaded 'ext-max.cgi' is not a script — aborting"
        ok "downloaded 3 files, checksums look sane"
}

install_file() { # $1 = source, $2 = destination, $3 = mode, $4 = updated message
        if [ ! -f "$2" ]; then
                cp "$1" "$2" && chmod "$3" "$2" && ok "$4"
                return 0
        fi
        if cmp -s "$1" "$2"; then
                chmod "$3" "$2" 2>/dev/null
                skip "$2 is already up to date"
                return 0
        fi
        [ -f "$2.bak" ] || cp "$2" "$2.bak"
        cp "$1" "$2" && chmod "$3" "$2" && ok "$4"
}

# ----------------------------------------------------------------------------
# majestic.yaml: enable hls + motionDetect
# ----------------------------------------------------------------------------
patch_yaml() {
        [ -f "$F_YAML" ] || { skip "$F_YAML not found — enable hls & motionDetect manually"; return 0; }
        awk '
                BEGIN { h = 0; m = 0; hd = 0; md = 0; hp = 0; mp = 0 }
                /^[A-Za-z][A-Za-z0-9_-]*:/ {
                        if (h && !hd) { print "  enabled: true"; hd = 1 }
                        if (m && !md) { print "  enabled: true"; md = 1 }
                        h = ($0 ~ /^hls:/)
                        m = ($0 ~ /^motionDetect:/)
                        if (h) hp = 1
                        if (m) mp = 1
                        print
                        next
                }
                (h || m) && /^[ \t]+enabled:/ {
                        match($0, /^[ \t]*/)
                        print substr($0, 1, RLENGTH) "enabled: true"
                        if (h) hd = 1
                        if (m) md = 1
                        next
                }
                { print }
                END {
                        if (h && !hd) { print "  enabled: true"; hd = 1 }
                        if (m && !md) { print "  enabled: true"; md = 1 }
                        if (!hp) { print ""; print "hls:"; print "  enabled: true" }
                        if (!mp) { print ""; print "motionDetect:"; print "  enabled: true" }
                }
        ' "$F_YAML" > "$TMPD/majestic.yaml.new" || { warn "cannot patch $F_YAML (awk failed)"; return 0; }
        [ -s "$TMPD/majestic.yaml.new" ] || { warn "cannot patch $F_YAML (empty result)"; return 0; }
        if cmp -s "$F_YAML" "$TMPD/majestic.yaml.new"; then
                skip "hls & motionDetect are already enabled in majestic.yaml"
                return 0
        fi
        [ -f "$F_YAML.bak" ] || cp "$F_YAML" "$F_YAML.bak"
        cat "$TMPD/majestic.yaml.new" > "$F_YAML" || { warn "cannot write $F_YAML"; return 0; }
        YAML_CHANGED=1
        ok "enabled hls & motionDetect in /etc/majestic.yaml (backup: majestic.yaml.bak)"
}

# ----------------------------------------------------------------------------
# /usr/sbin/motion.sh: run max on motion events
# ----------------------------------------------------------------------------
patch_motion() {
        if [ "$OPT_NO_MOTION" = "1" ]; then
                skip "--no-motion: /usr/sbin/motion.sh untouched"
                return 0
        fi
        if [ ! -f "$F_MOTION" ]; then
                {
                        printf '#!/bin/sh\n'
                        printf '# /usr/sbin/motion.sh — motion event hook\n'
                        printf '# Created by MAX-for-OpenIPC install.sh\n'
                        printf '# Majestic runs this on every motionDetect event (see majestic.yaml).\n'
                        printf '%s\n' "$MOTION_LINE"
                } > "$F_MOTION" || { warn "cannot create $F_MOTION"; return 0; }
                chmod 755 "$F_MOTION"
                ok "created /usr/sbin/motion.sh (runs max on every motion event)"
                return 0
        fi
        if grep -q "/usr/sbin/max" "$F_MOTION"; then
                skip "motion.sh already runs max"
                return 0
        fi
        [ -f "$F_MOTION.bak" ] || cp "$F_MOTION" "$F_MOTION.bak"
        awk '
                !ins && index($0, "touch \"$STOP_FILE\"") == 1 {
                        print
                        print b
                        print "/usr/sbin/max >/dev/null 2>&1 &"
                        print e
                        ins = 1
                        next
                }
                { print }
                END { exit !ins }
        ' b="$MARK_BEGIN" e="$MARK_END" "$F_MOTION" > "$TMPD/motion.new" && [ -s "$TMPD/motion.new" ] && {
                cat "$TMPD/motion.new" > "$F_MOTION"
                ok "added the max hook to the existing motion.sh (backup: motion.sh.bak)"
                return 0
        }
        {
                printf '\n%s\n' "$MARK_BEGIN"
                printf '%s\n' "$MOTION_LINE"
                printf '%s\n' "$MARK_END"
        } >> "$F_MOTION"
        ok "appended the max hook to the existing motion.sh (backup: motion.sh.bak)"
}

# ----------------------------------------------------------------------------
# web UI menu (header.cgi): add the MAX item
# ----------------------------------------------------------------------------
menu_insert_after() { # $1 = anchor substring, $2 = item line; result in $TMPD/header.new
        awk '
                !ins && index($0, needle) > 0 {
                        match($0, /^[ \t]*/)
                        indent = substr($0, 1, RLENGTH)
                        print
                        print indent item
                        ins = 1
                        next
                }
                { print }
                END { exit !ins }
        ' needle="$1" item="$2" "$F_HEADER" > "$TMPD/header.new"
}

patch_menu() {
        if [ "$OPT_NO_MENU" = "1" ]; then
                skip "--no-menu: header.cgi untouched"
                return 0
        fi
        if [ ! -f "$F_HEADER" ]; then
                skip "web UI header.cgi not found — the MAX page is reachable directly"
                return 0
        fi
        if grep -q "ext-max.cgi" "$F_HEADER"; then
                skip "MAX menu item already present in header.cgi"
                return 0
        fi
        ITEM='<li><a class="dropdown-item" href="ext-max.cgi">MAX</a></li>'
        if menu_insert_after 'href="ntfy.cgi"' "$ITEM" && [ -s "$TMPD/header.new" ]; then
                cat "$TMPD/header.new" > "$F_HEADER"
                ok "added MAX to the web UI menu (Services -> Notifications)"
                return 0
        fi
        if menu_insert_after 'aria-labelledby="dropdownExtensions"' "$ITEM" && [ -s "$TMPD/header.new" ]; then
                cat "$TMPD/header.new" > "$F_HEADER"
                ok "added MAX to the web UI menu (Extensions)"
                return 0
        fi
        if menu_insert_after 'load_plugins' "$ITEM" && [ -s "$TMPD/header.new" ]; then
                cat "$TMPD/header.new" > "$F_HEADER"
                ok "added MAX to the web UI menu (Services)"
                return 0
        fi
        rm -f "$TMPD/header.new"
        warn "could not find a menu anchor in header.cgi — the MAX page is reachable directly"
        [ -f "$ROOT/var/www/cgi-bin/p/common.cgi" ] || \
                warn "web UI helpers (p/common.cgi) not found — the MAX page may not render on this build"
}

# ----------------------------------------------------------------------------
# restart majestic, roll back majestic.yaml if it does not come back
# ----------------------------------------------------------------------------
wait_majestic() {
        i=0
        while [ "$i" -lt "$1" ]; do
                sleep 1
                pidof majestic >/dev/null 2>&1 && return 0
                i=$((i + 1))
        done
        return 1
}

restart_majestic() {
        if [ "$OPT_NO_RESTART" = "1" ]; then
                skip "--no-restart: restart majestic yourself (/etc/init.d/S95majestic restart)"
                return 0
        fi
        if [ "$YAML_CHANGED" != "1" ]; then
                skip "majestic.yaml was not changed — no restart needed"
                return 0
        fi
        if ! pidof majestic >/dev/null 2>&1; then
                warn "majestic is not running — restart skipped; start it manually"
                return 0
        fi
        INIT=""
        for s in "$ROOT"/etc/init.d/S*majestic*; do
                [ -x "$s" ] && { INIT="$s"; break; }
        done
        do_restart() {
                if [ -n "$INIT" ]; then
                        "$INIT" restart >/dev/null 2>&1
                else
                        killall -HUP majestic 2>/dev/null
                fi
        }
        msg="restarting majestic..."
        [ -z "$INIT" ] && msg="reloading majestic (SIGHUP)..."
        printf '[ .. ] %s\n' "$msg"
        do_restart
        if wait_majestic 15; then
                ok "majestic is up"
                return 0
        fi
        warn "majestic did not come back within 15s — rolling back majestic.yaml"
        if [ -f "$F_YAML.bak" ]; then
                cat "$F_YAML.bak" > "$F_YAML"
                do_restart
                if wait_majestic 15; then
                        ok "majestic is up with the previous configuration"
                        warn "majestic.yaml was restored from .bak — enable hls/motionDetect manually"
                        ROLLED_BACK=1
                else
                        die "majestic is still down — check 'logread | tail' and restore $F_YAML.bak manually"
                fi
        else
                die "majestic is down and there is no majestic.yaml.bak to roll back to"
        fi
}

# ----------------------------------------------------------------------------
# final summary
# ----------------------------------------------------------------------------
camera_ip() {
        ip -4 addr show scope global 2>/dev/null | awk '/inet /{split($2, a, "/"); print a[1]; exit}' 2>/dev/null
}

summary() {
        printf '\n----------------------------------------------------------------\n'
        printf ' MAX-for-OpenIPC is installed.\n'
        if [ "$ROLLED_BACK" = "1" ]; then
                printf ' NOTE: the majestic.yaml changes were rolled back during restart —\n'
                printf '       enable hls & motionDetect in /etc/majestic.yaml manually.\n'
        fi
        printf '%s\n' '----------------------------------------------------------------'
        printf ' Files:\n'
        printf '   /usr/sbin/max                  capture & upload script\n'
        printf '   /etc/webui/max.conf            configuration\n'
        printf '   /var/www/cgi-bin/ext-max.cgi   web UI page\n'
        IP=$(camera_ip)
        URL="http://<camera-ip>/cgi-bin/ext-max.cgi"
        [ -n "$IP" ] && URL="http://${IP}/cgi-bin/ext-max.cgi"
        printf '\n Configure the bot:\n'
        printf '   1. In the MAX app open @BotFather, create a bot, copy its token.\n'
        printf '   2. Send any message to your bot, then get the chat id:\n'
        printf '        curl -s -H "Authorization: <TOKEN>" https://platform-api.max.ru/updates\n'
        printf '      and find "chat_id" in the response (negative for groups).\n'
        printf '   3. Open %s\n' "$URL"
        printf '      (web UI menu: Services/Notifications -> MAX),\n'
        printf '      paste Token and Chat ID, press Save, then "Send test video".\n'
        if [ "$OPT_NO_MOTION" = "1" ]; then
                printf '\n Motion mode: not configured by this run (--no-motion).\n'
                printf '              Add /usr/sbin/max to /usr/sbin/motion.sh yourself.\n'
        else
                printf '\n Motion mode: automatic — motionDetect is enabled and motion.sh runs max.\n'
        fi
        printf ' Cron mode:   enable "Add to crontab" on the MAX page in the web UI.\n'
        printf '%s\n' '----------------------------------------------------------------'
}

# ----------------------------------------------------------------------------
# uninstall
# ----------------------------------------------------------------------------
uninstall() {
        printf 'Removing MAX-for-OpenIPC...\n'
        if [ -f "$ROOT/tmp/max.lock" ]; then
                p=$(cat "$ROOT/tmp/max.lock" 2>/dev/null)
                [ -n "$p" ] && kill "$p" 2>/dev/null && ok "stopped a running max (pid $p)"
                rm -f "$ROOT/tmp/max.lock"
        fi
        for f in "$F_MAX" "$F_CGI" "$F_CONF"; do
                if [ -f "$f" ]; then
                        rm -f "$f" "$f.bak"
                        ok "removed $f"
                else
                        skip "$f was not installed"
                fi
        done
        if [ -f "$F_MOTION" ]; then
                if grep -q "Created by MAX-for-OpenIPC install.sh" "$F_MOTION" && [ ! -f "$F_MOTION.bak" ]; then
                        rm -f "$F_MOTION"
                        ok "removed $F_MOTION (it was created by the installer)"
                elif grep -q "$MARK_BEGIN" "$F_MOTION"; then
                        sed "/$MARK_BEGIN/,/$MARK_END/d" "$F_MOTION" > "$TMPD/motion.del" && [ -s "$TMPD/motion.del" ] && {
                                cat "$TMPD/motion.del" > "$F_MOTION"
                                ok "removed the max hook from $F_MOTION"
                        }
                else
                        skip "$F_MOTION has no MAX hook"
                fi
        fi
        if [ -f "$F_HEADER" ] && grep -q "ext-max.cgi" "$F_HEADER"; then
                grep -v "ext-max.cgi" "$F_HEADER" > "$TMPD/header.del" && [ -s "$TMPD/header.del" ] && {
                        cat "$TMPD/header.del" > "$F_HEADER"
                        ok "removed the MAX item from the web UI menu"
                }
        fi
        if [ -f "$F_CRON" ] && grep -q "/usr/sbin/max" "$F_CRON"; then
                grep -v "/usr/sbin/max" "$F_CRON" > "$TMPD/cron.del" && {
                        cat "$TMPD/cron.del" > "$F_CRON"
                        ok "removed the max line from crontab (applies within a minute)"
                }
        fi
        rm -f "$ROOT"/tmp/max.lock "$ROOT"/tmp/max.extend "$ROOT"/tmp/max.queue \
                "$ROOT"/tmp/max.queue.wip "$ROOT"/tmp/max.worker_exit "$ROOT"/tmp/m-*.mp4 2>/dev/null
        printf '\nDone. hls and motionDetect were left enabled in %s — disable them there\n' "$F_YAML"
        printf 'if they are not needed. Re-run this installer to install MAX again.\n'
}

# ----------------------------------------------------------------------------
# main
# ----------------------------------------------------------------------------
[ "$OPT_UNINSTALL" = "1" ] && { uninstall; exit 0; }

get_sources || exit 1

install_file "$TMPD/max" "$F_MAX" 755 "installed /usr/sbin/max"
install_file "$TMPD/ext-max.cgi" "$F_CGI" 755 "installed /var/www/cgi-bin/ext-max.cgi"
install_file "$TMPD/max.conf" "$F_CONF" 644 "installed /etc/webui/max.conf (default config)"
[ -f "$F_CONF.bak" ] && ! cmp -s "$F_CONF.bak" "$F_CONF" && \
        warn "your previous /etc/webui/max.conf is saved as max.conf.bak — restore it to keep the bot token/chat id"

patch_yaml
patch_motion
patch_menu
restart_majestic
summary
exit 0
