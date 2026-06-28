① 設計方針（全pi -p統一の場合）
最適設計（ミニマム検証向け）:

manager（pi -p）：タスク受付・初期指示ファイル作成・最終結果集約
writer（pi -p）：ドラフト生成
reviewer（pi -p）：スコアリング・判定・差し戻しor最終承認

ワークフロー:
ユーザー → manager（pi -p） → writer → reviewer → manager（最終出力）
ポイント:

全員 pi -p で統一 → プロセスが軽量で再現性が高い（良い選択）
managerが最初に「タスク投入ファイル」を作成し、自分自身を再起動するか、直接writerをトリガー
連鎖は tmux send-keys + ファイル通信で完結

この方式はシングル vs マルチ比較に適しています。

② MEMORY.md テンプレート（pi -p対応）
manager/.pi-gl-mem/MEMORY.md
Markdown# manager - 統括（非対話モード）

## ルール（厳守）
1. inbox/ にタスクファイルがあれば読む
2. writer/inbox/ に指示ファイルを作成（{TS}_mgr_to-writer_量子コンピューティング.md）
3. tmux send-keys で writer を起動: "pi -p 'inbox/{ファイル名}'"
4. reviewerから最終報告が来たら、成果物をまとめ「=== ✅ ワークフロー完了 ===」を先頭行に出力
5. write_local_memory target=daily
writer/.pi-gl-mem/MEMORY.md
Markdown# writer - ドラフト作成（非対話）

## ルール（厳守）
1. inbox/ の指示ファイルを読み、タスクを実行してドラフトを作成
2. 可能な限りソースを明記
3. 完了後、reviewer/inbox/ に成果ファイルを作成（{TS}_w1_to-reviewer_ドラフト.md）
4. tmux send-keys -t {session}:agents.2 "pi -p 'inbox/{ファイル名}'" を実行
5. write_local_memory target=daily
reviewer/.pi-gl-mem/MEMORY.md（最重要）
Markdown# reviewer - ハルシネーション防止（非対話）

## 最重要命令
- あなたの知識だけで答えない。writer提供情報と明確な根拠のみ使用。
- 必ずスコアリングを実行。

## スコアリングシート（毎回使用）
- ソース一致度: 0-50
- 論理飛躍度: 0-30（推測表現を減点）
- 表現の断定度: 0-20

合計:
- 80点以上 → 承認
- 60-79点 → 注記付き承認
- 60点未満 → writerへ差し戻し（問題点明記）

## ルール（厳守）
1. inbox/ のwriter出力を読んでスコアリング
2. 判定後、manager/inbox/ に報告ファイル作成
3. tmux send-keys -t {session}:agents.0 "pi -p 'inbox/{ファイル名}'" を実行
4. write_local_memory target=daily

③ 最小の検証手順（今すぐ実行可能）

pi-team-minimal.sh を作成（上記MEMORY.mdを自動生成する版）
bash pi-team-minimal.sh hallucination_test
managerが起動したら、以下のタスクを投入：「2026年現在の量子コンピューティング実用化状況と、日本企業（東芝・富士通・NEC）の進捗をまとめて。」
完了後、=== ✅ ワークフロー完了 === がmanager出力にあれば成功
シングル版は別途 pi で同じタスクを実行して比較


今すぐ欲しいものを教えてください：

pi-team-minimal.sh の完全コード（80-100行程度）
上記MEMORY.mdを自動生成する版

どちらから出しますか？
pi-team-minimal.sh の完全コード（80-100行程度）
上記MEMORY.mdを自動生成する版　を短めに教えて
以下が pi-team-minimal.sh の完全コードです（約95行）。
Bash#!/bin/bash
# pi-team-minimal.sh — 固定3エージェント版（全pi -p）

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
TEAM_NAME="${1:-hallucination_test}"
TEAM_DIR="$BASE_DIR/tasks/$TEAM_NAME"
SESSION="$TEAM_NAME"
TS=$(date +%Y%m%d_%H%M)

# 固定3エージェント
AGENTS=("manager" "writer" "reviewer")
SHORTS=("mgr" "w1" "r1")
PANE=(0 1 2)

# 初回セットアップ
if [ ! -d "$TEAM_DIR" ]; then
  echo "=== ミニマムチーム生成: $TEAM_NAME ==="
  for i in "${!AGENTS[@]}"; do
    name="${AGENTS[$i]}"
    mkdir -p "$TEAM_DIR/$name/inbox" "$TEAM_DIR/$name/outbox"
    cd "$TEAM_DIR/$name"
    mkdir -p .pi-gl-mem/daily
  done

  # MEMORY.md 自動生成
  cat > "$TEAM_DIR/manager/.pi-gl-mem/MEMORY.md" << 'EOM'
# manager - 統括（非対話）

## ルール（厳守）
1. inbox/ にタスクがあれば読む
2. writer/inbox/ に指示ファイルを作成
3. tmux send-keys で writer起動
4. reviewerから最終報告を受け「=== ✅ ワークフロー完了 ===」を出力
5. write_local_memory target=daily
EOM

  cat > "$TEAM_DIR/writer/.pi-gl-mem/MEMORY.md" << 'EOM'
# writer - ドラフト作成

## ルール（厳守）
1. inbox/ の指示を読んでドラフト作成（ソース明記努力）
2. 完了後 reviewer/inbox/ に成果ファイル作成
3. tmux send-keys -t {SESSION}:agents.2 "pi -p 'inbox/{ファイル}'" Enter
4. write_local_memory target=daily
EOM

  cat > "$TEAM_DIR/reviewer/.pi-gl-mem/MEMORY.md" << 'EOM'
# reviewer - ハルシネーション防止

## 最重要
- 知識だけで答えない。writer情報のみ使用。
- 必ずスコアリング実行。

## スコアリング（毎回）
ソース一致度(0-50) / 論理飛躍度(0-30) / 表現断定度(0-20)
- 80以上 → 承認
- 60-79 → 注記付き
- 60未満 → writerへ差し戻し

## ルール（厳守）
1. inbox/ をレビュー＆スコアリング
2. manager/inbox/ に報告ファイル作成
3. tmux send-keys -t {SESSION}:agents.0 "pi -p 'inbox/{ファイル}'" Enter
4. write_local_memory target=daily
EOM

  echo "セットアップ完了"
fi

# tmux起動
tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION" -c "$TEAM_DIR/manager" -n agents
tmux split-window -h -c "$TEAM_DIR/writer"
tmux split-window -h -c "$TEAM_DIR/reviewer"
tmux select-layout tiled

echo "=== 起動完了: $TEAM_NAME ==="
echo "tmux attach -t $TEAM_NAME で接続"
echo "managerペインでタスクを投入してください（例: 量子コンピューティング...）"

# 自動待機（オプション）
if [ -n "$WT" ] || command -v wt.exe >/dev/null; then
  wt.exe wsl tmux attach -t "$SESSION" &
fi

使い方（最小検証）

ファイル保存・実行権限付与：Bashchmod +x pi-team-minimal.sh
起動：Bashbash pi-team-minimal.sh
tmux内で managerペイン に以下を入力：2026年現在の量子コンピューティングの実用化状況と、日本企業（東芝・富士通・NEC）の進捗を信頼できる情報に基づいてまとめてください。
完了を待つ（=== ✅ ワークフロー完了 === が出れば成功）
