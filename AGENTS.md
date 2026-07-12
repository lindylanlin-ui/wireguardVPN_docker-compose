# AGENTS.md

## 專案概要

這個倉庫以 Docker Compose 與 POSIX shell scripts 部署家用 WireGuard VPN server。主要映像為 `lscr.io/linuxserver/wireguard:latest`，預設提供 IPv4 full-tunnel，並以每台裝置一個 peer 的方式管理存取權。

所有變更都應優先維持以下特性：

- Router 只需將 WireGuard UDP port 轉發到 Docker host。
- VPN client 可存取家中 LAN，且所有 IPv4 流量由家中網路出站。
- 每個 peer 使用獨立金鑰，並可單獨新增或撤銷。
- 私密金鑰、實際部署參數、client 設定與 QR code 永不進入版控。

## 目錄與檔案

- `docker-compose.yml`：WireGuard service、capabilities、環境變數、volume、port 與 sysctl 設定。
- `.env.example`：可提交的設定範本，也是環境變數的文件來源。
- `.env`：實際部署設定；可能包含公開端點與 peer 名稱，不可提交或在回覆中完整輸出。
- `scripts/init-wireguard.sh`：首次初始化 server。
- `scripts/add-peer.sh`：新增 peer、重建 managed config，並匯出 client 檔案。
- `scripts/revoke-peer.sh`：撤銷 peer、刪除其資料並重建 managed config。
- `wireguard-data/`：server/peer 設定與私密金鑰；除 `.gitkeep` 外一律視為機密且不可修改、讀取或提交。
- `clients/`：匯出的 client `.conf` 與 QR code；除 `.gitkeep` 外一律視為機密且不可讀取或提交。
- `logs/`：執行日誌；不可提交。
- `logrotate/`：主機端 logrotate 設定。
- `README.md`：使用者操作與部署文件，內容以繁體中文撰寫。

## 開發原則

- Shell scripts 必須保持 POSIX `sh` 相容，使用 `#!/usr/bin/env sh` 與 `set -eu`；不要加入 Bash 專用語法，例如 arrays、`[[ ... ]]` 或 process substitution。
- Scripts 應從自身位置解析專案根目錄，再執行相對路徑操作，避免依賴呼叫者目前所在目錄。
- 變數皆加雙引號；讀取輸入使用 `IFS= read -r`；暫時更改 `IFS` 後必須還原。
- 錯誤訊息寫入 stderr，錯誤時回傳非零狀態；破壞性操作前保留明確確認機制。
- Peer 名稱限制為 ASCII 英文字母與數字，保持與 LinuxServer.io managed peer 命名方式及現有 scripts 一致。
- 新增或更名環境變數時，同步更新 `docker-compose.yml`、`.env.example`、相關 scripts 與 `README.md`。不要自動改寫使用者的 `.env`，除非該行為正是受測 script 的既有職責。
- Compose 中的預設值應與 `.env.example` 及 README 一致。安全相關預設值不可在未說明風險的情況下放寬。
- 使用繁體中文維護使用者文件、註解與 CLI 訊息；識別字、指令、檔名及通用技術名詞可保留英文。
- 只修改任務所需檔案，不要格式化或重寫無關內容。

## 安全界線

以下規則高於便利性：

- 不要顯示、搜尋、複製、修改或提交 `.env`、`wireguard-data/`、`clients/` 中的實際內容。
- 不要將 private key、preshared key、完整 peer config、QR code、公開 IP、DDNS 名稱或實際 peer 清單寫入測試輸出、fixture、文件、issue 或 commit。
- 不要用真實資料做測試；需要範例時使用 `.env.example` 及明顯的保留值，例如 `vpn.example.com`、`192.0.2.0/24`。
- 除非使用者明確要求並理解影響，不要刪除 `wireguard-data/`、`wg0.conf`、peer 資料夾、client 匯出檔或 `.env`。
- 不要為了驗證而執行 `init-wireguard.sh`、`add-peer.sh`、`revoke-peer.sh`、`docker compose up/down/restart` 或任何會重建容器／網路設定的指令。
- 不要變更 host firewall、iptables、sysctl、kernel modules、Router port forwarding 或系統 logrotate；這些屬於主機級操作，需由使用者明確授權。
- 維持 `WG_LOG_CONFS=false` 的安全預設，避免設定與金鑰進入 logs。

## 驗證方式

優先執行不會改變部署狀態的檢查：

```sh
sh -n scripts/*.sh
docker compose config --quiet
git diff --check
```

若環境已安裝 ShellCheck，再執行：

```sh
shellcheck -s sh scripts/*.sh
```

驗證注意事項：

- `docker compose config --quiet` 只用於驗證 Compose；不要輸出完整 render 結果，避免洩漏 `.env` 的部署資訊。
- 若修改參數驗證邏輯，優先以臨時目錄、stubbed `docker` 與假的 `.env` 做隔離測試，不可操作目前工作目錄中的真實部署資料。
- 涉及實際 VPN handshake、LAN 路由、DNS、port forwarding 或外部 IP 的驗證無法安全自動化時，清楚列出尚未執行的人工驗證，不要宣稱已通過。

## 完成條件

提交變更前確認：

- Shell 與 Compose 靜態檢查通過，或已說明無法執行的原因。
- `.env.example`、README、Compose 與 scripts 對同一設定的名稱、預設值及限制一致。
- `git status --short` 中沒有 `.env`、金鑰、peer config、QR code 或 logs。
- 未覆寫或刪除使用者現有的 WireGuard 狀態。
- 回覆中簡述變更、已執行的驗證，以及仍需使用者在真實環境確認的項目。
