#!/usr/bin/env sh
set -eu

# 先切回專案根目錄，避免相對路徑判斷錯誤。
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

require_ipv4() {
  value=${1:-}
  name=${2:-IP}

  case "$value" in
    *.*.*.*)
      ;;
    *)
      echo "${name} 必須是 IPv4 格式，例如 10.13.13.0。" >&2
      exit 1
      ;;
  esac
}

require_cidr() {
  value=${1:-}
  name=${2:-CIDR}

  case "$value" in
    *.*.*.*/*)
      ;;
    *)
      echo "${name} 必須是 CIDR 格式，例如 192.168.4.0/24。" >&2
      exit 1
      ;;
  esac
}

require_port() {
  value=${1:-}
  name=${2:-PORT}

  case "$value" in
    ''|*[!0-9]*)
      echo "${name} 必須是數字 port。" >&2
      exit 1
      ;;
  esac

  if [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
    echo "${name} 必須介於 1 到 65535。" >&2
    exit 1
  fi
}

validate_peer_list() {
  peer_list=${1:-}

  if [ -z "$peer_list" ] || [ "$peer_list" = "0" ]; then
    return 0
  fi

  OLD_IFS=${IFS}
  IFS=','
  for peer in $peer_list; do
    clean_peer=$(printf '%s' "$peer" | tr -d '[:space:]')
    case "$clean_peer" in
      ''|*[!A-Za-z0-9]*)
        echo "WG_PEERS 只允許英文字母與數字，且不可包含空白、底線或連字號。" >&2
        exit 1
        ;;
    esac
  done
  IFS=${OLD_IFS}
}

wait_for_wg_conf() {
  count=0
  while [ "$count" -lt 30 ]; do
    if [ -f "wireguard-data/wg_confs/wg0.conf" ]; then
      return 0
    fi
    sleep 2
    count=$((count + 1))
  done

  echo "等待 wireguard-data/wg_confs/wg0.conf 逾時，請檢查 docker compose logs -f wireguard。" >&2
  exit 1
}

if ! command -v docker >/dev/null 2>&1; then
  echo "找不到 docker，請先確認 Docker 已安裝且可執行。" >&2
  exit 1
fi

if [ ! -f ".env" ]; then
  echo "找不到 .env，請先從 .env.example 複製一份。" >&2
  exit 1
fi

. ./.env

# 從 .env 讀取部署參數，缺值時套用安全預設值。
SERVER_URL=${WG_SERVER_URL:-}
SERVER_PORT=${WG_SERVER_PORT:-51820}
INTERNAL_SUBNET=${WG_INTERNAL_SUBNET:-10.13.13.0}
LAN_SUBNET=${WG_LAN_SUBNET:-}
PEER_DNS=${WG_PEER_DNS:-1.1.1.1}
ALLOWEDIPS=${WG_ALLOWEDIPS:-0.0.0.0/0}
PEERS=${WG_PEERS:-0}

if [ -z "$SERVER_URL" ] || [ "$SERVER_URL" = "vpn.example.com" ]; then
  echo "初始化前，請先在 .env 中設定正確的 WG_SERVER_URL。" >&2
  exit 1
fi

if [ -z "$LAN_SUBNET" ]; then
  echo "初始化前，請先在 .env 中設定 WG_LAN_SUBNET。" >&2
  exit 1
fi

require_port "$SERVER_PORT" "WG_SERVER_PORT"
require_ipv4 "$INTERNAL_SUBNET" "WG_INTERNAL_SUBNET"
require_cidr "$LAN_SUBNET" "WG_LAN_SUBNET"
validate_peer_list "$PEERS"

# 若已初始化過，就停止執行，避免覆蓋既有 WireGuard 設定與金鑰。
if [ -f "wireguard-data/wg_confs/wg0.conf" ]; then
  echo "偵測到 wireguard-data/wg_confs/wg0.conf 已存在。"
  echo "如果你真的要重建整套 WireGuard 設定，請先手動清除 wireguard-data 內容。" >&2
  exit 1
fi

mkdir -p wireguard-data clients

echo "正在初始化 WireGuard server：${SERVER_URL}:${SERVER_PORT}"
echo "家中 LAN 網段：${LAN_SUBNET}"
echo "client 連線後的所有 IPv4 流量會預設走家中的 WireGuard 出口。"
echo "初始 peer 清單：${PEERS}"

docker compose up -d wireguard
wait_for_wg_conf

echo
echo "初始化完成。"
echo "可用 docker compose ps 與 docker compose logs -f wireguard 檢查服務。"
echo "如需新增裝置，下一步請執行：./scripts/add-peer.sh <peername>"
