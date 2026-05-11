#!/bin/bash

# --- 環境與工具檢查 ---
for cmd in cloudflared jq curl grep; do
    if ! command -v $cmd &> /dev/null; then
        echo "錯誤: 找不到指令 $cmd，請先安裝 (例如: apt install $cmd)"
        exit 1
    fi
done

echo "===================================================="
echo "開始清理無效的 Tunnel CNAME 紀錄"
echo "===================================================="

# 自動從檔案讀取 CF_TOKEN
TOKEN_FILE="/etc/cloudflared/.cf_token"
if [ -z "$CF_TOKEN" ] && [ -f "$TOKEN_FILE" ]; then
    source "$TOKEN_FILE"
    export CF_TOKEN
    echo "   [資訊] 已從 $TOKEN_FILE 自動載入 CF_TOKEN。"
fi

if [ -z "$CF_TOKEN" ]; then
    echo "錯誤: 找不到 CF_TOKEN，請確定設定了環境變數或 $TOKEN_FILE 存在。"
    exit 1
fi

# 取得現有所有的 tunnel IDs (擷取 UUID 格式)
echo "正在取得本地 Cloudflare Tunnels 列表..."
VALID_TUNNELS=$(cloudflared tunnel list | grep -oE "[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}")

if [ -z "$VALID_TUNNELS" ]; then
    echo "警告: 目前沒有找到任何有效的 Cloudflare Tunnels。"
    # 不退出，因為使用者可能真的把所有 tunnel 都刪除了，但還是想要清理 DNS
fi

# 取得所有 Zones
echo "正在取得 Cloudflare Zones..."
ZONES_RESP=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
    -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json")

ZONES=$(echo "$ZONES_RESP" | jq -c '.result[] | {id: .id, name: .name}')

if [ -z "$ZONES" ] || [ "$ZONES" == "null" ]; then
    echo "無法取得 Zones，請檢查 CF_TOKEN 權限或網路連線。"
    # 輸出原始錯誤方便除錯
    echo "$ZONES_RESP" | jq '.'
    exit 1
fi

# 迭代每個 Zone
echo "$ZONES" | while read -r zone; do
    ZONE_ID=$(echo "$zone" | jq -r '.id')
    ZONE_NAME=$(echo "$zone" | jq -r '.name')
    
    echo "檢查 Zone: $ZONE_NAME ($ZONE_ID)..."
    
    # 取得該 Zone 所有 CNAME 紀錄
    PAGE=1
    while true; do
        RECORDS_JSON=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=CNAME&per_page=100&page=$PAGE" \
            -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json")
        
        # 檢查請求是否成功
        SUCCESS=$(echo "$RECORDS_JSON" | jq -r '.success')
        if [ "$SUCCESS" != "true" ]; then
            echo "   [錯誤] 取得 DNS 紀錄失敗:"
            echo "$RECORDS_JSON" | jq -c '.errors'
            break
        fi
        
        RECORD_COUNT=$(echo "$RECORDS_JSON" | jq '.result | length')
        if [ "$RECORD_COUNT" -eq 0 ]; then
            break
        fi

        echo "$RECORDS_JSON" | jq -c '.result[]' | while read -r record; do
            REC_ID=$(echo "$record" | jq -r '.id')
            REC_NAME=$(echo "$record" | jq -r '.name')
            REC_CONTENT=$(echo "$record" | jq -r '.content')
            
            # 檢查保護名單 (絕對不能刪除)
            if [ "$REC_NAME" == "top101.ccwu.cc" ] || [ "$REC_NAME" == "top101" ] || [ "$REC_NAME" == "top101.top101.ccwu.cc" ]; then
                echo "   [保護] 受到保護的 CNAME: $REC_NAME (跳過)"
                continue
            fi
            
            # 檢查是否為 Tunnel CNAME (*.cfargotunnel.com)
            if [[ "$REC_CONTENT" == *".cfargotunnel.com" ]]; then
                # 擷取 Tunnel ID
                TUNNEL_ID=$(echo "$REC_CONTENT" | sed 's/.cfargotunnel.com//')
                
                # 檢查是否在 valid tunnels 中
                if echo "$VALID_TUNNELS" | grep -q "$TUNNEL_ID"; then
                    echo "   [保留] $REC_NAME 綁定於有效 Tunnel ($TUNNEL_ID)"
                else
                    echo "   [刪除] $REC_NAME ($REC_CONTENT) 對應的 Tunnel 已不存在..."
                    DELETE_RES=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$REC_ID" \
                        -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" | jq -r '.success')
                    if [ "$DELETE_RES" == "true" ]; then
                        echo "      -> 刪除成功"
                    else
                        echo "      -> 刪除失敗"
                    fi
                fi
            else
                echo "   [跳過] 非 Tunnel 產生的 CNAME: $REC_NAME -> $REC_CONTENT"
            fi
            
        done
        
        HAS_MORE=$(echo "$RECORDS_JSON" | jq '.result_info.total_pages > .result_info.page')
        if [ "$HAS_MORE" == "true" ]; then
            PAGE=$((PAGE + 1))
        else
            break
        fi
    done
done

echo "===================================================="
echo "清理完成"
echo "===================================================="
