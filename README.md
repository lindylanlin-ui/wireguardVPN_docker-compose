# WireGuard VPN Server Docker Compose

這個專案的目標，是建立一台「家用情境」的 WireGuard VPN Server。

## 這份專案解決的需求

- Router 只需要做 `UDP port forward`
- iPhone / Android / MacBook Air 等裝置可從外面連回家
- 連回來後可存取家中的 NAS、桌機、其他內網設備
- client 連線後的所有 IPv4 流量都走家裡這台 WireGuard Server 出外網
- 每一台裝置使用獨立 peer 金鑰
- 遺失裝置時可把該 peer 撤銷
- 專案推上 GitHub 時，不把私人資料、金鑰、client 設定檔一起上傳

## 與 OpenVPN 的差異

WireGuard 沒有「憑證」這個概念，而是改用：

- server 金鑰對
- 每一台 client 各自一組 peer 金鑰對

所以在 WireGuard 這套專案裡：

- `add-peer.sh` 類似 OpenVPN 的「建立憑證」
- `revoke-peer.sh` 類似 OpenVPN 的「撤銷憑證」

另外要注意：

- WireGuard peer 名稱在這個映像中建議只用英文字母與數字
- 不要用空白、底線、連字號

例如可用：

- `iphone1`
- `iphone2`
- `macbookair`

## 架構說明

這份設定採用官方文件完整的 LinuxServer.io WireGuard 映像：

- `lscr.io/linuxserver/wireguard:latest`

依官方文件，當 `PEERS` 被設為 `0`、數字，或名稱清單時，容器會進入 server mode 並自動產生：

- `wg0.conf`
- server 金鑰
- peer 金鑰
- peer 的 `.conf`
- peer 的 QR 圖片

來源：

- LinuxServer.io WireGuard 文件：[https://docs.linuxserver.io/images/docker-wireguard/](https://docs.linuxserver.io/images/docker-wireguard/)

## 事前準備

你需要先準備：

- 一台可執行 Docker 的 Linux 主機
- 這台主機在家中 LAN 內有固定 IP 或 DHCP 保留位址
- Router 可設定 `UDP port forward`
- 主機核心支援 WireGuard

## Router 設定

你只需要做這一項：

- 把 router 的 `UDP 51820` 轉發到這台 WireGuard 主機的 LAN IP

例如：

- 外部 Port: `51820/UDP`
- 內部主機: `192.168.4.103`
- 內部 Port: `51820/UDP`

如果你之後在 `.env` 改成別的 `WG_SERVER_PORT`，router 也要跟著改成相同的外部 port。

## 1. 建立 `.env`

先從範本複製：

```bash
cp .env.example .env
```

再編輯 `.env`。

### 範例

```dotenv
WG_SERVER_URL=myhome.ddns.net
WG_SERVER_PORT=51820
WG_INTERNAL_SUBNET=10.13.13.0
WG_LAN_SUBNET=192.168.4.0/24
WG_PEER_DNS=1.1.1.1
WG_ALLOWEDIPS=0.0.0.0/0
WG_PERSISTENTKEEPALIVE_PEERS=all
WG_PEERS=0
PUID=1000
PGID=1000
TZ=Asia/Taipei
WG_LOG_CONFS=false
```

### 參數說明

- `WG_SERVER_URL`
  - 給外部 client 連線用的公開 IP 或 DDNS 網域
  - 如果你家是浮動 IP，建議用 DDNS
- `WG_SERVER_PORT`
  - WireGuard 對外 port
  - Router port forward 要跟這個一致
- `WG_INTERNAL_SUBNET`
  - WireGuard 內部虛擬網段的起始子網
  - 例如 `10.13.13.0`
- `WG_LAN_SUBNET`
  - 你家裡真正的 LAN 網段
  - 例如 `192.168.4.0/24`
  - 目前這份設定採用 full tunnel，所以 LAN 也會一起包含在隧道裡
- `WG_PEER_DNS`
  - peer 匯入後使用的 DNS
  - 如果你只在乎穩定上網，先用 `1.1.1.1`
  - 如果你要解析家中設備名稱，也可以改成家中 router 或內部 DNS
- `WG_ALLOWEDIPS`
  - client 端要透過 WireGuard 走的路由
  - 預設 `0.0.0.0/0` 代表所有 IPv4 流量都走家中出口
- `WG_PERSISTENTKEEPALIVE_PEERS`
  - 行動裝置常建議設成 `all`
- `WG_PEERS`
  - 目前 active peer 清單
  - `0` 代表先啟動 server，但暫時不建立任何 peer
- `PUID` / `PGID`
  - 讓容器寫出來的檔案權限與主機一致
- `WG_LOG_CONFS`
  - 是否把 conf 打到 docker logs
  - 為了安全，預設關閉

## 2. 初始化 WireGuard Server

```bash
./scripts/init-wireguard.sh
```

這個腳本會幫你完成：

- 依照 `.env` 啟動 WireGuard server
- 建立 server mode 所需設定
- 以 full tunnel 模式運作
- 保留之後新增 peer 的能力

初始化後可查看狀態：

```bash
docker compose ps
docker compose logs -f wireguard
```

## 3. 新增 peer

每一台裝置都應該使用獨立的 peer。

例如：

```bash
./scripts/add-peer.sh iphone1
./scripts/add-peer.sh iphone2
./scripts/add-peer.sh macbookair
```

腳本會幫你完成：

- 把 peer 名稱加入 `.env` 的 `WG_PEERS`
- 強制重新產生 server conf
- 重建容器，讓新 peer 生效
- 匯出 client `.conf`
- 若映像有產出 QR 圖，也一起複製出來

輸出檔會在：

```text
clients/iphone1.conf
clients/iphone1.png
clients/iphone2.conf
clients/macbookair.conf
```

### 匯入到手機或 Mac

- iPhone / Android
  - 可用 WireGuard App 匯入 `.conf`
  - 若你比較習慣掃碼，也可直接掃 `clients/*.png`
- macOS
  - 可用 WireGuard 官方 App 匯入 `.conf`

## 4. 撤銷遺失或不再使用的裝置

如果手機遺失、舊筆電淘汰，或你不再信任某台裝置，就把它對應的 peer 移除。

例如：

```bash
./scripts/revoke-peer.sh iphone1
```

腳本會幫你完成：

- 從 `WG_PEERS` 清單移除該 peer
- 刪除對應 peer 資料夾
- 重新產生 `wg0.conf`
- 重建容器，讓該 peer 立即失效
- 刪除 `clients/` 內對應的 `.conf` 與 `.png`

如果你很確定要執行，也可以略過互動確認：

```bash
./scripts/revoke-peer.sh iphone1 --yes
```

## 5. 驗證是否符合你的需求

### 驗證可否連回家

peer 連線成功後，先測試：

- 是否能 ping 到家中 NAS IP
- 是否能打開 NAS web 介面
- 是否能連到桌機或其他內網設備

### 驗證是否走家中外網

client 連上 WireGuard 後，打開：

- `https://ifconfig.me`
- `https://whatismyipaddress.com`

如果顯示的是你家中的公開 IP，就代表「所有流量都走家裡外網」已經成立。

## 6. 主機端注意事項

### 核心模組與 sysctl

LinuxServer.io 文件指出，主機需要支援 WireGuard 核心模組，並在 server mode 正常使用 iptables。

這份 compose 已經幫你帶入：

- `NET_ADMIN`
- `SYS_MODULE`
- `/lib/modules:/lib/modules:ro`
- `net.ipv4.conf.all.src_valid_mark=1`

### 避免網段衝突

如果你在外面連線的地方，剛好也使用和你家一樣的 LAN 網段，例如都叫做 `192.168.1.0/24`，那麼存取家中內網設備可能會出現衝突。

比較理想的做法是：

- 讓家中 LAN 使用較不常見的網段
- 例如 `192.168.50.0/24` 或 `10.20.30.0/24`

## 7. 隱私與 GitHub 安全

這個專案目前已經避免把以下內容提交到 GitHub：

- `.env`
- `wireguard-data/` 內的 server 設定、peer 金鑰、QR 圖片
- `clients/` 內匯出的 client 設定檔與 QR 圖

因此你可以把專案推上 GitHub，但請注意：

- 真正的私人資料在 `.env`
- 真正的敏感資料在 `wireguard-data/`
- `clients/*.conf` 本身也是敏感資料

## 常用指令

初始化：

```bash
./scripts/init-wireguard.sh
```

啟動 / 重建：

```bash
docker compose up -d
```

查看狀態：

```bash
docker compose ps
```

查看日誌：

```bash
docker compose logs -f wireguard
```

新增 peer：

```bash
./scripts/add-peer.sh iphone1
```

撤銷 peer：

```bash
./scripts/revoke-peer.sh iphone1
```

停止服務：

```bash
docker compose down
```
