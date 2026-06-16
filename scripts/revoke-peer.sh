#!/usr/bin/env sh
set -eu

# 先切回專案根目錄，避免相對路徑判斷錯誤。
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

PEER_NAME=${1:-}
CONFIRM_FLAG=${2:-}

validate_peer_name() {
  value=${1:-}

  case "$value" in
    ''|*[!A-Za-z0-9]*)
      echo "peer 名稱只允許英文字母與數字。" >&2
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

if [ -z "$PEER_NAME" ]; then
  echo "用法：$0 <peername> [--yes]" >&2
  exit 1
fi

if [ -n "$CONFIRM_FLAG" ] && [ "$CONFIRM_FLAG" != "--yes" ]; then
  echo "第二個參數只能使用 --yes。" >&2
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
if [ "$CURRENT_PEERS" = "0" ] || [ -z "$CURRENT_PEERS" ]; then
  echo "目前沒有任何可撤銷的 peer。" >&2
  exit 1
fi

FOUND=0
NEW_PEERS=

OLD_IFS=${IFS}
IFS=','
for peer in $CURRENT_PEERS; do
  clean_peer=$(printf '%s' "$peer" | tr -d '[:space:]')
  if [ "$clean_peer" = "$PEER_NAME" ]; then
    FOUND=1
    continue
  fi

  if [ -z "$NEW_PEERS" ]; then
    NEW_PEERS=$clean_peer
  else
    NEW_PEERS="${NEW_PEERS},${clean_peer}"
  fi
done
IFS=${OLD_IFS}

if [ "$FOUND" -ne 1 ]; then
  echo "找不到 peer ${PEER_NAME}，無法撤銷。" >&2
  exit 1
fi

if [ "$CONFIRM_FLAG" != "--yes" ]; then
  printf '你確定要撤銷 WireGuard peer %s 嗎？輸入 yes 繼續：' "$PEER_NAME" >&2
  IFS= read -r answer
  if [ "$answer" != "yes" ]; then
    echo "已取消撤銷操作。" >&2
    exit 1
  fi
fi

if [ -z "$NEW_PEERS" ]; then
  NEW_PEERS=0
fi

update_env_var "WG_PEERS" "$NEW_PEERS"

# 刪除被撤銷 peer 的資料夾與 managed server conf，讓容器下次啟動時重建最新設定。
rm -rf "wireguard-data/peer_${PEER_NAME}"
rm -f wireguard-data/wg_confs/wg0.conf

echo "正在撤銷 WireGuard peer：${PEER_NAME}"
docker compose up -d --force-recreate wireguard

rm -f "clients/${PEER_NAME}.conf" "clients/${PEER_NAME}.png"

echo "已移除本機匯出的 peer 檔案：clients/${PEER_NAME}.conf / .png"
echo "目前 active peers：${NEW_PEERS}"
