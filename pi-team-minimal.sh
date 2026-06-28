#!/bin/bash
# pi-team-minimal.sh — 固定3エージェント版（v1.0.0方式 + Grokテンプレート）
# 使い方:
#   bash pi-team-minimal.sh <チーム名> <タスク内容>
# 例:
#   bash pi-team-minimal.sh test "2026年現在の量子コンピューティング状況をまとめて"

set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
TEAM_NAME="${1:-hallucination_test}"
TASK_CONTENT="${*:2}"
TEAM_DIR="$BASE_DIR/tasks/$TEAM_NAME"
SESSION="$TEAM_NAME"
TS=$(date +%Y%m%d_%H%M)
TIMEOUT=180

AGENTS=("manager" "writer" "reviewer")
SHORTS=("mgr" "w1" "r1")

# タスク内容がなければ入力
while [ -z "$TASK_CONTENT" ]; do
  echo -n "タスク内容: "; read TASK_CONTENT
done

# ============================================================
# MEMORY.md 生成（v1.0.0式: スクリプト側で展開）
# ============================================================
gen_memory() {
  local name="$1" role="$2"
  local file="$TEAM_DIR/$name/.pi-gl-mem/MEMORY.md"
  cat > "$file" << EOM
# $name

$role

## ルール
EOM
  shift 2
  for rule in "$@"; do
    rule="${rule//\{TS\}/$TS}"
    rule="${rule//\{SESSION\}/$SESSION}"
    rule="${rule//\{TIMEOUT\}/$TIMEOUT}"
    echo "$rule" >> "$file"
  done
}

write_memories() {
  # manager
  gen_memory "manager" "あなたは統括マネージャーです。ユーザー指示を解析しwriterにタスクを割り振り、reviewerの報告を確認して完了させる。" \
    "1. inbox/ にファイルが来たら読んで着手する" \
    "2. writerへの指示ファイルを作成する。以下の2アクションを**連続で**必ず実行せよ:" \
    "   (a) ファイルを ../writer/inbox/ に作成。ファイル名: {TS}_mgr_to-w1_v1_タスク.md。絶対パスではなく相対パス ../writer/inbox/ を使え（自分のwriter/inbox/ではない）" \
    "   (b) 【絶対必須】作成した直後に bash ツールで以下のコマンドを1行で実行せよ:" \
    "      tmux send-keys -t {SESSION}:agents.1 'echo \">>> writer 起動\" && timeout {TIMEOUT} pi -p \"inbox/ファイル名 を処理してください\"' Enter" \
    "      ※「ファイル名」は(a)で作成した実際のファイル名に置き換えること" \
    "3. reviewerからの報告（inbox/に届く）を確認する" \
    "4. 「=== ✅ 承認完了 ===」があれば最終成果物を outbox/ に保存し、先頭行に「=== ✅ ワークフロー完了 ===」と出力して完了する" \
    "5. 差し戻しの場合はwriterに再指示する。ファイル名のリビジョンを1つ上げて作成せよ（v1→v2→v3）" \
    "6. ログ: write_local_memory target=daily"

  # writer
  gen_memory "writer" "あなたはライターです。managerの指示に基づきドラフトを作成し、reviewerに提出する。" \
    "1. inbox/ にファイルが来たら読んで着手する" \
    "2. 可能な限りソースを明記する。推測部分は「（推測）」と明示する" \
    "3. ファイル名でリビジョンを管理する。inbox/ に届いた指示ファイル名からリビジョンを判断せよ:" \
    "   - 初回: ファイル名に _v1 を付けて reviewer/inbox/ に作成" \
    "   - 差し戻し1回目: _v2 で作成（最大 _v3 まで。_v3 でも差し戻しが来た場合はそのまま manager に送る）" \
    "   - ファイル名例: {TS}_w1_to-reviewer_v1_成果.md" \
    "   - パス: ../reviewer/inbox/" \
    "4. 【絶対必須】作成した直後に bash ツールで以下のコマンドを1行で実行せよ:" \
    "      tmux send-keys -t {SESSION}:agents.2 'echo \">>> reviewer 起動\" && timeout {TIMEOUT} pi -p \"inbox/ファイル名 を処理してください\"' Enter" \
    "      ※「ファイル名」は手順3で作成した実際のファイル名に置き換えること" \
    "5. ログ: write_local_memory target=daily"

  # reviewer（Grokスコアリングシート組み込み）
  gen_memory "reviewer" "あなたはレビュアーです。writerの成果物を検証しスコアリングする。あなたの知識で補完してはならない。" \
    "1. inbox/ にファイルが来たら読んで着手する" \
    "2. 【最重要】bash で date コマンドを実行し現在日付を確認してから評価を開始せよ" \
    "3. ファイル名からリビジョンを確認する。_v3 以上の場合は差し戻し禁止。強制的に承認（85点未満でも注記付き承認）して manager へ送れ" \
    "4. writerの成果物を以下のスコアシートで評価する:" \
    "   【ソース信頼性】(0-40点): 一次ソース(公式サイトなど)=40、二次ソース(Wikipediaなど)=20、ソースなし=0" \
    "   【最新性】(0-30点): 現在日付と比較して最新=30、1年前まで=15、2年以上前=0。年月が未記載なら-10" \
    "   【論理・一貫性】(0-20点): 内部矛盾なし=20、軽微な矛盾=10、重大な矛盾=0" \
    "   【表現の慎重さ】(0-10点): 客観的断定で慎重=10、過度な断定や曖昧=5以下" \
    "5. 合計点とリビジョンに応じて処理する:" \
    "   - 85点以上 → 「=== ✅ 承認完了 ===」を含めて manager/inbox/ に承認報告" \
    "   - 70〜84点 → 「※要確認情報あり」と注記して manager/inbox/ に報告" \
    "   - 70点未満 かつ _v2 以下 → 問題点を挙げて writer/inbox/ に差し戻し" \
    "   - 70点未満 かつ _v3 以上 → 差し戻し禁止。注記付きで manager/inbox/ に報告" \
    "6. 判定結果に応じて以下の2アクションを**連続で**必ず実行せよ:" \
    "   (a) 報告ファイルを該当エージェントの inbox/ に作成する。パスを間違えるな:" \
    "      - manager宛: ../manager/inbox/ に作成（自分のmanager/inbox/ではない）" \
    "      - writer宛:  ../writer/inbox/ に作成" \
    "   (b) 【絶対必須】作成した直後に bash ツールで以下のいずれかのコマンドを1行で実行せよ:" \
    "      - manager宛: tmux send-keys -t {SESSION}:agents.0 'echo \">>> manager 再起動\" && timeout {TIMEOUT} pi -p \"inbox/ファイル名 を処理してください\"' Enter" \
    "      - writer宛:  tmux send-keys -t {SESSION}:agents.1 'echo \">>> writer 差し戻し\" && timeout {TIMEOUT} pi -p \"inbox/ファイル名 を処理してください\"' Enter" \
    "      ※「ファイル名」は(a)で作成した実際のファイル名に置き換えること" \
    "7. ログ: write_local_memory target=daily"
}

# ============================================================
# ディレクトリセットアップ
# ============================================================
if [ ! -d "$TEAM_DIR" ]; then
  echo "=== $TEAM_NAME を初期化 ==="
  for i in 0 1 2; do
    name="${AGENTS[$i]}"
    mkdir -p "$TEAM_DIR/$name/inbox" "$TEAM_DIR/$name/outbox"
    mkdir -p "$TEAM_DIR/$name/.pi-gl-mem/daily"
  done
  write_memories
  echo "3エージェント構成完了"
else
  echo "=== $TEAM_NAME は既存。MEMORY.md のみ再生成 ==="
  write_memories
fi

# ============================================================
# タスク投入
# ============================================================
TASK_FILE="${TS}_task.md"
echo "$TASK_CONTENT" > "$TEAM_DIR/manager/inbox/$TASK_FILE"
echo "タスク作成: manager/inbox/$TASK_FILE"

# ============================================================
# tmux 起動
# ============================================================
tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION" -c "$TEAM_DIR/manager" -n agents
tmux split-window -h -c "$TEAM_DIR/writer"
tmux split-window -h -c "$TEAM_DIR/reviewer"
tmux select-layout tiled

# エージェント0（manager）を起動（timeout付き）
sleep 1
tmux send-keys -t 0 \
  "timeout $TIMEOUT pi -p 'inbox/$TASK_FILE を処理してください'" Enter

# ============================================================
# 完了検出ループ（v1.0.0式: ポーリング）
# ============================================================
if which wt.exe >/dev/null 2>&1; then
  "$(which wt.exe)" wsl tmux attach -t "$SESSION" &
elif which cmd.exe >/dev/null 2>&1; then
  cmd.exe /c start "tmux" wsl tmux attach -t "$SESSION"
fi

echo ""
echo "===== 起動完了: tmux attach -t $SESSION ====="
echo "ペイン0: manager（実行中）"
echo "ペイン1: writer（待機）"
echo "ペイン2: reviewer（待機）"
echo ""

# 完了検出ループ
for i in $(seq 1 30); do
  sleep 10
  # 完了マーカーを検出
  FOUND=$(find "$TEAM_DIR/manager/inbox/" -type f -newer "$TEAM_DIR/manager/inbox/$TASK_FILE" 2>/dev/null | head -1)
  if [ -n "$FOUND" ]; then
    head -1 "$FOUND" 2>/dev/null | grep -q "=== ✅ ワークフロー完了 ===" && {
      echo "╔════════════════════════════════════════╗"
      echo "║      ✅ ワークフロー完了！            ║"
      echo "╚════════════════════════════════════════╝"
      exit 0
    }
  fi
done

echo "⏰ タイムアウト（5分経過）"
exit 1
