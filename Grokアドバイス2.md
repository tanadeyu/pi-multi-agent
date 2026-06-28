以下に完全回答します。
1. pi-team-minimal.sh（v2.2.0ベース・固定3エージェント版）
Bash#!/bin/bash
# pi-team-minimal.sh — 固定3エージェント版（manager/writer/reviewer、全pi -p）

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
TEAM_NAME="${1:-hallucination_test}"
TEAM_DIR="$BASE_DIR/tasks/$TEAM_NAME"
SESSION="$TEAM_NAME"
TS=$(date +%Y%m%d_%H%M)

AGENTS=("manager" "writer" "reviewer")
SHORTS=("mgr" "w1" "r1")

if [ ! -d "$TEAM_DIR" ]; then
  echo "=== 固定3エージェント ミニマム版 生成 ==="
  for i in "${!AGENTS[@]}"; do
    name="${AGENTS[$i]}"
    mkdir -p "$TEAM_DIR/$name/inbox" "$TEAM_DIR/$name/outbox"
    cd "$TEAM_DIR/$name"
    mkdir -p .pi-gl-mem/daily
  done

  # MEMORY.md 生成（詳細版）
  cat > "$TEAM_DIR/manager/.pi-gl-mem/MEMORY.md" << 'EOM'
# manager - 統括（非対話モード）

## ルール（厳守）
1. inbox/ にユーザー指示があれば読む
2. writer/inbox/ にタスク指示ファイルを作成（ファイル名に{TS}使用）
3. tmux send-keys -t {SESSION}:agents.1 "pi -p 'inbox/{ファイル名}'" Enter を実行
4. reviewerから最終報告を受け取ったら成果物をまとめ、先頭行に「=== ✅ ワークフロー完了 ===」を出力
5. write_local_memory target=daily
EOM

  cat > "$TEAM_DIR/writer/.pi-gl-mem/MEMORY.md" << 'EOM'
# writer - ドラフト作成

## ルール（厳守）
1. inbox/ の指示ファイルを読み、タスクを実行してドラフトを作成
2. 可能な限りソースを明記し、推測部分は「（推測）」と記載
3. 完了後、reviewer/inbox/ に成果ファイルを作成（{TS}_w1_to-reviewer_... .md）
4. bashで tmux send-keys -t {SESSION}:agents.2 "pi -p 'inbox/{ファイル名}'" Enter を実行
5. write_local_memory target=daily
EOM

  cat > "$TEAM_DIR/reviewer/.pi-gl-mem/MEMORY.md" << 'EOM'
# reviewer - ハルシネーション防止・審査

## 最重要命令
- あなたの知識だけで答えない。writer提供情報と明確な根拠のみ使用。
- すべての主張にソース引用を試みること。

## スコアリングシート（必ず適用）
【ソース一致度】0-50点
【論理飛躍度】0-30点（「と思われる」「可能性が高い」などの推測表現を検知して減点）
【表現の断定度】0-20点（断定的表現を高評価）

## 判定基準
- 80点以上 → 承認して managerへ最終報告
- 60-79点 → 「※AI推測部分あり」と注記して managerへ
- 60点未満 → 問題点を具体的に指摘して writerへ差し戻し

## ルール（厳守）
1. inbox/ のwriter出力をスコアリング
2. 判定後、manager/inbox/ に報告ファイルを作成
3. bashで tmux send-keys -t {SESSION}:agents.0 "pi -p 'inbox/{ファイル名}'" Enter を実行
4. write_local_memory target=daily
EOM

  echo "ミニマム版セットアップ完了"
fi

# tmux起動
tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION" -c "$TEAM_DIR/manager" -n agents
tmux split-window -h -c "$TEAM_DIR/writer"
tmux split-window -h -c "$TEAM_DIR/reviewer"
tmux select-layout tiled

echo "=== 起動完了: tmux attach -t $TEAM_NAME ==="

2. MEMORY.md テンプレート（上記スクリプトに既に組み込み済み）
上記のスクリプト内で自動生成される内容がそのまま完全テンプレートです。特にreviewerのスコアリング部分は具体的に記載しています。
tmux send-keysの部分は {SESSION} と {ファイル名} をエージェントが文脈で適切に置き換えるよう指示しています（piの能力で十分対応可能）。

3. テスト手順（シングル vs マルチ比較）
テストタスク（固定）:
「2026年現在の量子コンピューティングの実用化状況と、日本企業（東芝・富士通・NEC）の具体的な進捗・マイルストーン・商用化予定を、信頼できる情報に基づいて詳細にまとめてください。」
手順:

マルチ版（3エージェント）
bash pi-team-minimal.sh
tmux attachしてmanagerペインで上記タスクを貼り付け
完了まで待つ（=== ✅ ワークフロー完了 === が出る）
出力結果を result_multi_1.md などに保存

シングル版
別ターミナルで pi を起動
同じタスクを入力
出力結果を result_single_1.md に保存

これを5回繰り返す（同じタスクで）

ハルシネーションの数え方（各出力ごとに）:

明確な事実誤り（例: 存在しない企業発表、間違った年号）
根拠のない強い断定（「〜である」「〜に成功した」などソースなし）
推測表現の多用（「と思われる」「可能性が高い」など）

記録シート例（各実行後に手動で作成）:
Markdown### 実行1 - マルチ
ハルシネーション数: 2
推測表現数: 3
ソース引用数: 4
品質スコア: 7/10
所要時間: 約4分
5回分の平均を比較すれば、マルチ版の方がハルシネーションが少ないかどうかが明確になります。

このスクリプトを保存して試してみてください。
動かない部分や改善点があればすぐに修正します。
