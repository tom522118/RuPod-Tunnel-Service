#!/bin/bash

# --- 高級版：欄位數量偵測清理腳本 ---

echo "正在掃描 Cloudflare Tunnel..."
echo "目標：偵測連線欄位為空的失效 Tunnel (NF == 3)"
echo "--------------------------------------------------"

# 獲取原始資料
RAW_OUTPUT=$(cloudflared tunnel list)

# 核心邏輯：
# 1. NF == 3 表示該行只有 ID, NAME, CREATED 三個欄位 (CONNECTIONS 為空)
# 2. $1 ~ /^[0-9a-f]/ 確保第一欄是 ID (排除標題列)
unhealthy_tunnels=$(echo "$RAW_OUTPUT" | awk 'NF == 3 && $1 ~ /^[0-9a-f]/')

if [ -z "$unhealthy_tunnels" ]; then
    echo "[INFO] 目前沒有偵測到失效的 Tunnel。"
    exit 0
fi

echo "$unhealthy_tunnels" | while read -r line; do
    T_ID=$(echo "$line" | awk '{print $1}')
    T_NAME=$(echo "$line" | awk '{print $2}')

    echo "[偵測] 發現失效項目：$T_NAME (ID: $T_ID)"

    # A. 移除 DNS 路由 (CNAME)
    echo "      > 正在清理 DNS 紀錄..."
    # 這裡同樣過濾標題，確保只抓到 Domain
    routes=$(cloudflared tunnel route dns list "$T_ID" 2>/dev/null | awk '$1 ~ /\./ {print $1}')
    
    if [ -n "$routes" ]; then
        for domain in $routes; do
            echo "      >> 刪除網域: $domain"
            cloudflared tunnel route dns --delete "$T_ID" "$domain" > /dev/null 2>&1
        done
    else
        echo "      > 無關聯網域。"
    fi

    # B. 刪除 Tunnel 實體
    echo "      > 正在刪除 Tunnel 實體..."
    cloudflared tunnel delete -f "$T_ID" > /dev/null 2>&1
    
    echo "[完成] $T_NAME 清理完畢。"
    echo "--------------------------------------------------"
done

echo "程序執行結束。"
