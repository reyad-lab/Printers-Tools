#!/bin/bash
# ===============================================================
#  developed  : Mahmoud Rabia Kassem — Specialist IT Admin
#  Version : 1.0 — Final Stable For MF
# ===============================================================

# ────────────────────────────────────────────────────────────────
#  SECTION 1 — Version & Repository Configuration
# ────────────────────────────────────────────────────────────────
CURRENT_VERSION="1.0"
GH_USER="mahmoudkassem30"
REPO="Printers-Tools"
BRANCH="main"

VERSION_URL="https://raw.githubusercontent.com/$GH_USER/$REPO/$BRANCH/MF/version-MF.txt"
SCRIPT_URL="https://raw.githubusercontent.com/$GH_USER/$REPO/$BRANCH/MF/printers-MF.sh"

# ────────────────────────────────────────────────────────────────
#  SECTION 1b — Integrity Verification
# ────────────────────────────────────────────────────────────────
MANIFEST_URL="https://raw.githubusercontent.com/mahmoudkassem30/Printers-Tools/main/sources/pic/manifest.sha256"

verify_sha256_or_abort() {
    local FILE_PATH="$1"
    local KEY="$2"

    if [ ! -f "$FILE_PATH" ]; then
        echo "[integrity] File not found: $FILE_PATH" >&2
        return 1
    fi

    local MANIFEST_TMP
    MANIFEST_TMP=$(mktemp /tmp/ita_manifest.XXXXXX) || return 1

    if ! curl -fsSL --connect-timeout 10 --max-time 20 "$MANIFEST_URL" -o "$MANIFEST_TMP" 2>/dev/null; then
        echo "[integrity] Could not download integrity manifest. Aborting for safety." >&2
        rm -f "$MANIFEST_TMP"
        return 1
    fi

    local EXPECTED_HASH
    EXPECTED_HASH=$(grep -m1 "^${KEY}=" "$MANIFEST_TMP" | cut -d= -f2- | tr -d '[:space:]')
    rm -f "$MANIFEST_TMP"

    if [ -z "$EXPECTED_HASH" ]; then
        echo "[integrity] No manifest entry found for key: $KEY" >&2
        return 1
    fi

    local ACTUAL_HASH
    ACTUAL_HASH=$(sha256sum "$FILE_PATH" | awk '{print $1}')

    if [ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]; then
        echo "[integrity] Verification FAILED for $FILE_PATH" >&2
        echo "[integrity] Expected: $EXPECTED_HASH" >&2
        echo "[integrity] Actual:   $ACTUAL_HASH" >&2
        return 1
    fi

    return 0
}
# ────────────────────────────────────────────────────────────────
#  SECTION 2 — Auto-Update Function
#  Checks GitHub for a newer version and offers to update in-place
# ────────────────────────────────────────────────────────────────
check_for_updates() {

    if ! curl -sf --connect-timeout 5 https://github.com -o /dev/null; then
        return
    fi

    REMOTE_VERSION=$(curl -fsSL --connect-timeout 5 "$VERSION_URL" | tr -d '\r\n ')

    [ -z "$REMOTE_VERSION" ] && return

    if [ "$CURRENT_VERSION" != "$REMOTE_VERSION" ] && \
       [ "$(printf '%s\n%s\n' "$CURRENT_VERSION" "$REMOTE_VERSION" | sort -V | tail -n1)" = "$REMOTE_VERSION" ]; then

        refresh_sys_icon

        read _W _H < <(get_win_size medium)

        zenity --question \
            --title="يوجد تحديث جديد برجاء التحديث" \
            --text="يوجد إصدار جديد ($REMOTE_VERSION).\nهل تريد التحديث الآن؟" \
            --width=$_W \
            --window-icon="$SYS_ICON" 2>/dev/null

        if [ $? -eq 0 ]; then

            TMP_SCRIPT="/tmp/printers_new.sh"

            if curl -fsSL "$SCRIPT_URL" -o "$TMP_SCRIPT"; then

                if ! verify_sha256_or_abort "$TMP_SCRIPT" "PRINTERS_MF"; then

                    rm -f "$TMP_SCRIPT"

                    zenity --error \
                        --title="فشل التحقق من سلامة التحديث" \
                        --text="لم يتم التحقق من سلامة الملف المحمّل، تم إلغاء التحديث لحمايتك.\nيرجى المحاولة لاحقاً." \
                        2>/dev/null

                else

                chmod +x "$TMP_SCRIPT"

                install -m 755 "$TMP_SCRIPT" /usr/local/bin/it-aman

                rm -f "$TMP_SCRIPT"

                zenity --info \
                    --title="تم التحديث بنجاح" \
                    --text="تم التحديث إلى الإصدار $REMOTE_VERSION بنجاح.\nيرجى إعادة تشغيل الأداة." \
                    2>/dev/null

                exit 0

                fi

            else

                zenity --error \
                    --title="فشل التحديث " \
                    --text="لم يتم تحميل الملف برجاء المحاوله لاحقا." \
                    2>/dev/null
            fi
        fi
    fi
}
# ────────────────────────────────────────────────────────────────
#  SECTION 3 — Error Handler
#  Logs errors to Desktop and opens the log file automatically
# ────────────────────────────────────────────────────────────────
handle_error() {
    local error_point="$1"
    local REAL_USER=${SUDO_USER:-$USER}
    local USER_DESKTOP="/home/$REAL_USER/Desktop"
    local LOG_FILE="$USER_DESKTOP/it_aman_error.log"

    echo "--- Error Report ---"    >> "$LOG_FILE"
    echo "Date: $(date)"           >> "$LOG_FILE"
    echo "Failed at: $error_point" >> "$LOG_FILE"
    echo "--------------------"    >> "$LOG_FILE"

    chown "$REAL_USER:$REAL_USER" "$LOG_FILE"
    zenity --error --title "Error" \
        --text "An error occurred at: $error_point\nOpening error log now." \
        --width=300 2>/dev/null
    sudo -u "$REAL_USER" xdg-open "$LOG_FILE" &>/dev/null
}

# ────────────────────────────────────────────────────────────────
#  SECTION 4 — Root Privilege Check
# ────────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    zenity --error --title "Error" \
        --text "Administrator rights required. Please use sudo." 2>/dev/null
    exit 1
fi

REAL_USER=${SUDO_USER:-$USER}

# ────────────────────────────────────────────────────────────────
#  SECTION 5 — CUPS Environment & Sudoers Setup
# ────────────────────────────────────────────────────────────────
CUPS_ADMIN_USER="admin"
export CUPS_SERVER=localhost
export IPP_PORT=631

CUPS_SUDOERS_FILE="/etc/sudoers.d/it-aman-cups"
if [ ! -f "$CUPS_SUDOERS_FILE" ]; then
    cat > "$CUPS_SUDOERS_FILE" <<'EOF'
admin ALL=(ALL) NOPASSWD: /usr/sbin/lpadmin, /usr/sbin/cupsenable, /usr/sbin/cupsaccept, /usr/sbin/cancel
EOF
    chmod 0440 "$CUPS_SUDOERS_FILE"
fi

# ────────────────────────────────────────────────────────────────
#  SECTION 6 — Tool Identity & Icon Configuration
# ────────────────────────────────────────────────────────────────
TOOL_NAME="IT Aman - Printer Tool For MF V1.0"
SYS_ICON_NAME="it-aman-printer"
SYS_ICON_PATH=""
SYS_ICON_URL="https://raw.githubusercontent.com/mahmoudkassem30/Printers-Tools/main/sources/Icons/icon-printer.png"
SYS_ICON_FILE="/usr/local/share/it-aman/icons/icon-printer.png"
SYS_ICON_THEME_FILE="/usr/share/icons/hicolor/128x128/apps/${SYS_ICON_NAME}.png"
DESKTOP_FILE="/usr/share/applications/it-aman-printer.desktop"
SCRIPT_ABS_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"

# Fallback system printer icon if custom icon not yet downloaded
for _ICON_CAND in \
    /usr/share/icons/hicolor/48x48/devices/printer.png \
    /usr/share/icons/Adwaita/48x48/devices/printer.png \
    /usr/share/icons/Adwaita/64x64/devices/printer.png
do
    if [ -f "$_ICON_CAND" ]; then
        SYS_ICON_PATH="$_ICON_CAND"
        break
    fi
done
SYS_ICON="${SYS_ICON_NAME}"

# ────────────────────────────────────────────────────────────────
#  SECTION 7 — Icon Management Functions
#  refresh_sys_icon   : syncs downloaded icon to GTK theme cache
#  ensure_desktop_entry : creates .desktop launcher file
# ────────────────────────────────────────────────────────────────
refresh_sys_icon() {
    if [ -s "$SYS_ICON_FILE" ]; then
        mkdir -p "$(dirname "$SYS_ICON_THEME_FILE")" >/dev/null 2>&1
        if [ ! -s "$SYS_ICON_THEME_FILE" ] || ! cmp -s "$SYS_ICON_FILE" "$SYS_ICON_THEME_FILE"; then
            cp -f "$SYS_ICON_FILE" "$SYS_ICON_THEME_FILE" >/dev/null 2>&1
            mkdir -p /usr/share/icons/hicolor/64x64/apps >/dev/null 2>&1
            cp -f "$SYS_ICON_FILE" /usr/share/icons/hicolor/64x64/apps/${SYS_ICON_NAME}.png >/dev/null 2>&1
            command -v gtk-update-icon-cache >/dev/null 2>&1 && \
                gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1
        fi
        SYS_ICON="$SYS_ICON_NAME"
    else
        SYS_ICON="${SYS_ICON_PATH:-printer}"
    fi
}

ensure_desktop_entry() {
    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=IT Aman Printer Tool
Exec=${SCRIPT_ABS_PATH}
Icon=${SYS_ICON_FILE}
Terminal=false
Categories=Utility;System;
StartupWMClass=zenity
EOF
    command -v update-desktop-database >/dev/null 2>&1 && \
        update-desktop-database /usr/share/applications >/dev/null 2>&1
}

# Download icon in background (non-blocking)
(
    if [ ! -s "$SYS_ICON_FILE" ]; then
        mkdir -p "$(dirname "$SYS_ICON_FILE")" >/dev/null 2>&1
        curl -fL --connect-timeout 8 --max-time 30 --retry 1 \
            -o "${SYS_ICON_FILE}.tmp" "$SYS_ICON_URL" >/dev/null 2>&1 \
            && mv -f "${SYS_ICON_FILE}.tmp" "$SYS_ICON_FILE"
    fi
) &

refresh_sys_icon
ensure_desktop_entry

# ────────────────────────────────────────────────────────────────
#  SECTION 8 — Dynamic Window Sizing
#  Returns width and height scaled to screen resolution
#  Usage : read W H < <(get_win_size medium)
#  Types : small | medium | large | wide | progress
# ────────────────────────────────────────────────────────────────
get_win_size() {
    local TYPE="${1:-medium}"
    local SCR_W SCR_H

    if command -v xrandr &>/dev/null; then
        read SCR_W SCR_H < <(xrandr 2>/dev/null \
            | grep -oE '[0-9]+x[0-9]+' | head -1 \
            | awk -Fx '{print $1, $2}')
    fi

    # Fallback if xrandr is unavailable
    [ -z "$SCR_W" ] && SCR_W=1920
    [ -z "$SCR_H" ] && SCR_H=1080

    local W H
    case "$TYPE" in
        small)
            W=$(( SCR_W * 28 / 100 )); H=$(( SCR_H * 28 / 100 ))
            [ "$W" -lt 320 ] && W=320;  [ "$W" -gt 480 ] && W=480
            [ "$H" -lt 180 ] && H=180;  [ "$H" -gt 300 ] && H=300
            ;;
        medium)
            W=$(( SCR_W * 35 / 100 )); H=$(( SCR_H * 38 / 100 ))
            [ "$W" -lt 420 ] && W=420;  [ "$W" -gt 600 ] && W=600
            [ "$H" -lt 260 ] && H=260;  [ "$H" -gt 420 ] && H=420
            ;;
        large)
            W=$(( SCR_W * 42 / 100 )); H=$(( SCR_H * 52 / 100 ))
            [ "$W" -lt 520 ] && W=520;  [ "$W" -gt 680 ] && W=680
            [ "$H" -lt 360 ] && H=360;  [ "$H" -gt 620 ] && H=620
            ;;
        wide)
            W=$(( SCR_W * 45 / 100 )); H=$(( SCR_H * 38 / 100 ))
            [ "$W" -lt 540 ] && W=540;  [ "$W" -gt 720 ] && W=720
            [ "$H" -lt 260 ] && H=260;  [ "$H" -gt 420 ] && H=420
            ;;
        progress)
            W=$(( SCR_W * 32 / 100 )); H=$(( SCR_H * 18 / 100 ))
            [ "$W" -lt 380 ] && W=380;  [ "$W" -gt 560 ] && W=560
            [ "$H" -lt 130 ] && H=130;  [ "$H" -gt 200 ] && H=200
            ;;
    esac
    echo "$W $H"
}

# ────────────────────────────────────────────────────────────────
#  SECTION 9 — Thermal Paper Size Helper Functions
#  Detect and resolve 80mm/72mm paper size tokens from CUPS options
# ────────────────────────────────────────────────────────────────
pick_thermal_size_value() {
    local OPT_LINE="$1"
    local TOKENS
    TOKENS=$(echo "$OPT_LINE" | tr ' ' '\n' | sed 's/^\*//' | cut -d'/' -f1)
    echo "$TOKENS" | grep -Ei '^Custom\.80x297mm$|^80[^0-9]*x[^0-9]*297(mm)?$|^w80h297$' | head -1 && return
    echo "$TOKENS" | grep -Ei '^Custom\.72x297mm$|^72[^0-9]*x[^0-9]*297(mm)?$|^w72h297$' | head -1 && return
    echo "$TOKENS" | grep -Ei '80[^0-9]*x[^0-9]*297|297[^0-9]*x[^0-9]*80|72[^0-9]*x[^0-9]*297|297[^0-9]*x[^0-9]*72' | head -1
}

extract_cups_tokens() {
    local OPT_LINE="$1"
    echo "$OPT_LINE" \
        | sed 's/^[^:]*://g' \
        | tr ' ' '\n' \
        | sed 's/^\*//' \
        | cut -d'/' -f1 \
        | sed '/^$/d'
}

resolve_thermal_size_from_tokens() {
    local TOKENS="$1"
    local TOKENS_NO_CUSTOM
    local V
    TOKENS_NO_CUSTOM=$(echo "$TOKENS" | grep -E -i -v 'custom')
    for V in 80x297mm 80x297 80mmx297mm 80mmx297 w80h297 72x297mm 72x297 72mmx297mm 72mmx297 w72h297; do
        echo "$TOKENS_NO_CUSTOM" | grep -E -i "^${V}$" | head -1 && return
    done
    echo "$TOKENS_NO_CUSTOM" | grep -E -i '80[^0-9]*x[^0-9]*297|297[^0-9]*x[^0-9]*80' | head -1 && return
    echo "$TOKENS_NO_CUSTOM" | grep -E -i '72[^0-9]*x[^0-9]*297|297[^0-9]*x[^0-9]*72' | head -1
}

resolve_forced_custom_size_from_tokens() {
    local TOKENS="$1"
    local TOKENS_CUSTOM
    TOKENS_CUSTOM=$(echo "$TOKENS" | grep -E -i 'custom')
    echo "$TOKENS_CUSTOM" | grep -E -i '^Custom\.72x297(mm)?$|^Custom72x297(mm)?$'           | head -1 && return
    echo "$TOKENS_CUSTOM" | grep -E -i '^Custom\.72\.0x297\.0(mm)?$|^Custom72\.0x297\.0(mm)?$' | head -1 && return
    echo "$TOKENS_CUSTOM" | grep -E -i '72[^0-9]*x[^0-9]*297|297[^0-9]*x[^0-9]*72'            | head -1 && return
    echo "Custom.72x297mm"
}

# ────────────────────────────────────────────────────────────────
#  SECTION 10 — Thermal Printer Defaults Setter
#  Applies FullCut as the default cut mode for thermal printers
# ────────────────────────────────────────────────────────────────
set_thermal_defaults() {
    local PRN="$1"
    local OPTS CUT_LINE CUT_VAL

    OPTS=$(sudo -u admin /usr/bin/lpoptions -p "$PRN" -l 2>/dev/null)
    [ -z "$OPTS" ] && return

    CUT_LINE=$(echo "$OPTS" | grep -i '^CutType[/:]' | head -1)
    CUT_VAL=$(echo "$CUT_LINE" \
        | tr ' ' '\n' \
        | sed 's/^\*//' \
        | cut -d'/' -f1 \
        | grep -Ei '^FullCut$|^Full$|^Cut$' \
        | head -1)

    if [ -n "$CUT_VAL" ]; then
        sudo -u admin /usr/bin/lpoptions -p "$PRN" -o "CutType=$CUT_VAL" 2>/dev/null
        sudo -u admin /usr/sbin/lpadmin  -p "$PRN" -o "CutType=$CUT_VAL" 2>/dev/null
    fi
}

# ────────────────────────────────────────────────────────────────
#  SECTION 11 — Startup Sequence
#  Run update check → show welcome splash → define UI strings
# ────────────────────────────────────────────────────────────────
check_for_updates
# ── Welcome screen ───────────────────────────────────────────
show_welcome() {
    zenity --info \
        --title="IT-Aman — Printers-Tools For MF V1.0 " \
        --text="\n<b><big>   IT-Aman — Printers-Tools For MF V1.0   </big></b>\n\n\
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\
  <b>Made By:</b>  IT Aman Helpdesk Support Team\n\
  <b>Department:</b>      Information Technology\n\
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n\
<b>This tool makes work easier</b>\n\n\
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n\
<i>Version 1.0 </i>\n\n\
<i>© All Rights Reserved 2026 - IT-Aman</i>\n" \
        --width=500 \
        --height=380 \
        --ok-label="Continue ▶" \
        2>/dev/null
    [[ $? -ne 0 ]] && { echo -e "${YELLOW}[INFO]${RESET} Cancelled by user."; exit 0; }
}
show_welcome
# ────────────────────────────────────────────────────────────────
#  SECTION 12 — UI String Definitions (Arabic)
# ────────────────────────────────────────────────────────────────
TXT_MENU="قائمة الخدمات المتاحة:"
TXT_O1=" معالجة حشر الورق (ارشادات)"
TXT_O2=" فحص النظام الذكي (كشف وحل تلقائي)"
TXT_O3=" إدارة الطابعات (إضافة / حذف)"
TXT_O4=" إدارة الطابعة الحرارية (إضافة / حذف)"
TXT_O5=" إصلاح أوامر الطباعة (تنظيف الذاكرة العامة)"
TXT_O6=" خروج"
TXT_WAIT="جاري المعالجة، يرجى الانتظار..."
TXT_SUCCESS="تمت العملية بنجاح ✅"
JAM_TITLE="خطوات إزالة الورق العالق"
JAM_MSG="⚠️ يرجى اتباع التعليمات التالية بدقة:\n\n1. أطفئ الطابعة وافصل كابل الكهرباء فوراً.\n2. افتح الأبواب المخصصة للورق.\n3. اسحب الورق العالق 'بكلتا اليدين' ببطء شديد.\n4. لا تستخدم القوة المفرطة أو أدوات حادة.\n\n📷 بعد الضغط على OK سيتم عرض صورة توضيحية لطريقة الإزالة."
REP_HDR="[ تقرير فحص IT Aman ]"
REP_C_FX="- تم إعادة تشغيل خدمة الطباعة (CUPS)."
REP_J_FX="- تم تنظيف مهام الطباعة العالقة."
REP_E_FX="- تم اكتشاف طابعات معطلة وإعادة تنشيطها."

# ────────────────────────────────────────────────────────────────
#  SECTION 13 — Admin Mode State
#  ADMIN_MODE=0  → normal user  (options 3 & 4 hidden)
#  ADMIN_MODE=1  → unlocked for this session only
# ────────────────────────────────────────────────────────────────
ADMIN_MODE=0

# ────────────────────────────────────────────────────────────────
#  SECTION 14 — Admin Unlock Function
# ────────────────────────────────────────────────────────────────
try_admin_unlock() {
    read _W _H < <(get_win_size medium)

    # Welcome message
    zenity --info \
        --title "🔐 Administrator Access" \
        --window-icon="$SYS_ICON" \
        --text "🔐 Welcome, Administrator\n\nThis section grants access to advanced printer management.\nPlease authenticate to continue.\n\nEnter the root password registered on this machine." \
        --width=$_W 2>/dev/null

    # Ask for root password
    ENTERED_PASS=$(zenity --password \
        --title "🔐 Authentication Required" \
        --window-icon="$SYS_ICON" 2>/dev/null)

    # User cancelled
    [ -z "$ENTERED_PASS" ] && return

    # Verify password against root account via PAM (works even when already root)
    AUTH_OK=0
    if command -v python3 &>/dev/null && python3 -c "import pam" 2>/dev/null; then
        printf '%s' "$ENTERED_PASS" | python3 -c '
import sys, pam
pw = sys.stdin.read()
p = pam.pam()
sys.exit(0 if p.authenticate("root", pw) else 1)
' && AUTH_OK=1
    elif command -v pamtester &>/dev/null; then
        echo "$ENTERED_PASS" | pamtester login root authenticate 2>/dev/null && AUTH_OK=1
    else
      
        SHADOW_HASH=$(getent shadow root 2>/dev/null | cut -d: -f2)
        if [ -n "$SHADOW_HASH" ] && [ "$SHADOW_HASH" != "*" ] && [ "$SHADOW_HASH" != "!" ]; then
            COMPUTED=$(printf '%s\n%s\n' "$SHADOW_HASH" "$ENTERED_PASS" | python3 -c '
import crypt, sys
h = sys.stdin.readline().rstrip("\n")
pw = sys.stdin.readline().rstrip("\n")
print(crypt.crypt(pw, h))
' 2>/dev/null)
            [ "$COMPUTED" = "$SHADOW_HASH" ] && AUTH_OK=1
        fi
    fi
    if [ "$AUTH_OK" -eq 1 ]; then
        ADMIN_MODE=1
        read _W _H < <(get_win_size medium)
        zenity --info \
            --title "✅ Access Granted" \
            --window-icon="$SYS_ICON" \
            --text "✅ Authentication successful.\n\nAdvanced options are now unlocked for this session." \
            --width=$_W 2>/dev/null
    else
        read _W _H < <(get_win_size medium)
        zenity --error \
            --title "❌ Access Denied" \
            --window-icon="$SYS_ICON" \
            --text "❌ Incorrect password.\n\nAccess denied." \
            --width=$_W 2>/dev/null
    fi
    unset ENTERED_PASS AUTH_OK SHADOW_HASH COMPUTED
}

# ────────────────────────────────────────────────────────────────
#  SECTION 15 — Main Menu Loop
# ────────────────────────────────────────────────────────────────
while true; do
    refresh_sys_icon
    read _W _H < <(get_win_size large)

    # Build menu based on ADMIN_MODE
    # Normal mode  : 1,2,3(fix),4(exit)          — options 3&4 printer mgmt hidden
    # Admin mode   : 1,2,3(printers),4(thermal),5(fix),6(exit)
    if [ "$ADMIN_MODE" -eq 0 ]; then
        CHOICE=$(zenity --list \
            --title "$TOOL_NAME" \
            --window-icon="$SYS_ICON" \
            --text "$TXT_MENU" \
            --radiolist \
            --column "Select" --column "ID" --column "Option" \
            FALSE "1" "$TXT_O1" \
            FALSE "2" "$TXT_O2" \
            FALSE "3" "$TXT_O5" \
            FALSE "4" "🔒 For Admin" \
            FALSE "5" "$TXT_O6" \
            --width=$_W --height=$_H 2>/dev/null)

        # Map normal-mode IDs to internal handler IDs
        case "$CHOICE" in
            1) CHOICE="1" ;;
            2) CHOICE="2" ;;
            3) CHOICE="5" ;;
            4)
                SECRET=$(zenity --entry \
                    --title "🔒 Admin Access" \
                    --window-icon="$SYS_ICON" \
                    --text "Enter access code:" \
                    --width=300 2>/dev/null)
               ADMIN_KEY=$(printf '\x41\x4d\x4d\x41\x4e')
		if [ "$SECRET" = "$ADMIN_KEY" ]; then
   		 unset SECRET ADMIN_KEY
   		 try_admin_unlock
		elif [ -n "$SECRET" ]; then
  		  unset SECRET ADMIN_KEY
                elif [ -n "$SECRET" ]; then
                    read _W _H < <(get_win_size medium)
                    zenity --error \
                        --title "❌ Access Denied" \
                        --window-icon="$SYS_ICON" \
                        --text "❌ Invalid access code." \
                        --width=$_W 2>/dev/null
                fi
                continue
                ;;
            5) exit 0 ;;
            *) exit 0 ;;
        esac
    else
        CHOICE=$(zenity --list \
            --title "$TOOL_NAME" \
            --window-icon="$SYS_ICON" \
            --text "$TXT_MENU" \
            --radiolist \
            --column "Select" --column "ID" --column "Option" \
            FALSE "1" "$TXT_O1" \
            FALSE "2" "$TXT_O2" \
            FALSE "3" "$TXT_O3" \
            FALSE "4" "$TXT_O4" \
            FALSE "5" "$TXT_O5" \
            FALSE "6" "$TXT_O6" \
            --width=$_W --height=$_H 2>/dev/null)

        if [ -z "$CHOICE" ] || [ "$CHOICE" == "6" ]; then exit 0; fi
    fi

    [ -z "$CHOICE" ] && continue

    case "$CHOICE" in

        # ────────────────────────────────────────────────────────
        #  MENU 1 — Paper Jam Guide
        #  Shows step-by-step instructions then opens a guide image
        # ────────────────────────────────────────────────────────
        1)
            read _W _H < <(get_win_size medium)
            zenity --info \
                --title "$JAM_TITLE" \
                --window-icon="$SYS_ICON" \
                --text "$JAM_MSG" \
                --width=$_W 2>/dev/null

            # Download and display the paper jam removal guide image
            JAM_IMG_URL="https://raw.githubusercontent.com/mahmoudkassem30/Printers-Tools/dbd1722a4ffac9f42856d9d3f70faa2874d1fd93/sources/pic/paperjam.png"
            JAM_IMG_TMP="/tmp/ita_paperjam.png"
            curl -fL --connect-timeout 10 --max-time 30 \
                -o "$JAM_IMG_TMP" "$JAM_IMG_URL" 2>/dev/null

            if [ -s "$JAM_IMG_TMP" ]; then
                # Try image viewers in order of preference
                if command -v eog &>/dev/null; then
                    sudo -u "$REAL_USER" eog "$JAM_IMG_TMP" &>/dev/null &
                elif command -v display &>/dev/null; then
                    sudo -u "$REAL_USER" display "$JAM_IMG_TMP" &>/dev/null &
                else
                    sudo -u "$REAL_USER" xdg-open "$JAM_IMG_TMP" &>/dev/null &
                fi
            else
                # Fallback: open URL directly if download failed
                sudo -u "$REAL_USER" xdg-open "$JAM_IMG_URL" &>/dev/null &
            fi
            ;;

        # ────────────────────────────────────────────────────────
        #  MENU 2 — Smart Diagnostic & Auto-Fix
        #
        #  Step 1 : Start CUPS if not running (required before any lpstat call)
        #  Step 2 : Verify at least one printer is registered in CUPS
        #           → abort with a clear message if none found
        #  Step 3 : Ping each printer's IP on ports 9100 / 631
        #           → warn about unreachable printers before continuing
        #  Step 4 : Clear all stuck / pending print jobs
        #  Step 5 : Re-enable any printers that CUPS marked as disabled
        #  Step 6 : Show final diagnostic report to the user
        # ────────────────────────────────────────────────────────
        2)
            DIAG_LOG=$(mktemp)

            # Step 1: Ensure CUPS is running before querying printers
            if ! systemctl is-active --quiet cups; then
                systemctl restart cups 2>/dev/null
                sleep 2
                echo "$REP_C_FX" >> "$DIAG_LOG"
            fi

            # Step 2: Check if any printers are registered in CUPS
            ALL_PRINTERS_DIAG=$(lpstat -e 2>/dev/null)
            if [ -z "$ALL_PRINTERS_DIAG" ]; then
                read _W _H < <(get_win_size medium)
                zenity --warning \
                    --title "تشخيص النظام" \
                    --window-icon="$SYS_ICON" \
                    --text "⚠️ لم يتم العثور على أي طابعات مضافة في النظام.\n\nالنظام لا يستطيع رؤية أي طابعة حالياً.\n\nيرجى التأكد من:\n• إضافة الطابعة أولاً من قائمة (إدارة الطابعات)\n• تشغيل الطابعة والتحقق من الاتصال بالشبكة\n• تفعيل خدمة CUPS" \
                    --width=$_W 2>/dev/null
                rm -f "$DIAG_LOG"
                continue
            fi

            # Step 3: Check network reachability for each registered printer
            UNREACHABLE_LIST=""
            while read -r PNAME; do
                [ -z "$PNAME" ] && continue
                PURI=$(lpstat -v "$PNAME" 2>/dev/null | awk '{print $NF}')
                PRINTER_IP=$(echo "$PURI" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')
                if [ -n "$PRINTER_IP" ]; then
                    if ! timeout 2 bash -c "echo >/dev/tcp/$PRINTER_IP/9100" 2>/dev/null && \
                       ! timeout 2 bash -c "echo >/dev/tcp/$PRINTER_IP/631"  2>/dev/null; then
                        UNREACHABLE_LIST="${UNREACHABLE_LIST}\n• $PNAME  ($PRINTER_IP) — غير متاح على الشبكة"
                    fi
                fi
            done <<< "$ALL_PRINTERS_DIAG"

            if [ -n "$UNREACHABLE_LIST" ]; then
                read _W _H < <(get_win_size medium)
                zenity --warning \
                    --title "تشخيص النظام — تحذير شبكة" \
                    --window-icon="$SYS_ICON" \
                    --text "⚠️ الطابعات التالية غير متاحة على الشبكة حالياً:${UNREACHABLE_LIST}\n\nيرجى التحقق من:\n• تشغيل الطابعة\n• الاتصال بنفس الشبكة\n• إعدادات IP للطابعة" \
                    --width=$_W 2>/dev/null
            fi

            # Steps 4 & 5: Clear stuck jobs and re-enable disabled printers
            (
                echo "20"

                # Step 4: Clear all stuck print jobs
                if [ -n "$(lpstat -o 2>/dev/null)" ]; then
                    sudo -u admin /usr/sbin/cancel -a 2>/dev/null
                    echo "$REP_J_FX" >> "$DIAG_LOG"
                fi
                echo "60"

                # Step 5: Re-enable any disabled printers
                DISABLED_PRINTERS=$(lpstat -p 2>/dev/null | grep "disabled" | awk '{print $2}')
                if [ -n "$DISABLED_PRINTERS" ]; then
                    while read -r p; do
                        sudo -u admin /usr/sbin/cupsenable  "$p" 2>/dev/null
                        sudo -u admin /usr/sbin/cupsaccept "$p" 2>/dev/null
                    done <<< "$DISABLED_PRINTERS"
                    echo "$REP_E_FX" >> "$DIAG_LOG"
                fi
                echo "100"
            ) | zenity --progress \
                --title "$TOOL_NAME" \
                --window-icon="$SYS_ICON" \
                --text "$TXT_WAIT" \
                --auto-close 2>/dev/null

            # Step 6: Show final diagnostic report
            if [ ! -s "$DIAG_LOG" ]; then
                FINAL_MSG="النظام يعمل بشكل جيد، لم يتم العثور على أخطاء برمجية."
            else
                FINAL_MSG=$(cat "$DIAG_LOG")
            fi
            read _W _H < <(get_win_size medium)
            zenity --info \
                --title "تقرير الإصلاح" \
                --window-icon="$SYS_ICON" \
                --text "<b>$REP_HDR</b>\n\n$FINAL_MSG\n\n$TXT_SUCCESS" \
                --width=$_W 2>/dev/null
            rm -f "$DIAG_LOG"
            ;;

        # ────────────────────────────────────────────────────────
        #  MENU 3 — Network Printer Management (Add / Remove)
        # ────────────────────────────────────────────────────────
        3)
            read _W _H < <(get_win_size medium)
            MGMT_CHOICE=$(zenity --list \
                --title "$TOOL_NAME" \
                --window-icon="$SYS_ICON" \
                --text "إدارة الطابعات:" \
                --radiolist --column "" --column "ID" --column "Action" \
                TRUE  "add"    "🖨️  إضافة طابعة جديدة" \
                FALSE "remove" "🗑️  حذف طابعة" \
                --width=$_W --height=$_H 2>/dev/null)

            [ -z "$MGMT_CHOICE" ] && continue

            # ── ADD: Scan network and register a new printer ─────
            if [ "$MGMT_CHOICE" == "add" ]; then

                SCAN_LOG="/tmp/ita_scan.log"
                FOUND_FILE="/tmp/ita_found.txt"
                PROG_FILE="/tmp/ita_scan_prog.txt"
                rm -f "$FOUND_FILE" "$SCAN_LOG" "$PROG_FILE"

                # Background network scan process
                (
                    echo "5"  > "$PROG_FILE"
                    echo "# Detecting local network..." >> "$PROG_FILE"

                    LOCAL_IP=$(ip route get 8.8.8.8 2>/dev/null | grep -oE 'src [0-9.]+' | awk '{print $2}')
                    SUBNET=$(echo "$LOCAL_IP" | cut -d. -f1-3)

                    echo "# Network: $SUBNET.0/24" >> "$PROG_FILE"
                    echo "Network: $SUBNET.0/24"   >> "$SCAN_LOG"

                    # Query CUPS backends for known printer URIs
                    echo "10" > "$PROG_FILE"
                    echo "# Checking CUPS backends..." >> "$PROG_FILE"
                    timeout 15 sudo -u admin lpinfo -v 2>/dev/null \
                        | awk '{print $2}' \
                        | grep -iE '^(ipp|ipps|lpd|socket)://' \
                        | grep -viE 'everywhere|driverless|localhost|127\.0\.0' \
                        > /tmp/ita_lpinfo_uris.txt

                    # TCP port scan on ports 631 (IPP) and 9100 (RAW/JetDirect)
                    echo "20" > "$PROG_FILE"
                    echo "# Scanning ports 631 & 9100 on subnet..." >> "$PROG_FILE"
                    if [ -n "$SUBNET" ]; then
                        for i in $(seq 1 254); do
                            HOST="$SUBNET.$i"
                            (
                                if timeout 1 bash -c "echo >/dev/tcp/$HOST/631"  2>/dev/null || \
                                   timeout 1 bash -c "echo >/dev/tcp/$HOST/9100" 2>/dev/null; then
                                    echo "ipp://$HOST/ipp/print" >> /tmp/ita_scan_uris.txt
                                fi
                            ) &
                        done
                        wait
                    fi

                    echo "45" > "$PROG_FILE"
                    echo "# Collecting results..." >> "$PROG_FILE"

                    # mDNS / Bonjour discovery via Avahi if available
                    if command -v avahi-browse &>/dev/null; then
                        echo "# mDNS scan..." >> "$PROG_FILE"
                        timeout 8 avahi-browse -t -r _ipp._tcp 2>/dev/null \
                            | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' \
                            | sort -u \
                            | while read -r IP; do
                                echo "ipp://$IP/ipp/print" >> /tmp/ita_scan_uris.txt
                            done
                    fi

                    # Merge and deduplicate all discovered URIs
                    cat /tmp/ita_lpinfo_uris.txt /tmp/ita_scan_uris.txt 2>/dev/null \
                        | sort -u \
                        | grep -viE 'localhost|127\.0\.0' \
                        > /tmp/ita_uris.txt
                    rm -f /tmp/ita_lpinfo_uris.txt /tmp/ita_scan_uris.txt

                    TOTAL=$(wc -l < /tmp/ita_uris.txt 2>/dev/null || echo 0)
                    echo "Found $TOTAL potential printers" >> "$SCAN_LOG"

                    echo "50" > "$PROG_FILE"
                    echo "# Identifying printers ($TOTAL)..." >> "$PROG_FILE"

                    COUNT=0
                    while read -r URI; do
                        [ -z "$URI" ] && continue
                        COUNT=$((COUNT + 1))
                        PRINTER_IP=$(echo "$URI" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')
                        [ -z "$PRINTER_IP" ] && continue

                        REAL_MODEL=""

                        # Attempt 1: scrape model from printer web interface root page
                        WEB_PAGE=$(curl -sf --connect-timeout 3 -A "Mozilla/5.0" \
                            "http://$PRINTER_IP/" 2>/dev/null)
                        if [ -n "$WEB_PAGE" ]; then
                            REAL_MODEL=$(echo "$WEB_PAGE" \
                                | grep -ioE 'Model\s*:\s*[a-zA-Z0-9][a-zA-Z0-9\- ]{2,40}' \
                                | head -1 | sed 's/Model\s*:\s*//I' | xargs)
                            if [ -z "$REAL_MODEL" ]; then
                                REAL_MODEL=$(echo "$WEB_PAGE" \
                                    | grep -ioE '<title>[^<]{3,60}</title>' \
                                    | sed 's/<[^>]*>//g' \
                                    | grep -ioE '[a-zA-Z0-9][a-zA-Z0-9\- ]{4,40}' \
                                    | grep -iv 'home\|login\|welcome\|index\|web\|page' \
                                    | head -1 | xargs)
                            fi
                        fi

                        # Attempt 2: probe known printer-specific status URLs
                        if [ -z "$REAL_MODEL" ]; then
                            for TRY_PATH in \
                                "/general/information.html" \
                                "/info/overview.html" \
                                "/web/guest/en/websys/webArch/mainFrame.cgi" \
                                "/cgi-bin/dynamic/config/status.html" \
                                "/status.cgi"
                            do
                                TRY_PAGE=$(curl -sf --connect-timeout 2 -A "Mozilla/5.0" \
                                    "http://$PRINTER_IP${TRY_PATH}" 2>/dev/null)
                                if [ -n "$TRY_PAGE" ]; then
                                    REAL_MODEL=$(echo "$TRY_PAGE" \
                                        | grep -ioE 'Model\s*[:\-]?\s*[a-zA-Z0-9][a-zA-Z0-9\- ]{2,40}' \
                                        | head -1 | sed 's/Model\s*[:\-]\s*//I' | xargs)
                                    [ -n "$REAL_MODEL" ] && break
                                fi
                            done
                        fi

                        # Attempt 3: use ipptool to query IPP printer-make-and-model attribute
                        if [ -z "$REAL_MODEL" ] && command -v ipptool &>/dev/null; then
                            RAW_MODEL=$(timeout 5 ipptool -t "$URI" \
                                /usr/share/cups/ipptool/get-printer-attributes.test 2>/dev/null \
                                | grep -i 'printer-make-and-model' \
                                | grep -v 'REQUIRED\|STATUS\|EXPECT' \
                                | tail -1 | sed 's/.*= //;s/["\r]//g' | xargs)
                            REAL_MODEL=$(echo "$RAW_MODEL" \
                                | sed 's/KYOCERA Document Solutions Inc\.//gI' \
                                | sed 's/[Cc]orporation\b//g' \
                                | sed 's/\bInc\.\?//g' | xargs)
                        fi

                        # Fallback label when model cannot be identified
                        [ -z "$REAL_MODEL" ] && REAL_MODEL="Printer @ $PRINTER_IP"

                        [ "$TOTAL" -gt 0 ] && PROG=$(( 50 + (COUNT * 45 / TOTAL) )) || PROG=80
                        echo "$PROG" > "$PROG_FILE"
                        echo "# ($COUNT/$TOTAL) $REAL_MODEL" >> "$PROG_FILE"
                        echo "$URI||$REAL_MODEL||$PRINTER_IP" >> "$FOUND_FILE"

                    done < /tmp/ita_uris.txt
                    rm -f /tmp/ita_uris.txt

                    echo "100" > "$PROG_FILE"
                    echo "# Scan complete." >> "$PROG_FILE"
                    echo "DONE" >> "$PROG_FILE"
                ) &
                BG_PID=$!

                # Progress bar driven by the background scan process
                read _PW _PH < <(get_win_size progress)
                (
                    LAST_VAL=5
                    while kill -0 "$BG_PID" 2>/dev/null; do
                        if [ -f "$PROG_FILE" ]; then
                            NEW_VAL=$(grep '^[0-9]' "$PROG_FILE" | tail -1)
                            NEW_MSG=$(grep '^#'     "$PROG_FILE" | tail -1)
                            if [ -n "$NEW_VAL" ] && [ "$NEW_VAL" != "$LAST_VAL" ]; then
                                echo "$NEW_VAL"; LAST_VAL="$NEW_VAL"
                            fi
                            [ -n "$NEW_MSG" ] && echo "$NEW_MSG"
                        fi
                        sleep 1
                    done
                    echo "100"; echo "# Done"
                ) | zenity --progress \
                    --title "$TOOL_NAME" \
                    --window-icon="$SYS_ICON" \
                    --text "🔍 جاري البحث عن الطابعات على الشبكة..." \
                    --width=$_PW --height=$_PH --no-cancel 2>/dev/null

                wait "$BG_PID"
                rm -f "$PROG_FILE"

                # Load discovered printer list
                DISCOVERED_LIST=""
                [ -f "$FOUND_FILE" ] && DISCOVERED_LIST=$(cat "$FOUND_FILE")
                rm -f "$FOUND_FILE"

                if [ -z "$DISCOVERED_LIST" ]; then
                    read _W _H < <(get_win_size medium)
                    zenity --warning \
                        --title "$TOOL_NAME" --window-icon="$SYS_ICON" \
                        --text "⚠️ لم يتم العثور على طابعات شبكة.\n\nتأكد من:\n• تشغيل الطابعة\n• الاتصال بنفس الشبكة\n• تفعيل خدمة CUPS\n\nLog: $SCAN_LOG" \
                        --width=$_W 2>/dev/null
                    continue
                fi

                # Display discovered printers for user selection
                ZENITY_ARGS=()
                while IFS='||' read -r URI MODEL IP; do
                    [ -z "$URI" ] && continue
                    ZENITY_ARGS+=("$URI" "$MODEL" "$IP")
                done <<< "$DISCOVERED_LIST"

                SELECTED_URI=$(zenity --list \
                    --title "$TOOL_NAME" --window-icon="$SYS_ICON" \
                    --text "🖨️ اختر الطابعة لإضافتها:" \
                    --column "URI" --column "Model" --column "IP Address" \
                    --hide-column=1 --print-column=1 \
                    "${ZENITY_ARGS[@]}" \
                    --width=$_W --height=$_H 2>/dev/null)

                [ -z "$SELECTED_URI" ] && continue

                SELECTED_LINE=$(echo "$DISCOVERED_LIST" | grep "^${SELECTED_URI}||")
                SELECTED_MODEL=$(echo "$SELECTED_LINE" | awk -F'\\|\\|' '{print $2}')
                SELECTED_IP=$(echo "$SELECTED_LINE"    | awk -F'\\|\\|' '{print $3}')
                [ -z "$SELECTED_MODEL" ] && SELECTED_MODEL="Printer"

                PRINTER_NAME="kyocera-Printer"
                LPD_URI="lpd://$SELECTED_IP/queue"

                # Resolve Kyocera PPD — prefer ECOSYS M3550idn KPDL driver
                PPD_MODEL=$(lpinfo -m 2>/dev/null | grep -i "ECOSYS M3550idn" | grep -i "KPDL" | head -1 | awk '{print $1}')
                [ -z "$PPD_MODEL" ] && PPD_MODEL=$(lpinfo -m 2>/dev/null | grep -i "M3550idn" | head -1 | awk '{print $1}')
                [ -z "$PPD_MODEL" ] && PPD_MODEL=$(lpinfo -m 2>/dev/null | grep -i "ECOSYS"    | head -1 | awk '{print $1}')
                [ -z "$PPD_MODEL" ] && PPD_MODEL="drv:///sample.drv/generic.ppd"

                # If no Kyocera driver found, download and install the .deb package
                if [ "$PPD_MODEL" == "drv:///sample.drv/generic.ppd" ]; then
                    KYO_DEB_URL="https://raw.githubusercontent.com/mahmoudkassem30/Printers-Tools/dbd1722a4ffac9f42856d9d3f70faa2874d1fd93/sources/Drivers/kyodialog_9.3-0_amd64.deb"
                    KYO_DEB_FILE="/tmp/kyodialog_9.3-0_amd64.deb"
                    KYO_LOG="/tmp/ita_kyocera.log"
                    PROG_FILE="/tmp/ita_kyo_prog.txt"
                    echo "3" > "$PROG_FILE"

                    (
                        echo "$(date): Starting Kyocera driver download" > "$KYO_LOG"
                        echo "8"  > "$PROG_FILE"; echo "# Downloading Kyocera package..." >> "$PROG_FILE"

                        curl -fL --connect-timeout 20 --max-time 120 --retry 2 \
                            -o "$KYO_DEB_FILE" "$KYO_DEB_URL" 2>>"$KYO_LOG"

                        if [ $? -ne 0 ] || [ ! -s "$KYO_DEB_FILE" ]; then
                            echo "$(date): Download failed" >> "$KYO_LOG"
                            echo "FAIL" > "$PROG_FILE"
                        elif ! verify_sha256_or_abort "$KYO_DEB_FILE" "KYOCERA_DEB"; then
                            echo "$(date): Integrity check failed, refusing to install" >> "$KYO_LOG"
                            rm -f "$KYO_DEB_FILE"
                            echo "FAIL" > "$PROG_FILE"
                        else
                            echo "$(date): Download complete — $(du -sh "$KYO_DEB_FILE" | cut -f1)" >> "$KYO_LOG"
                            echo "55" > "$PROG_FILE"; echo "# Installing..." >> "$PROG_FILE"
                            DEBIAN_FRONTEND=noninteractive dpkg -i "$KYO_DEB_FILE" >>"$KYO_LOG" 2>&1
                            apt-get install -f -y >>"$KYO_LOG" 2>&1
                            rm -f "$KYO_DEB_FILE"
                            echo "80" > "$PROG_FILE"; echo "# Restarting CUPS..." >> "$PROG_FILE"
                            systemctl restart cups >>"$KYO_LOG" 2>&1
                            sleep 3
                            echo "100" > "$PROG_FILE"; echo "# Install complete" >> "$PROG_FILE"
                            echo "DONE" >> "$PROG_FILE"
                        fi
                    ) &
                    BG_PID=$!

                    read _PW _PH < <(get_win_size progress)
                    (
                        LAST_VAL=3
                        while kill -0 "$BG_PID" 2>/dev/null; do
                            if [ -f "$PROG_FILE" ]; then
                                NEW_VAL=$(grep '^[0-9]' "$PROG_FILE" | tail -1)
                                NEW_MSG=$(grep '^#'     "$PROG_FILE" | tail -1)
                                if [ -n "$NEW_VAL" ] && [ "$NEW_VAL" != "$LAST_VAL" ]; then
                                    echo "$NEW_VAL"; LAST_VAL="$NEW_VAL"
                                fi
                                [ -n "$NEW_MSG" ] && echo "$NEW_MSG"
                                grep -q "^FAIL" "$PROG_FILE" 2>/dev/null && break
                            fi
                            sleep 1
                        done
                        echo "100"; echo "# Done"
                    ) | zenity --progress \
                        --title "$TOOL_NAME" --window-icon="$SYS_ICON" \
                        --text "📦 Kyocera Printing Package\n\n📥 جاري التحميل والتثبيت تلقائياً..." \
                        --width=$_PW --height=$_PH --no-cancel 2>/dev/null

                    wait "$BG_PID"
                    rm -f "$PROG_FILE"

                    # Re-check for Kyocera PPD after install
                    PPD_MODEL=$(lpinfo -m 2>/dev/null | grep -i "ECOSYS M3550idn" | grep -i "KPDL" | head -1 | awk '{print $1}')
                    [ -z "$PPD_MODEL" ] && PPD_MODEL=$(lpinfo -m 2>/dev/null | grep -i "M3550idn" | head -1 | awk '{print $1}')
                    [ -z "$PPD_MODEL" ] && PPD_MODEL=$(lpinfo -m 2>/dev/null | grep -i "ECOSYS"    | head -1 | awk '{print $1}')
                    [ -z "$PPD_MODEL" ] && PPD_MODEL=$(lpinfo -m 2>/dev/null | grep -i "Kyocera" | grep -i "KPDL" | head -1 | awk '{print $1}')

                    if [ -z "$PPD_MODEL" ]; then
                        PPD_MODEL="drv:///sample.drv/generic.ppd"
                        zenity --warning \
                            --title "$TOOL_NAME" --window-icon="$SYS_ICON" \
                            --text "⚠️ لم يتم العثور على تعريف Kyocera بعد التثبيت.\n\nسيتم استخدام Generic.\n\nLog: $KYO_LOG" \
                            --width=$_W 2>/dev/null
                    fi
                fi

                # Register the printer in CUPS and apply default settings
                read _PW _PH < <(get_win_size progress)
                (
                    echo "10"
                    # Remove existing entry with the same name if present
                    lpstat -e 2>/dev/null | grep -q "^$PRINTER_NAME$" \
                        && sudo -u admin /usr/sbin/lpadmin -x "$PRINTER_NAME" 2>/dev/null
                    echo "30"
                    sudo -u admin /usr/sbin/lpadmin \
                        -p "$PRINTER_NAME" -E \
                        -v "$LPD_URI" \
                        -m "$PPD_MODEL" \
                        -D "$SELECTED_MODEL" \
                        -L "Network - $SELECTED_IP" \
                        2>/tmp/ita_err
                    echo "75"
                    sudo -u admin /usr/sbin/cupsenable  "$PRINTER_NAME" 2>/dev/null
                    sudo -u admin /usr/sbin/cupsaccept "$PRINTER_NAME" 2>/dev/null
                    echo "85"

                    # Detect paper feed slot key from PPD options
                    PAPERFEED_KEY=$(sudo -u admin /usr/bin/lpoptions \
                        -p "$PRINTER_NAME" -l 2>/dev/null \
                        | grep -i 'paper.*feed\|feed.*paper\|InputSlot\|MediaSource' \
                        | head -1 | cut -d'/' -f1 | xargs)

                    if [ -z "$PAPERFEED_KEY" ]; then
                        for TRY_KEY in InputSlot MediaSource PaperFeed KCFeeder; do
                            CHECK=$(sudo -u admin /usr/bin/lpoptions \
                                -p "$PRINTER_NAME" -l 2>/dev/null | grep -i "^$TRY_KEY" | head -1)
                            if [ -n "$CHECK" ]; then PAPERFEED_KEY="$TRY_KEY"; break; fi
                        done
                    fi

                    PAPERFEED_VAL=""
                    if [ -n "$PAPERFEED_KEY" ]; then
                        PAPERFEED_VAL=$(sudo -u admin /usr/bin/lpoptions \
                            -p "$PRINTER_NAME" -l 2>/dev/null \
                            | grep -i "^$PAPERFEED_KEY" \
                            | grep -ioE '\bOne\b|\bCassette1\b|\bTray1\b|\bUpper\b' | head -1)
                        [ -z "$PAPERFEED_VAL" ] && PAPERFEED_VAL="One"
                    fi

                    if [ -n "$PAPERFEED_KEY" ] && [ -n "$PAPERFEED_VAL" ]; then
                        sudo -u admin /usr/bin/lpoptions -p "$PRINTER_NAME" \
                            -o "${PAPERFEED_KEY}=${PAPERFEED_VAL}" -o Duplex=None 2>/dev/null
                        sudo -u admin /usr/sbin/lpadmin  -p "$PRINTER_NAME" \
                            -o "${PAPERFEED_KEY}=${PAPERFEED_VAL}" -o Duplex=None 2>/dev/null
                    else
                        sudo -u admin /usr/bin/lpoptions -p "$PRINTER_NAME" \
                            -o Duplex=None 2>/dev/null
                    fi
                    echo "100"
                ) | zenity --progress \
                    --title "$TOOL_NAME" --window-icon="$SYS_ICON" \
                    --text "⚙️ جاري تثبيت الطابعة..." \
                    --auto-close --width=$_PW --height=$_PH 2>/dev/null

                read _IW _IH < <(get_win_size medium)
                if lpstat -e 2>/dev/null | grep -q "^$PRINTER_NAME$"; then
                    zenity --info \
                        --title "نجاح / Success" --window-icon="$SYS_ICON" \
                        --text "✅ تمت الإضافة بنجاح!\n\n🖨️ الاسم:\n    $PRINTER_NAME\n\n📡 الموديل:\n    $SELECTED_MODEL\n\n🌐 IP: $SELECTED_IP\n\n🔌 Protocol: LPD\n🔧 Driver: $PPD_MODEL\n📄 Paper Feeder: One\n🔁 Duplex: Off" \
                        --width=$_IW 2>/dev/null
                else
                    ERR_MSG=$(cat /tmp/ita_err 2>/dev/null | head -5)
                    zenity --error \
                        --title "خطأ / Error" --window-icon="$SYS_ICON" \
                        --text "❌ فشلت إضافة الطابعة.\n\n$ERR_MSG" \
                        --width=$_IW 2>/dev/null
                fi
                rm -f /tmp/ita_err

            # ── REMOVE: Delete a registered network printer ──────
            elif [ "$MGMT_CHOICE" == "remove" ]; then

                ALL_PRINTERS=$(lpstat -e 2>/dev/null)
                if [ -z "$ALL_PRINTERS" ]; then
                    zenity --warning \
                        --title "$TOOL_NAME" --window-icon="$SYS_ICON" \
                        --text "⚠️ لا توجد طابعات مضافة في النظام." \
                        --width=$_W 2>/dev/null
                    continue
                fi

                ZENITY_ARGS=()
                while read -r PNAME; do
                    [ -z "$PNAME" ] && continue
                    URI=$(lpstat -v "$PNAME" 2>/dev/null | awk '{print $NF}')
                    if echo "$URI" | grep -qiE 'ipp|lpd|socket|http|smb'; then
                        PTYPE="🌐 Network"
                    elif echo "$URI" | grep -qiE 'usb|direct|parallel'; then
                        PTYPE="🔌 USB / Thermal"
                    else
                        PTYPE="❓ Other"
                    fi
                    ZENITY_ARGS+=("$PNAME" "$PTYPE" "$URI")
                done <<< "$ALL_PRINTERS"

                SELECTED=$(zenity --list \
                    --title "$TOOL_NAME" --window-icon="$SYS_ICON" \
                    --text "🗑️ اختر الطابعة للحذف:" \
                    --column "Name" --column "Type" --column "URI" \
                    --print-column=1 "${ZENITY_ARGS[@]}" \
                    --width=$_W --height=$_H 2>/dev/null)

                [ -z "$SELECTED" ] && continue

                zenity --question \
                    --title "Confirm" --window-icon="$SYS_ICON" \
                    --text "⚠️ هل أنت متأكد من حذف:\n\n🖨️  $SELECTED" \
                    --ok-label="نعم، احذف" --cancel-label="إلغاء" \
                    --width=$_W 2>/dev/null
                [ $? -ne 0 ] && continue

                read _PW _PH < <(get_win_size progress)
                (
                    echo "20"
                    sudo -u admin /usr/sbin/cancel -a "$SELECTED" 2>/dev/null
                    cancel -a "$SELECTED" 2>/dev/null
                    echo "50"
                    sudo -u admin /usr/sbin/cupsdisable "$SELECTED" 2>/dev/null
                    sleep 1
                    echo "70"
                    sudo -u admin /usr/sbin/lpadmin -x "$SELECTED" 2>/tmp/ita_err
                    echo "100"
                ) | zenity --progress \
                    --title "$TOOL_NAME" --window-icon="$SYS_ICON" \
                    --text "🗑️ جاري حذف الطابعة..." \
                    --auto-close --width=$_PW --height=$_PH 2>/dev/null

                read _IW _IH < <(get_win_size medium)
                if ! lpstat -e 2>/dev/null | grep -q "^$SELECTED$"; then
                    zenity --info \
                        --title "Success" --window-icon="$SYS_ICON" \
                        --text "✅ تم الحذف بنجاح!\n\n🖨️  $SELECTED" \
                        --width=$_IW 2>/dev/null
                else
                    ERR_MSG=$(cat /tmp/ita_err 2>/dev/null | head -5)
                    zenity --error \
                        --title "Error" --window-icon="$SYS_ICON" \
                        --text "❌ فشل الحذف.\n\n$ERR_MSG" \
                        --width=$_IW 2>/dev/null
                fi
                rm -f /tmp/ita_err
            fi
            ;;

        # ────────────────────────────────────────────────────────
        #  MENU 4 — Thermal Printer Management (Add / Remove)
        # ────────────────────────────────────────────────────────
        4)
            read _W _H < <(get_win_size medium)
            THERMAL_CHOICE=$(zenity --list \
                --title "$TOOL_NAME" --window-icon="$SYS_ICON" \
                --text "إدارة الطابعة الحرارية:" \
                --radiolist --column "" --column "ID" --column "Action" \
                TRUE  "add"    "🖨️  إضافة طابعة حرارية" \
                FALSE "remove" "🗑️  حذف طابعة حرارية" \
                --width=$_W --height=$_H 2>/dev/null)

            [ -z "$THERMAL_CHOICE" ] && continue

            # ── ADD: Install thermal driver and register printer ─
            if [ "$THERMAL_CHOICE" == "add" ]; then

                # Warn user to physically verify printer model before selecting
                read _W _H < <(get_win_size medium)
                zenity --warning \
                    --title "⚠️ تنبيه مهم" --window-icon="$SYS_ICON" \
                    --text "⚠️ برجاء التأكد جيداً من نوع الطابعة قبل الاختيار\n\n🔍 انظر إلى الطابعة بشكل مباشر وتأكد من اسمها:\n    • هل هي SPRT (مكتوب عليها SPRT)؟\n    • أم هي X-Printer XP-80 (مكتوب عليها XP-80)؟\n\n⚡ الاختيار الخاطئ قد يسبب مشكلة في التعريف" \
                    --width=$_W 2>/dev/null

                # Download printer model images for the card-style GTK picker
                XP_IMG="/tmp/ita_xprinter.jpg"
                SPRIT_IMG="/tmp/ita_sprit.jpg"
                curl -sfL --connect-timeout 8 \
                    "https://raw.githubusercontent.com/mahmoudkassem30/Printers-Tools/dbd1722a4ffac9f42856d9d3f70faa2874d1fd93/sources/Icons/Xprinter-xp80.jpg" \
                    -o "$XP_IMG" 2>/dev/null
                curl -sfL --connect-timeout 8 \
                    "https://raw.githubusercontent.com/mahmoudkassem30/Printers-Tools/dbd1722a4ffac9f42856d9d3f70faa2874d1fd93/sources/Icons/SPRIT.jpg" \
                    -o "$SPRIT_IMG" 2>/dev/null

                THERMAL_BRAND=""
                RESULT_FILE="/tmp/ita_thermal_choice.txt"
                rm -f "$RESULT_FILE"

                DISPLAY_OK=0
                [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ] && DISPLAY_OK=1

                # Show GTK card picker if display and Python/GTK3 are available
                if [ "$DISPLAY_OK" -eq 1 ] && \
                   python3 -c "import gi; gi.require_version('Gtk','3.0'); from gi.repository import Gtk" 2>/dev/null; then
                    sudo -u "$REAL_USER" python3 - "$XP_IMG" "$SPRIT_IMG" "$RESULT_FILE" "$SYS_ICON" << 'PYEOF'
import sys, os, gi
gi.require_version('Gtk', '3.0')
gi.require_version('GdkPixbuf', '2.0')
from gi.repository import Gtk, GdkPixbuf

xp_img_path    = sys.argv[1]
sprit_img_path = sys.argv[2]
result_file    = sys.argv[3]
icon_arg       = sys.argv[4] if len(sys.argv) > 4 else ""

win = Gtk.Window()
win.set_title("Select Thermal Printer Type")
if icon_arg:
    try:
        if os.path.isfile(icon_arg):
            win.set_icon_from_file(icon_arg)
        else:
            win.set_icon_name(icon_arg)
    except Exception:
        pass
win.set_border_width(20)
win.set_resizable(False)
win.connect("destroy", Gtk.main_quit)

css = b"""
window        { background-color: #1e1e2e; }
label.title   { color: #cba6f7; font-size: 16px; font-weight: bold; margin-bottom: 10px; }
button        { background: #313244; border: 2px solid #45475a; border-radius: 12px; padding: 12px; }
button:hover  { background: #3d3f55; border-color: #cba6f7; }
label.name    { color: #cba6f7; font-size: 14px; font-weight: bold; margin-top: 8px; }
label.sub     { color: #a6adc8; font-size: 11px; }
label.warning { color: #f38ba8; font-size: 11px; font-weight: bold; margin-top: 14px; padding: 8px; }
"""
provider = Gtk.CssProvider()
provider.load_from_data(css)
Gtk.StyleContext.add_provider_for_screen(
    win.get_screen(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
win.add(main_box)

title = Gtk.Label(label="اختر نوع الطابعة الحرارية")
title.get_style_context().add_class("title")
main_box.pack_start(title, False, False, 0)

cards_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=24)
cards_box.set_halign(Gtk.Align.CENTER)
main_box.pack_start(cards_box, False, False, 0)

def make_card(img_path, name, subtitle, choice_val):
    btn = Gtk.Button()
    btn.get_style_context().add_class("flat")
    inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
    inner.set_halign(Gtk.Align.CENTER)
    try:
        pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(img_path, 160, 130, True)
        img_widget = Gtk.Image.new_from_pixbuf(pixbuf)
    except Exception:
        img_widget = Gtk.Image.new_from_icon_name("printer", Gtk.IconSize.DIALOG)
    inner.pack_start(img_widget, False, False, 0)
    lbl_name = Gtk.Label(label=name)
    lbl_name.get_style_context().add_class("name")
    inner.pack_start(lbl_name, False, False, 0)
    lbl_sub = Gtk.Label(label=subtitle)
    lbl_sub.get_style_context().add_class("sub")
    inner.pack_start(lbl_sub, False, False, 0)
    btn.add(inner)
    def on_click(b, val=choice_val):
        with open(result_file, 'w') as f:
            f.write(val)
        Gtk.main_quit()
    btn.connect("clicked", on_click)
    return btn

cards_box.pack_start(make_card(xp_img_path,   "X-Printer", "XP-80 Series", "xprinter"), False, False, 0)
cards_box.pack_start(make_card(sprit_img_path, "SPRT",      "80mm Thermal", "sprt"),     False, False, 0)

# Warning note below selection cards — choosing wrong model breaks the driver
note_label = Gtk.Label(
    label="⚠️ برجاء التأكد جيداً من اختيار نوع الطابعة\nلأنه عند اختيار نوع مختلف لن تعمل الطابعة")
note_label.get_style_context().add_class("warning")
note_label.set_justify(Gtk.Justification.CENTER)
main_box.pack_start(note_label, False, False, 0)

win.show_all()
Gtk.main()
PYEOF
                    [ -f "$RESULT_FILE" ] && THERMAL_BRAND=$(cat "$RESULT_FILE")
                fi

                # Fallback to standard zenity list if GTK picker unavailable or cancelled
                if [ -z "$THERMAL_BRAND" ]; then
                    read _W _H < <(get_win_size medium)
                    THERMAL_BRAND=$(zenity --list \
                        --title "$TOOL_NAME" --window-icon="$SYS_ICON" \
                        --text "اختر نوع الطابعة الحرارية:\n\n⚠️ برجاء التأكد جيداً من اختيار نوع الطابعة\nلأنه عند اختيار نوع مختلف لن تعمل الطابعة" \
                        --radiolist --column "" --column "ID" --column "Type" \
                        TRUE  "xprinter" "🖨️  X-Printer  (XP-80 Series)" \
                        FALSE "sprt"     "🖨️  SPRT  (80mm Thermal)" \
                        --width=$_W --height=$_H 2>/dev/null)
                fi

                rm -f "$XP_IMG" "$SPRIT_IMG" "$RESULT_FILE"
                [ -z "$THERMAL_BRAND" ] && continue

                # Detect connected USB printer device URI
                USB_DEV=$(sudo -u admin lpinfo -v 2>/dev/null | grep -iE 'usb:/' | awk '{print $2}' | head -1)
                [ -z "$USB_DEV" ] && USB_DEV=$(lpinfo -v 2>/dev/null | grep -iE 'usb:/' | awk '{print $2}' | head -1)

                if [ -z "$USB_DEV" ]; then
                    read _W _H < <(get_win_size medium)
                    zenity --warning \
                        --title "$TOOL_NAME" --window-icon="$SYS_ICON" \
                        --text "⚠️ لم يتم اكتشاف طابعة USB.\n\nتأكد من توصيل الطابعة وتشغيلها." \
                        --width=$_W 2>/dev/null
                    continue
                fi

                THERMAL_LOG="/tmp/ita_thermal.log"
                PROG_FILE="/tmp/ita_thermal_prog.txt"
                rm -f "$THERMAL_LOG" "$PROG_FILE"

                # ── XP-80: Download installer and run it ─────────
                if [ "$THERMAL_BRAND" == "xprinter" ]; then

                    PRINTER_NAME="xp80"
                    XP_URL="https://raw.githubusercontent.com/mahmoudkassem30/Printers-Tools/dbd1722a4ffac9f42856d9d3f70faa2874d1fd93/sources/Drivers/install-xp80"
                    XP_FILE="/tmp/XP-80"

                    (
                        echo "$(date): Starting XP-80 download" > "$THERMAL_LOG"
                        echo "10" > "$PROG_FILE"; echo "# Downloading X-Printer XP-80 driver..." >> "$PROG_FILE"

                        curl -fL --connect-timeout 20 --max-time 120 --retry 2 \
                            -o "$XP_FILE" "$XP_URL" 2>>"$THERMAL_LOG"

                        if [ ! -s "$XP_FILE" ]; then
                            echo "$(date): Download failed" >> "$THERMAL_LOG"
                            echo "FAIL" > "$PROG_FILE"; exit 1
                        fi

                        if ! verify_sha256_or_abort "$XP_FILE" "XP80_INSTALLER"; then
                            echo "$(date): Integrity check failed, refusing to run installer" >> "$THERMAL_LOG"
                            rm -f "$XP_FILE"
                            echo "FAIL" > "$PROG_FILE"; exit 1
                        fi

                        echo "$(date): Download complete — $(du -sh "$XP_FILE" | cut -f1)" >> "$THERMAL_LOG"
                        echo "40" > "$PROG_FILE"; echo "# Running installer..." >> "$PROG_FILE"
                        chmod 755 "$XP_FILE"
                        cd /tmp && ./XP-80 >>"$THERMAL_LOG" 2>&1

                        echo "72" > "$PROG_FILE"; echo "# Restarting CUPS..." >> "$PROG_FILE"
                        systemctl restart cups >>"$THERMAL_LOG" 2>&1
                        sleep 2
                        rm -f "$XP_FILE"

                        echo "100" > "$PROG_FILE"; echo "# Done" >> "$PROG_FILE"
                        echo "DONE" >> "$PROG_FILE"
                    ) &
                    BG_PID=$!

                    read _PW _PH < <(get_win_size progress)
                    (
                        LAST_VAL=5
                        while kill -0 "$BG_PID" 2>/dev/null; do
                            [ -f "$PROG_FILE" ] && {
                                NV=$(grep '^[0-9]' "$PROG_FILE" | tail -1)
                                NM=$(grep '^#'     "$PROG_FILE" | tail -1)
                                [ -n "$NV" ] && [ "$NV" != "$LAST_VAL" ] && echo "$NV" && LAST_VAL="$NV"
                                [ -n "$NM" ] && echo "$NM"
                                grep -q "^FAIL" "$PROG_FILE" 2>/dev/null && break
                            }
                            sleep 1
                        done
                        echo "100"; echo "# Done"
                    ) | zenity --progress \
                        --title "$TOOL_NAME" --window-icon="$SYS_ICON" \
                        --text "⚙️ جاري تثبيت تعريف X-Printer XP-80..." \
                        --width=$_PW --height=$_PH --no-cancel 2>/dev/null

                    wait "$BG_PID"
                    rm -f "$PROG_FILE"

                    # Verify PPD is now available in CUPS
                    XP_PPD=$(lpinfo -m 2>/dev/null | grep -i "XP-80\|XP80\|xprinter" | head -1 | awk '{print $1}')
                    if [ -z "$XP_PPD" ]; then
                        read _EW _EH < <(get_win_size medium)
                        zenity --error --title "Error" --window-icon="$SYS_ICON" \
                            --text "❌ لم يتم العثور على تعريف XP-80 بعد التثبيت.\n\nLog: $THERMAL_LOG" \
                            --width=$_EW 2>/dev/null
                        continue
                    fi

                    # Register XP-80 printer in CUPS
                    read _PW _PH < <(get_win_size progress)
                    (
                        echo "20"
                        lpstat -e 2>/dev/null | grep -q "^$PRINTER_NAME$" \
                            && sudo -u admin /usr/sbin/lpadmin -x "$PRINTER_NAME" 2>/dev/null
                        echo "45"
                        sudo -u admin /usr/sbin/lpadmin \
                            -p "$PRINTER_NAME" -E \
                            -v "$USB_DEV" -m "$XP_PPD" \
                            -D "X-Printer XP-80" 2>/tmp/ita_err
                        echo "65"
                        sudo -u admin /usr/sbin/cupsenable  "$PRINTER_NAME" 2>/dev/null
                        sudo -u admin /usr/sbin/cupsaccept "$PRINTER_NAME" 2>/dev/null
                        echo "82"
                        set_thermal_defaults "$PRINTER_NAME"
                        echo "100"
                    ) | zenity --progress \
                        --title "$TOOL_NAME" --window-icon="$SYS_ICON" \
                        --text "🖨️ جاري إضافة X-Printer XP-80..." \
                        --auto-close --width=$_PW --height=$_PH 2>/dev/null

                    read _IW _IH < <(get_win_size medium)
                    if lpstat -e 2>/dev/null | grep -q "^$PRINTER_NAME$"; then
                        zenity --info --title "Success" --window-icon="$SYS_ICON" \
                            --text "✅ تمت إضافة X-Printer XP-80 بنجاح!\n\n🖨️ Name: $PRINTER_NAME\n🔌 USB: $USB_DEV\n📄 Paper: 80mm" \
                            --width=$_IW 2>/dev/null
                    else
                        ERR_MSG=$(cat /tmp/ita_err 2>/dev/null | head -5)
                        zenity --error --title "Error" --window-icon="$SYS_ICON" \
                            --text "❌ فشلت إضافة الطابعة.\n\n$ERR_MSG" \
                            --width=$_IW 2>/dev/null
                    fi
                    rm -f /tmp/ita_err

                # ── SPRT: Download individual driver files and install ──
                elif [ "$THERMAL_BRAND" == "sprt" ]; then

                    PRINTER_NAME="SPRT"
                    SPRIT_DIR="/tmp/sprit_driver_extract"
                    SPRIT_BASE_URL="https://raw.githubusercontent.com/mahmoudkassem30/Printers-Tools/dbd1722a4ffac9f42856d9d3f70faa2874d1fd93/sources/Drivers/install-SPRIT"

                    (
                        echo "$(date): Starting SPRT download" > "$THERMAL_LOG"
                        echo "10" > "$PROG_FILE"; echo "# Downloading SPRT driver files..." >> "$PROG_FILE"

                        rm -rf "$SPRIT_DIR"; mkdir -p "$SPRIT_DIR"

                        # Download all 5 required SPRT driver files individually
                        DOWNLOAD_OK=1
                        for FNAME in 80mmSeries.ppd install.sh rastertoprinter rastertoprintercm rastertoprinterlm; do
                            curl -fL --connect-timeout 20 --max-time 60 --retry 2 \
                                -o "$SPRIT_DIR/$FNAME" "$SPRIT_BASE_URL/$FNAME" 2>>"$THERMAL_LOG"
                            if [ $? -ne 0 ] || [ ! -s "$SPRIT_DIR/$FNAME" ]; then
                                echo "$(date): Failed to download $FNAME" >> "$THERMAL_LOG"
                                DOWNLOAD_OK=0
                                continue
                            fi

                            case "$FNAME" in
                                80mmSeries.ppd)      SPRIT_KEY="SPRIT_PPD" ;;
                                install.sh)          SPRIT_KEY="SPRIT_INSTALL_SH" ;;
                                rastertoprinter)      SPRIT_KEY="SPRIT_RASTER" ;;
                                rastertoprintercm)    SPRIT_KEY="SPRIT_RASTER_CM" ;;
                                rastertoprinterlm)    SPRIT_KEY="SPRIT_RASTER_LM" ;;
                            esac

                            if ! verify_sha256_or_abort "$SPRIT_DIR/$FNAME" "$SPRIT_KEY"; then
                                echo "$(date): Integrity check failed for $FNAME, refusing to install" >> "$THERMAL_LOG"
                                rm -f "$SPRIT_DIR/$FNAME"
                                DOWNLOAD_OK=0
                            else
                                echo "$(date): Downloaded and verified $FNAME" >> "$THERMAL_LOG"
                            fi
                        done

                        if [ "$DOWNLOAD_OK" -eq 0 ]; then
                            echo "FAIL" > "$PROG_FILE"; exit 1
                        fi

                        echo "35" > "$PROG_FILE"; echo "# Running install.sh..." >> "$PROG_FILE"

                        chmod +x "$SPRIT_DIR/install.sh" \
                                  "$SPRIT_DIR/rastertoprinter" \
                                  "$SPRIT_DIR/rastertoprintercm" \
                                  "$SPRIT_DIR/rastertoprinterlm" 2>>"$THERMAL_LOG"

                        (cd "$SPRIT_DIR" && ./install.sh) >>"$THERMAL_LOG" 2>&1
                        echo "$(date): install.sh completed" >> "$THERMAL_LOG"

                        # Resolve CUPS filter and PPD paths from cupsd.conf
                        SERVERROOT=$(awk '/^[[:space:]]*ServerRoot[[:space:]]+/ {print $2; exit}' /etc/cups/cupsd.conf)
                        SERVERBIN=$(awk  '/^[[:space:]]*ServerBin[[:space:]]+/  {print $2; exit}' /etc/cups/cupsd.conf)
                        DATADIR=$(awk    '/^[[:space:]]*DataDir[[:space:]]+/    {print $2; exit}' /etc/cups/cupsd.conf)

                        if [ -z "$SERVERBIN" ]; then
                            FILTERDIR="/usr/lib/cups/filter"
                        elif [ "${SERVERBIN:0:1}" = "/" ]; then
                            FILTERDIR="$SERVERBIN/filter"
                        else
                            FILTERDIR="$SERVERROOT/$SERVERBIN/filter"
                        fi

                        if [ -z "$DATADIR" ]; then
                            PPDDIR="/usr/share/cups/model/printer"
                        elif [ "${DATADIR:0:1}" = "/" ]; then
                            PPDDIR="$DATADIR/model/printer"
                        else
                            PPDDIR="$SERVERROOT/$DATADIR/model/printer"
                        fi

                        # Force-copy filter binaries to CUPS filter directory as fallback
                        mkdir -p "$FILTERDIR" "$PPDDIR" /usr/lib/cups/filter
                        for FNAME in rastertoprinter rastertoprinterlm rastertoprintercm; do
                            if [ -f "$SPRIT_DIR/$FNAME" ]; then
                                cp -f "$SPRIT_DIR/$FNAME" "$FILTERDIR/$FNAME" 2>>"$THERMAL_LOG"
                                chmod +x "$FILTERDIR/$FNAME" 2>>"$THERMAL_LOG"
                                cp -f "$SPRIT_DIR/$FNAME" "/usr/lib/cups/filter/$FNAME" 2>>"$THERMAL_LOG"
                                chmod +x "/usr/lib/cups/filter/$FNAME" 2>>"$THERMAL_LOG"
                            fi
                        done

                        # Copy PPD to CUPS model directory
                        mkdir -p /usr/share/cups/model/SPRIT
                        cp -f "$SPRIT_DIR/80mmSeries.ppd" /usr/share/cups/model/SPRIT/ 2>>"$THERMAL_LOG"

                        echo "78" > "$PROG_FILE"; echo "# Restarting CUPS..." >> "$PROG_FILE"
                        systemctl restart cups >>"$THERMAL_LOG" 2>&1
                        sleep 2

                        echo "100" > "$PROG_FILE"; echo "# Install complete" >> "$PROG_FILE"
                        echo "DONE" >> "$PROG_FILE"
                    ) &
                    BG_PID=$!

                    read _PW _PH < <(get_win_size progress)
                    (
                        LAST_VAL=5
                        while kill -0 "$BG_PID" 2>/dev/null; do
                            [ -f "$PROG_FILE" ] && {
                                NV=$(grep '^[0-9]' "$PROG_FILE" | tail -1)
                                NM=$(grep '^#'     "$PROG_FILE" | tail -1)
                                [ -n "$NV" ] && [ "$NV" != "$LAST_VAL" ] && echo "$NV" && LAST_VAL="$NV"
                                [ -n "$NM" ] && echo "$NM"
                                grep -q "^FAIL" "$PROG_FILE" 2>/dev/null && break
                            }
                            sleep 1
                        done
                        echo "100"; echo "# Done"
                    ) | zenity --progress \
                        --title "$TOOL_NAME" --window-icon="$SYS_ICON" \
                        --text "⚙️ جاري تثبيت تعريف SPRT..." \
                        --width=$_PW --height=$_PH --no-cancel 2>/dev/null

                    wait "$BG_PID"
                    rm -f "$PROG_FILE"

                    SPRIT_PPD_DEST="/usr/share/cups/model/SPRIT/80mmSeries.ppd"

                    # Verify PPD file was installed successfully
                    if [ ! -f "$SPRIT_PPD_DEST" ]; then
                        read _EW _EH < <(get_win_size medium)
                        zenity --error --title "Error" --window-icon="$SYS_ICON" \
                            --text "❌ لم يتم العثور على 80mmSeries.ppd.\n\nLog: $THERMAL_LOG" \
                            --width=$_EW 2>/dev/null
                        rm -rf "$SPRIT_DIR"; continue
                    fi

                    # Verify rastertoprinter filter binary is executable
                    if [ ! -x "/usr/lib/cups/filter/rastertoprinter" ] && \
                       [ ! -x "$FILTERDIR/rastertoprinter" ]; then
                        read _EW _EH < <(get_win_size medium)
                        zenity --error --title "Error" --window-icon="$SYS_ICON" \
                            --text "❌ Missing rastertoprinter filter.\n\nLog: $THERMAL_LOG" \
                            --width=$_EW 2>/dev/null
                        rm -rf "$SPRIT_DIR"; continue
                    fi

                    # Patch PPD to set FullCut as the default paper cut mode
                    if grep -qi "FullCut\|Full Cut\|CutType\|AutoCut" "$SPRIT_PPD_DEST" 2>/dev/null; then
                        sed -i 's/\*DefaultCutType:.*/\*DefaultCutType: FullCut/gI' "$SPRIT_PPD_DEST" 2>/dev/null
                        sed -i 's/\*DefaultAutoCut:.*/\*DefaultAutoCut: FullCut/gI' "$SPRIT_PPD_DEST" 2>/dev/null
                    fi

                    systemctl restart cups 2>/dev/null; sleep 1

                    # Register SPRT printer in CUPS
                    read _PW _PH < <(get_win_size progress)
                    (
                        echo "20"
                        lpstat -e 2>/dev/null | grep -q "^$PRINTER_NAME$" \
                            && sudo -u admin /usr/sbin/lpadmin -x "$PRINTER_NAME" 2>/dev/null
                        echo "45"
                        sudo -u admin /usr/sbin/lpadmin \
                            -p "$PRINTER_NAME" -E \
                            -v "$USB_DEV" -P "$SPRIT_PPD_DEST" \
                            -D "SPRT 80mm Thermal" 2>/tmp/ita_err
                        echo "65"
                        sudo -u admin /usr/sbin/cupsenable  "$PRINTER_NAME" 2>/dev/null
                        sudo -u admin /usr/sbin/cupsaccept "$PRINTER_NAME" 2>/dev/null
                        echo "80"
                        set_thermal_defaults "$PRINTER_NAME"
                        echo "100"
                    ) | zenity --progress \
                        --title "$TOOL_NAME" --window-icon="$SYS_ICON" \
                        --text "🖨️ جاري إضافة SPRT..." \
                        --auto-close --width=$_PW --height=$_PH 2>/dev/null

                    rm -rf "$SPRIT_DIR"

                    read _IW _IH < <(get_win_size medium)
                    if lpstat -e 2>/dev/null | grep -q "^$PRINTER_NAME$"; then
                        zenity --info --title "Success" --window-icon="$SYS_ICON" \
                            --text "✅ تمت إضافة SPRT بنجاح!\n\n🖨️ Name: $PRINTER_NAME\n🔌 USB: $USB_DEV\n📄 PPD: 80mmSeries\n✂️ Cut: Full Cut\n📄 Media: 80mm x 297mm" \
                            --width=$_IW 2>/dev/null
                    else
                        ERR_MSG=$(cat /tmp/ita_err 2>/dev/null | head -5)
                        zenity --error --title "Error" --window-icon="$SYS_ICON" \
                            --text "❌ فشلت إضافة الطابعة.\n\n$ERR_MSG" \
                            --width=$_IW 2>/dev/null
                    fi
                    rm -f /tmp/ita_err
                fi

            # ── REMOVE: Delete a thermal printer entry ───────────
            elif [ "$THERMAL_CHOICE" == "remove" ]; then
                read _W _H < <(get_win_size medium)

                ALL_PRINTERS=$(lpstat -e 2>/dev/null)
                if [ -z "$ALL_PRINTERS" ]; then
                    zenity --warning --title "$TOOL_NAME" --window-icon="$SYS_ICON" \
                        --text "⚠️ لا توجد طابعات مضافة في النظام." \
                        --width=$_W 2>/dev/null
                    continue
                fi

                ZENITY_ARGS=()
                while read -r PNAME; do
                    [ -z "$PNAME" ] && continue
                    URI=$(lpstat -v "$PNAME" 2>/dev/null | awk '{print $NF}')
                    if echo "$URI" | grep -qiE 'usb|direct|parallel'; then
                        PTYPE="🔌 USB / Thermal"
                    elif echo "$URI" | grep -qiE 'ipp|lpd|socket'; then
                        PTYPE="🌐 Network"
                    else
                        PTYPE="❓ Other"
                    fi
                    ZENITY_ARGS+=("$PNAME" "$PTYPE" "$URI")
                done <<< "$ALL_PRINTERS"

                read _W _H < <(get_win_size wide)
                SELECTED=$(zenity --list \
                    --title "$TOOL_NAME" --window-icon="$SYS_ICON" \
                    --text "🗑️ اختر الطابعة للحذف:" \
                    --column "Name" --column "Type" --column "URI" \
                    --print-column=1 "${ZENITY_ARGS[@]}" \
                    --width=$_W --height=$_H 2>/dev/null)

                [ -z "$SELECTED" ] && continue

                read _W _H < <(get_win_size medium)
                zenity --question --title "Confirm" --window-icon="$SYS_ICON" \
                    --text "⚠️ هل أنت متأكد من حذف:\n\n🖨️  $SELECTED" \
                    --ok-label="نعم، احذف" --cancel-label="إلغاء" \
                    --width=$_W 2>/dev/null
                [ $? -ne 0 ] && continue

                read _PW _PH < <(get_win_size progress)
                (
                    echo "20"
                    sudo -u admin /usr/sbin/cancel -a "$SELECTED" 2>/dev/null
                    cancel -a "$SELECTED" 2>/dev/null
                    echo "50"
                    sudo -u admin /usr/sbin/cupsdisable "$SELECTED" 2>/dev/null
                    sleep 1
                    echo "70"
                    sudo -u admin /usr/sbin/lpadmin -x "$SELECTED" 2>/tmp/ita_err
                    echo "100"
                ) | zenity --progress \
                    --title "$TOOL_NAME" --window-icon="$SYS_ICON" \
                    --text "🗑️ جاري حذف الطابعة..." \
                    --auto-close --width=$_PW --height=$_PH 2>/dev/null

                read _IW _IH < <(get_win_size medium)
                if ! lpstat -e 2>/dev/null | grep -q "^$SELECTED$"; then
                    zenity --info --title "Success" --window-icon="$SYS_ICON" \
                        --text "✅ تم الحذف بنجاح!\n\n🖨️  $SELECTED" \
                        --width=$_IW 2>/dev/null
                else
                    ERR_MSG=$(cat /tmp/ita_err 2>/dev/null | head -5)
                    zenity --error --title "Error" --window-icon="$SYS_ICON" \
                        --text "❌ فشل الحذف.\n\n$ERR_MSG" \
                        --width=$_IW 2>/dev/null
                fi
                rm -f /tmp/ita_err
            fi
            ;;

        # ────────────────────────────────────────────────────────
        #  MENU 5 — Quick Fix Print Spooler
        #  Stops CUPS, clears the spool directory, restarts CUPS
        # ────────────────────────────────────────────────────────
        5)
            read _PW _PH < <(get_win_size progress)
            (
                echo "20"
                systemctl stop cups 2>/dev/null
                echo "50"
                rm -rf /var/spool/cups/*
                echo "80"
                systemctl start cups 2>/dev/null
                echo "100"
            ) | zenity --progress \
                --title "$TOOL_NAME" --window-icon="$SYS_ICON" \
                --text "$TXT_WAIT" --auto-close 2>/dev/null

            read _W _H < <(get_win_size medium)
            zenity --info \
                --title "$TOOL_NAME" --window-icon="$SYS_ICON" \
                --text "$TXT_SUCCESS" --width=$_W 2>/dev/null
            ;;

    esac
done
