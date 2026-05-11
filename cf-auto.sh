#!/bin/bash

# 使用方法: 
# 建立: sudo ./cf-auto.sh <hostname> <optional_port>
# 刪除: sudo ./cf-auto.sh delete <hostname>

# --- [建議 1] 環境與工具檢查 (Binary Check) ---
for cmd in cloudflared tmux jq curl; do
    if ! command -v $cmd &> /dev/null; then
        echo "錯誤: 找不到指令 $cmd，請先安裝 (例如: apt install $cmd)"
        exit 1
    fi
done

# --- [建議 6] 刪除模式 (Cleanup Mode) ---
if [ "$1" == "delete" ]; then
    if [ -z "$2" ]; then
        echo "使用方式: sudo [CF_TOKEN=...] $0 delete <完整主機名>"
        exit 1
    fi
    FULL_HOSTNAME=$2
    PREFIX=$(echo $FULL_HOSTNAME | cut -d'.' -f1)
    CONFIG_DIR="/etc/cloudflared"

    echo "--- [開始清理] 正在刪除隧道與 DNS 紀錄: $FULL_HOSTNAME ---"

    # 自動從檔案讀取 CF_TOKEN (如果環境變數沒設定)
    TOKEN_FILE="/etc/cloudflared/.cf_token"
    if [ -z "$CF_TOKEN" ] && [ -f "$TOKEN_FILE" ]; then
        source "$TOKEN_FILE"
        export CF_TOKEN
        echo "   [資訊] 已從 $TOKEN_FILE 自動載入 CF_TOKEN。"
    fi

    # 1. 透過 API 刪除 DNS 紀錄
    if [ -n "$CF_TOKEN" ]; then
        echo "1. 正在透過 API 搜尋並刪除 DNS 紀錄 ($FULL_HOSTNAME)..."
        
        # 取得所有 Zones 並找出符合 FULL_HOSTNAME 結尾的 Zone ID
        ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
            -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" | \
            jq -r --arg host "$FULL_HOSTNAME" '.result[] | .name as $n | select($host | endswith($n)) | .id' | head -n 1)
        
        if [ "$ZONE_ID" != "null" ] && [ -n "$ZONE_ID" ]; then
            # 取得 Record ID
            RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$FULL_HOSTNAME" \
                -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" | jq -r '.result[0].id')
            
            if [ "$RECORD_ID" != "null" ] && [ -n "$RECORD_ID" ]; then
                DELETE_RES=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
                    -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" | jq -r '.success')
                if [ "$DELETE_RES" == "true" ]; then
                    echo "   [成功] DNS 紀錄已從 Cloudflare 刪除。"
                else
                    echo "   [失敗] 無法刪除 DNS 紀錄，請檢查 Token 權限 (需有 DNS:Edit)。"
                fi
            else
                echo "   [跳過] 找不到該主機名的 DNS 紀錄 (Zone ID: $ZONE_ID)。"
            fi
        else
            echo "   [失敗] 找不到符合 $FULL_HOSTNAME 的 Zone，請確認網域已加入 Cloudflare 且 CF_TOKEN 正確。"
        fi
    else
        echo "1. [跳過] 未偵測到 CF_TOKEN，將不會刪除 Cloudflare 上的 DNS 紀錄。"
        echo "   提示: 請確保 /etc/cloudflared/.cf_token 存在且格式正確。"
    fi

    # 2. 找出 Tunnel ID 並刪除
    # 使用 grep -w 確保精確匹配隧道名稱
    TUNNEL_ID=$(cloudflared tunnel list | grep -w "$PREFIX-tunnel" | awk '{print $1}' | head -n 1)

    if [ -n "$TUNNEL_ID" ]; then
        echo "2. 正在刪除雲端隧道實體 ($TUNNEL_ID)..."
        cloudflared tunnel delete -f "$TUNNEL_ID"
    else
        echo "2. [跳過] 找不到雲端隧道 ID (名稱: $PREFIX-tunnel)。"
    fi

    # 3. 清理本地檔案
    echo "3. 清理本地設定檔..."
    rm -f "$CONFIG_DIR/$PREFIX.yml"
    [ -n "$TUNNEL_ID" ] && rm -f "$CONFIG_DIR/$TUNNEL_ID.json"

    # 4. 關閉 tmux 視窗
    echo "4. 關閉 tmux 視窗..."
    tmux kill-window -t "cf-tunnels:$PREFIX" 2>/dev/null

    echo "--- [清理完成] ---"
    exit 0
fi

if [ -z "$1" ]; then
    echo "===================================================="
    echo "Cloudflare Tunnel 自動化管理工具"
    echo "===================================================="
    echo "使用方式 (建立/重連):"
    echo "  sudo ./cf-auto.sh <完整主機名> [自訂埠號]"
    echo ""
    echo "使用方式 (刪除/清理):"
    echo "  sudo ./cf-auto.sh delete <完整主機名>"
    echo ""
    echo "參數說明:"
    echo "  <完整主機名> : 例如 web01.example.com"
    echo "  [自訂埠號]   : (選填) 若不指定，將根據名稱開頭自動判斷"
    echo "                 web -> 80, ssh -> 22, vnc -> 5900,"
    echo "                 ollama -> 11434, rdp -> 3389"
    echo ""
    echo "使用範例:"
    echo "  1. 建立 Web 服務:   sudo ./cf-auto.sh web01.top101.ccwu.cc"
    echo "  2. 建立自訂埠服務: sudo ./cf-auto.sh app01.top101.ccwu.cc 8080"
    echo "  3. 刪除現有服務:   sudo ./cf-auto.sh delete web01.top101.ccwu.cc"
    echo "===================================================="
    exit 1
fi

FULL_HOSTNAME=$1
PREFIX=$(echo $FULL_HOSTNAME | cut -d'.' -f1)
CONFIG_DIR="/etc/cloudflared"
mkdir -p $CONFIG_DIR

# 0. 找出 cert.pem 的確切位置
ORIGIN_CERT=$(find /root/.cloudflared /home/*/.cloudflared -name "cert.pem" 2>/dev/null | head -n 1)

if [ -z "$ORIGIN_CERT" ]; then
    echo "錯誤: 找不到 cert.pem。請先執行 cloudflared tunnel login"
    exit 1
fi

# 1. 判斷服務類型 (支援前綴匹配與自訂 Port)
CUSTOM_PORT=$2
case "$PREFIX" in
    web*)    SERVICE="http://localhost:${CUSTOM_PORT:-80}" ;;
    ssh*)    SERVICE="ssh://localhost:${CUSTOM_PORT:-22}" ;;
    vnc*)    SERVICE="tcp://localhost:${CUSTOM_PORT:-5900}" ;;
    ollama*) SERVICE="http://localhost:${CUSTOM_PORT:-11434}" ;;
    rdp*)    SERVICE="rdp://localhost:${CUSTOM_PORT:-3389}" ;;
    *)       SERVICE="http://localhost:${CUSTOM_PORT:-80}" ;;
esac

echo "--- 偵測到服務類型，將導向: $SERVICE ---"

# 2. 建立隧道 (支援相容已存在的隧道名稱)
echo "正在準備隧道: $PREFIX-tunnel ..."
CREATE_OUTPUT=$(cloudflared tunnel --origincert "$ORIGIN_CERT" create "$PREFIX-tunnel" 2>&1)

if [[ $CREATE_OUTPUT == *"already exists"* ]]; then
    echo "偵測到雲端已存在同名隧道，正在擷取現有 ID..."
    TUNNEL_ID=$(cloudflared tunnel list | grep "$PREFIX-tunnel" | awk '{print $1}' | head -n 1)
else
    TUNNEL_ID=$(echo "$CREATE_OUTPUT" | grep -oE "[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}" | head -n 1 | tr -d '\r\n ')
fi

if [ -z "$TUNNEL_ID" ]; then
    echo "建立失敗，輸出訊息：$CREATE_OUTPUT"
    exit 1
fi
echo "成功取得隧道! ID: $TUNNEL_ID"

# 3. 搬移金鑰與權限設定
SRC_JSON=$(find /root/.cloudflared /home/*/.cloudflared -name "$TUNNEL_ID.json" 2>/dev/null | head -n 1)
CRED_FILE="$CONFIG_DIR/$TUNNEL_ID.json"

if [ -n "$SRC_JSON" ] && [ -f "$SRC_JSON" ]; then
    cp "$SRC_JSON" "$CRED_FILE"
    chmod 600 "$CRED_FILE"
    echo "已成功同步金鑰並設定權限 (600): $CRED_FILE"
else
    echo "錯誤: 找不到金鑰檔案 $TUNNEL_ID.json"
    exit 1
fi

cat <<EOT > "$CONFIG_DIR/$PREFIX.yml"
tunnel: $TUNNEL_ID
credentials-file: $CRED_FILE
protocol: http2
ha-connections: 2

ingress:
  - hostname: $FULL_HOSTNAME
    service: $SERVICE
  - service: http_status:404
EOT

# 4. 綁定 DNS
echo "正在綁定 DNS 路由..."
sleep 1
cloudflared tunnel --origincert "$ORIGIN_CERT" route dns "$TUNNEL_ID" "$FULL_HOSTNAME"

# 5. 在 tmux 中啟動
SESSION_NAME="cf-tunnels"
tmux has-session -t $SESSION_NAME 2>/dev/null || tmux new-session -d -s $SESSION_NAME -n "manager"
tmux new-window -t $SESSION_NAME -n "$PREFIX" "cloudflared tunnel --config $CONFIG_DIR/$PREFIX.yml run"

echo "--- [任務完成] ---"
echo "網址: $FULL_HOSTNAME"
