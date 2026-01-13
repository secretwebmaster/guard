#!/bin/sh

# =========================
# CONFIG
# =========================

DEBUG=false   # true = always send telegram, false = only on failure

GUARD_BASE_URL="https://api.github.com/repos/secretwebmaster/guard/contents/hash"

FILES="
/www/server/nginx/conf/nginx.conf
/www/server/nginx/conf/proxy.conf
"

BOT_TOKEN="TELEGRAM_BOT_TOKEN"
CHAT_ID="TELEGRAM_CHAT_ID"

# =========================
# INTERNAL STATE
# =========================

STATUS_OK=1
FAILED_FILES=""

SERVER_IP=$(curl -fsS https://api.ipify.org 2>/dev/null || echo "UNKNOWN")

TMP_LOG="/tmp/guard_run.log"
: > "$TMP_LOG"

# redirect all output to terminal + log
exec > >(tee "$TMP_LOG") 2>&1

# =========================
# CHECK FILES
# =========================

{
echo "=================================================="
echo "SERVER IP: ${SERVER_IP}"
echo "=================================================="
echo

echo "$FILES" | while IFS= read -r REAL_FILE; do
    [ -z "$REAL_FILE" ] && continue

    echo "FILE   : $REAL_FILE"

    if [ ! -f "$REAL_FILE" ]; then
        echo "STATUS : MISSING"
        STATUS_OK=0
        FAILED_FILES="$FAILED_FILES
$REAL_FILE"
        echo
        echo "--------------------------------------------------"
        echo
        continue
    fi

    CURRENT_HASH=$(sha256sum "$REAL_FILE" | awk '{print $1}')

    REPO_PATH=$(printf "%s" "$REAL_FILE" | sed 's|^/||')
    HASH_URL="$GUARD_BASE_URL/$REPO_PATH"

    HASH_CONTENT=$(curl -fsSL \
        -H "Accept: application/vnd.github.v3.raw" \
        -H "Cache-Control: no-cache" \
        -H "Pragma: no-cache" \
        "$HASH_URL")

    if [ $? -ne 0 ] || [ -z "$HASH_CONTENT" ]; then
        echo "STATUS : HASH FETCH FAILED"
        echo "SOURCE : $HASH_URL"
        STATUS_OK=0
        FAILED_FILES="$FAILED_FILES
$REAL_FILE"
        echo
        echo "--------------------------------------------------"
        echo
        continue
    fi

    REPO_HASHES=$(printf "%s\n" "$HASH_CONTENT" \
        | sed 's/\r$//' \
        | sed '/^[[:space:]]*#/d' \
        | sed '/^[[:space:]]*$/d' \
        | grep '^[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]$')

    if printf "%s\n" "$REPO_HASHES" | grep -Fx "$CURRENT_HASH" >/dev/null 2>&1; then
        echo "STATUS : OK"
        echo "CURRENT: $CURRENT_HASH"
    else
        echo "STATUS : MISMATCH"
        echo "CURRENT: $CURRENT_HASH"
        echo "ALLOWED:"
        printf "%s\n" "$REPO_HASHES" | sed 's/^/  /'
        STATUS_OK=0
        FAILED_FILES="$FAILED_FILES
$REAL_FILE"
    fi

    echo "SOURCE : $HASH_URL"
    echo
    echo "--------------------------------------------------"
    echo
done

if [ "$STATUS_OK" -eq 1 ]; then
    echo "FINAL RESULT: ALL FILES OK"
else
    echo "FINAL RESULT: CHECK FAILED"
fi
}

# =========================
# TELEGRAM ALERT
# =========================

if [ "$DEBUG" = "true" ] || [ "$STATUS_OK" -ne 1 ]; then
    TMP_MSG="/tmp/guard_telegram_msg.txt"

    {
        echo '```'

        if [ "$DEBUG" = "true" ]; then
            cat "$TMP_LOG"
        else
            echo "=================================================="
            echo "SERVER IP: ${SERVER_IP}"
            echo "=================================================="
            echo

            printf "%s\n" "$FAILED_FILES" | while IFS= read -r f; do
                [ -z "$f" ] && continue
                awk -v file="$f" '
                    $0 ~ "^FILE[[:space:]]+:[[:space:]]+" file "$" { show=1 }
                    show { print }
                    show && /^--------------------------------------------------$/ { show=0 }
                ' "$TMP_LOG"
                echo
            done

            echo "FINAL RESULT: CHECK FAILED"
        fi

        echo '```'
    } > "$TMP_MSG"

    curl -fsS -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d parse_mode="Markdown" \
        --data-urlencode text@"$TMP_MSG" \
        > /dev/null 2>&1 || true

    rm -f "$TMP_MSG"
fi

# =========================
# EXIT
# =========================

[ "$STATUS_OK" -eq 1 ] && exit 0 || exit 1
