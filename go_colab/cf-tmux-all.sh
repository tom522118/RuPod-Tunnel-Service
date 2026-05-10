#!/bin/bash

# 設定檔目錄
CONFIG_DIR="/etc/cloudflared"
SESSION_NAME="cf-tunnels"

# 檢查 tmux session 是否存在，不存在則建立並命名第一個視窗為 manager
tmux has-session -t $SESSION_NAME 2>/dev/null
if [ $? != 0 ]; then
    tmux new-session -d -s $SESSION_NAME -n "manager"
    echo "已建立新的 tmux session: $SESSION_NAME"
fi

# 遍歷目錄下所有的 yml 檔案
for config in "$CONFIG_DIR"/*.yml; do
    # 檢查是否有檔案存在，避免目錄為空時報錯
    [ -e "$config" ] || continue

    # 取得不含路徑與副檔名的名稱 (例如 web01)
    filename=$(basename -- "$config")
    name="${filename%.*}"

    # 檢查該名稱的 tmux 視窗是否已經在跑了
    if tmux list-windows -t $SESSION_NAME | grep -q "$name"; then
        echo "跳過: 視窗 [$name] 已經在運行中。"
    else
        echo "正在啟動隧道: [$name] (使用設定檔: $filename)"
        # 建立新視窗並執行 cloudflared
        # 加上 --protocol http2 可以增加在台灣網路環境下的穩定性，避免「降級」
        tmux new-window -t $SESSION_NAME -n "$name" "sudo cloudflared tunnel --config $config --protocol http2 run"
    fi
done

echo "--- 掃描完成 ---"
echo "輸入 'tmux a -t $SESSION_NAME' 進入管理介面"
