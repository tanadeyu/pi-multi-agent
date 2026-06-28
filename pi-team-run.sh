#!/bin/bash
# pi-team-run.sh v2.2.0 — tmux パイプラインペイン起動エンジン

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
INIT_SCRIPT="$HOME/.pi/agent/git/github.com/tanadeyu/pi-gl-mem/pi-gl-mem-init.sh"
WT=$(which wt.exe 2>/dev/null || true)

# === 対話入力 ===
while true; do
  echo -n "チーム名 (半角英数): "; read TEAM_NAME
  [[ "$TEAM_NAME" =~ ^[a-zA-Z0-9]+$ ]] && break
  echo "エラー: 半角英数字のみ"
done
while true; do
  echo -n "ワーカー数 (1-4): "; read WORKER_N
  [[ "$WORKER_N" =~ ^[1-4]$ ]] && break
done
SESSION="$TEAM_NAME"
TEAM_DIR="$BASE_DIR/tasks/$TEAM_NAME"

AGENTS=(manager worker01 worker02 worker03 worker04)
SHORTS=(mgr w01 w02 w03 w04)

# === ディレクトリ生成（初回のみ） ===
init_piglm() {
  if [ -f "$INIT_SCRIPT" ]; then
    echo y | bash "$INIT_SCRIPT" 2>/dev/null
  fi
  # initが失敗しても手動で作る
  mkdir -p .pi-gl-mem/daily .pi-gl-mem/notes
  echo '{"injectGlobal":false}' > .pi-gl-mem/pi_gl_settings.json
  cat > .pi-gl-mem/SCRATCHPAD.md 2>/dev/null <<< ""
}

if [ ! -d "$TEAM_DIR" ]; then
  echo "=== $TEAM_NAME（worker${WORKER_N}名）を生成 ==="
  for i in $(seq 0 $WORKER_N); do
    name="${AGENTS[$i]}"; short="${SHORTS[$i]}"
    mkdir -p "$TEAM_DIR/$name/inbox" "$TEAM_DIR/$name/outbox"
    cd "$TEAM_DIR/$name"
    [ ! -d ".pi-gl-mem" ] && init_piglm
    cd "$BASE_DIR"
  done
  # MEMORY.md を個別に書き込み
  cd "$TEAM_DIR"
  cat > manager/.pi-gl-mem/MEMORY.md <<- EOM
# manager — プロジェクト統括（対話と設定のみ。作業禁止）

## 最重要ルール
- **自分ではコードを書かない、調査しない。**
- **ただし worker の役割・経路設定として MEMORY.md を編集するのは許可。**

## ルール
1. 各 worker の役割をユーザーに順に聞く（「w01 の役割は？」→「w02 の役割は？」…）
2. 各 worker の .pi-gl-mem/MEMORY.md に write ツールで役割を追記（例: `## 役割\n担当: 設計`）
3. 処理の経路（順番）をユーザーに聞く（例: 「w01 → w02 → w03」）
4. 各 worker の .pi-gl-mem/MEMORY.md に write ツールで経路を追記（例: `## 経路\n次: w02\n次ペイン: 2`）
   最終 worker には「次: なし」を設定
5. 最初の worker 用の指示ファイルを作成
   - ファイル名: {TS}_mgr_to-{最初のworker}_{件名}.md
   - 経路情報（次: worker名／次ペイン: 番号）をファイル内に含める
6. 最初の worker を起動: tmux send-keys -t ${SESSION}:agents.1 "pi -p 'inbox/{ファイル}'" Enter
7. 以降は最終報告が来るまで待機
8. write_local_memory target=daily
EOM

  for i in $(seq 1 $WORKER_N); do
    name="${AGENTS[$i]}"; short="${SHORTS[$i]}"
    pane=$i
    cat > "$name/.pi-gl-mem/MEMORY.md" <<- EOM
# ${name} — 汎用ワーカー

## 役割
（manager が設定）

## 経路
次:
次ペイン:

## ルール
1. inbox/ の指示ファイルを読んで着手
2. 指示ファイルのタスクを実行し成果物を作成
3. 完了後、指示ファイル内の経路情報を確認:
   - 「次: (worker名)」「次ペイン: (番号)」があれば
     → 成果ファイルを ../{次}/inbox/ に作成
     → bash で tmux send-keys -t ${SESSION}:agents.{次ペイン} "pi -p 'inbox/{ファイル}'" Enter を実行
   - 「次: なし」なら manager に最終報告
     → 報告ファイルを ../manager/inbox/ に作成
     → bash で tmux send-keys -t ${SESSION}:agents.0 "[${short} 完了] 最終報告" Enter を実行
4. write_local_memory target=daily
EOM
  done
  cd "$BASE_DIR"
  echo "生成完了（$(( 1 + WORKER_N ))エージェント）"
fi

# === tmux ペイン作成（シンプル版） ===
tmux kill-session -t "$SESSION" 2>/dev/null || true
echo "=== $TEAM_NAME 起動 ==="

# ペイン0: manager
tmux new-session -d -s "$SESSION" -c "$TEAM_DIR/manager" -n agents

for i in $(seq 1 $WORKER_N); do
  name="${AGENTS[$i]}"
  tmux split-window -h -c "$TEAM_DIR/$name"
done

tmux select-layout tiled

# manager 起動＋役割設定の開始
tmux select-pane -t 0 \; send-keys "pi" Enter \; send-keys "これから各 worker の役割を設定します。w01 の役割は？" Enter

# 表示
if [ -n "$WT" ]; then
  "$WT" wsl tmux attach -t "$SESSION" &
elif which cmd.exe >/dev/null 2>&1; then
  cmd.exe /c start "tmux" wsl tmux attach -t "$SESSION"
else
  tmux attach -t "$SESSION"
fi

echo "tmux attach -t $SESSION で接続"
