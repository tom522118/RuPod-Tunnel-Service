#!/bin/bash

# 1. 向 Oracle Metadata 服務查詢目前的 Region
# 使用 v2 接口需要加上 Authorization Header
REGION=$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/region)

# 2. 根據回傳值判斷縮寫
if [[ "$REGION" == *"tokyo"* ]]; then
    LOC="tokyo"
elif [[ "$REGION" == *"ashburn"* ]]; then
    LOC="ashburn"
elif [[ "$REGION" == *"phoenix"* ]]; then
    LOC="phoenix"
else
    LOC="oci-vm"
fi

# 3. 定義新的 PS1 (保留 Ubuntu 預設的顏色設定，但將主機名換成區域)
# \u 是用戶名, \w 是完整路徑
NEW_PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@'$LOC'\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# 4. 寫入 ~/.bashrc (先檢查是否已經寫入過，避免重複)
if ! grep -q "PS1_AUTO_LOCATION" ~/.bashrc; then
    echo "" >> ~/.bashrc
    echo "# PS1_AUTO_LOCATION" >> ~/.bashrc
    echo "export PS1='$NEW_PS1'" >> ~/.bashrc
    echo "PS1 修改完成，請執行 'source ~/.bashrc' 或重新登入。"
else
    # 如果已經存在，則更新它
    sed -i "s|export PS1=.*# PS1_AUTO_LOCATION|export PS1='$NEW_PS1' # PS1_AUTO_LOCATION|g" ~/.bashrc
    echo "PS1 已更新為 $LOC。"
fi
