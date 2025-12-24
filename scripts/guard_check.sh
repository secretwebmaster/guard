#!/bin/bash

# =========================
# CONFIG
# =========================

DEBUG=false   # true = always send telegram, false = only on failure

GUARD_BASE_URL="https://raw.githubusercontent.com/secretwebmaster/guard/main/hash"

FILES=(
/www/server/nginx/conf/nginx.conf
/www/server/nginx/conf/proxy.conf
)

BOT_TOKEN="TELEGRAM_BOT_TOKEN"
CHAT_ID="TELEGRAM_CHAT_ID"

# =========================
# INTERNAL STATE
# =========================

STATUS_OK=1
FAILED_FILES=()

SERVER_IP=$(curl -s https://api.ipify.org)

TMP_LOG="/tmp/guard_run.log"
: > "$TMP_LOG"
# redirect all output to terminal + log (NO subshell)
exec > >(tee "$TMP_LOG") 2>&1

# =========================
# CHECK FILES
# =========================

{
echo "=================================================="
echo "SERVER IP: ${SERVER_IP}"
echo "=================================================="
echo

for REAL_FILE in "${FILES[@]}"; do
    echo "FILE   : $REAL_FILE"

    if [ ! -f "$REAL_FILE" ]; then
        echo "STATUS : MISSING"
        STATUS_OK=0
        FAILED_FILES+=("$REAL_FILE")
        echo
        echo "--------------------------------------------------"
        echo
        continue
    fi

    CURRENT_HASH=$(sha256sum "$REAL_FILE" | awk '{print $1}')
    HASH_URL="$GUARD_BASE_URL$REAL_FILE"

    HASH_CONTENT=$(curl -fsSL \
        -H "Cache-Control: no-cache" \
        -H "Pragma: no-cache" \
        "$HASH_URL")

    if [ -z "$HASH_CONTENT" ]; then
        echo "STATUS : HASH FILE NOT FOUND"
        echo "SOURCE : $HASH_URL"
        STATUS_OK=0
        FAILED_FILES+=("$REAL_FILE")
        echo
        echo "--------------------------------------------------"
        echo
        continue
    fi

    REPO_HASHES=$(echo "$HASH_CONTENT" | sed 's/\r$//' | sed '/^[[:space:]]*#/d' | sed '/^[[:space:]]*$/d')
    MATCHED_HASH=$(echo "$REPO_HASHES" | grep -Fx "$CURRENT_HASH")

    if [ -n "$MATCHED_HASH" ]; then
        echo "STATUS : OK"
        echo "CURRENT: $CURRENT_HASH"
        echo "MATCH  : $MATCHED_HASH"
    else
        echo "STATUS : MISMATCH"
        echo "CURRENT: $CURRENT_HASH"
        echo "ALLOWED:"
        echo "$(echo "$REPO_HASHES" | sed 's/^/  /')"
        STATUS_OK=0
        FAILED_FILES+=("$REAL_FILE")
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
            # DEBUG mode: send full output
            cat "$TMP_LOG"
        else
            # Non-debug: send only failed file blocks
            for f in "${FAILED_FILES[@]}"; do
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

    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d parse_mode="Markdown" \
        --data-urlencode text@"$TMP_MSG" \
        > /dev/null

    rm -f "$TMP_MSG"
fi


# =========================
# EXIT
# =========================

[ "$STATUS_OK" -eq 1 ] && exit 0 || exit 1
