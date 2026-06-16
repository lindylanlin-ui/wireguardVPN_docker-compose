#!/usr/bin/env sh
set -eu

# 先切回專案根目錄，避免相對路徑判斷錯誤。
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

PEER_NAME=${1:-}

validate_peer_name() {
  value=${1:-}

  case "$value" in
    ''|*[!A-Za-z0-9]*)
      echo "peer 名稱只允許英文字母與數字。" >&2
      echo "例如：iphone1、iphone2、macbookair" >&2
      exit 1
      ;;
  esac
}

update_env_var() {
  key=${1:-}
  value=${2:-}

  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    printf '%s=%s\n' "$key" "$value" >> .env
  fi
}

wait_for_peer_files() {
  peer_dir=${1:-}
  count=0
  while [ "$count" -lt 30 ]; do
    if [ -f "${peer_dir}/${peer_dir##*/}.conf" ]; then
      return 0
    fi
    sleep 2
    count=$((count + 1))
  done

  echo "等待 ${peer_dir} 內的 peer 設定檔逾時，請檢查 docker compose logs -f wireguard。" >&2
  exit 1
}

if [ -z "$PEER_NAME" ]; then
  echo "用法：$0 <peername>" >&2
  exit 1
fi

validate_peer_name "$PEER_NAME"

if [ ! -f ".env" ]; then
  echo "找不到 .env，請先從 .env.example 複製一份。" >&2
  exit 1
fi

if [ ! -f "wireguard-data/wg_confs/wg0.conf" ]; then
  echo "WireGuard server 尚未初始化，請先執行 ./scripts/init-wireguard.sh。" >&2
  exit 1
fi

. ./.env

CURRENT_PEERS=${WG_PEERS:-0}

OLD_IFS=${IFS}
IFS=','
for peer in $CURRENT_PEERS; do
  clean_peer=$(printf '%s' "$peer" | tr -d '[:space:]')
  if [ "$clean_peer" = "$PEER_NAME" ]; then
    echo "peer ${PEER_NAME} 已存在，請換一個名稱。" >&2
    IFS=${OLD_IFS}
    exit 1
  fi
done
IFS=${OLD_IFS}

if [ "$CURRENT_PEERS" = "0" ] || [ -z "$CURRENT_PEERS" ]; then
  NEW_PEERS=$PEER_NAME
else
  NEW_PEERS="${CURRENT_PEERS},${PEER_NAME}"
fi

update_env_var "WG_PEERS" "$NEW_PEERS"

# 強制重新產生 managed server conf，確保 peer 清單變更確實反映到 wg0.conf。
rm -f wireguard-data/wg_confs/wg0.conf

echo "正在新增 WireGuard peer：${PEER_NAME}"
docker compose up -d --force-recreate wireguard

PEER_DIR="wireguard-data/peer_${PEER_NAME}"
wait_for_peer_files "$PEER_DIR"

cp "${PEER_DIR}/peer_${PEER_NAME}.conf" "clients/${PEER_NAME}.conf"
if [ -f "${PEER_DIR}/peer_${PEER_NAME}.png" ]; then
  cp "${PEER_DIR}/peer_${PEER_NAME}.png" "clients/${PEER_NAME}.png"
fi

echo "已輸出 client 設定檔：clients/${PEER_NAME}.conf"
if [ -f "clients/${PEER_NAME}.png" ]; then
  echo "已輸出 QR 圖片：clients/${PEER_NAME}.png"
fi
echo "目前 active peers：${NEW_PEERS}"
