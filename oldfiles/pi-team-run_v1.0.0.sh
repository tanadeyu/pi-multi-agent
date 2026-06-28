#!/bin/bash
# pi-team-run.sh — マルチエージェントチームの生成・起動
# 使い方: bash pi-team-run.sh team_a
#         実行ごとに新しいタスクがタイムスタンプ付きで作成される
set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
INIT_SCRIPT="$HOME/.pi/agent/git/github.com/tanadeyu/pi-gl-mem/pi-gl-mem-init.sh"

# === 引数解決 ===
TEAM_NAME="${1:?Usage: bash pi-team-run.sh <team-name>}"
CONFIG="$BASE_DIR/$TEAM_NAME.json"
TEAM_DIR="$BASE_DIR/teams/$TEAM_NAME"

# ============================================================
# 定数
# ============================================================
WT=$(which wt.exe 2>/dev/null || true)
TS=$(date +%Y%m%d_%H%M)  # この実行のタイムスタンプ

# ============================================================
# デフォルトエージェント定義
# ============================================================
DEFAULT_AGENTS=(
  "agent1_editor:あなたは編集者（ディレクター）です。ユーザーからの指示を解析しタスクに分解、agent2_writerに指示を出し、品質を管理します。"
  "agent2_writer:あなたはライターです。agent1_editorからの指示に従いコードや文章を実装し、成果物をagent3_reviewerに提出します。"
  "agent3_reviewer:あなたはレビュアーです。agent2_writerの成果物をチェックし、修正が必要ならフィードバック、合格ならagent1_editorに承認報告をします。"
)

gen_memory() {
  local name="$1" role="$2" short="$3"
  shift 3
  local rules=("$@")

  {
    echo "# $name 役割"
    echo "$role"
    echo ""
    echo "## ルール"
    local i=1
    for rule in "${rules[@]}"; do
      rule="${rule//\{TS\}/$TS}"
      rule="${rule//\{short\}/$short}"
      echo "$i. $rule"
      i=$((i + 1))
    done
  } > "$TEAM_DIR/$name/.pi-gl-mem/MEMORY.md"
}

# ============================================================
# 起動モード
# ============================================================
if [ -f "$CONFIG" ]; then
  echo "=== $TEAM_NAME を起動します ==="

  SESSION=$(jq -r '.session' "$CONFIG")
  TIMEOUT=$(jq -r '.timeout' "$CONFIG")
  WORKFLOW=$(jq -r '.workflow // ""' "$CONFIG")
  LOOP=$(jq -r '.loops[] | "\(.between[0])\u2194\(.between[1]): \u6700低\(.min)回、\u6700大\(.max)回まで\u7e70り返し"' "$CONFIG" 2>/dev/null | paste -sd " / ")
  mapfile -t AGENTS < <(jq -r '.agents[].name' "$CONFIG")
  mapfile -t ROLES  < <(jq -r '.agents[].role' "$CONFIG")

  FIRST_NAME="${AGENTS[0]}"

  # チームディレクトリが未作成なら生成
  if [ ! -d "$TEAM_DIR" ]; then
    echo "  → ディレクトリが見つかりません。設定から生成します"
    mkdir -p "$TEAM_DIR"

    PANE_MAP=""
    for i in "${!AGENTS[@]}"; do
      [ -n "$PANE_MAP" ] && PANE_MAP+=" / "
      PANE_MAP+="${AGENTS[$i]}=$i"
    done

    for i in "${!AGENTS[@]}"; do
      name="${AGENTS[$i]}"
      role="${ROLES[$i]}"
      mkdir -p "$TEAM_DIR/$name"
      cd "$TEAM_DIR/$name"

      if [ ! -d ".pi-gl-mem" ]; then
        echo y | bash "$INIT_SCRIPT" 2>/dev/null
      fi

      mapfile -t RULES < <(jq -r ".agents[$i].rules[]" "$CONFIG")
      SHORT="a$((i+1))"
      gen_memory "$name" "$role" "$SHORT" "${RULES[@]}"
      echo '{"injectGlobal": false}' > .pi-gl-mem/pi_gl_settings.json
      mkdir -p inbox outbox
      cd "$BASE_DIR"
      echo "  → $name 完了"
    done

    if ! grep -q ".pi-gl-mem/" "$TEAM_DIR/.gitignore" 2>/dev/null; then
      echo ".pi-gl-mem/" >> "$TEAM_DIR/.gitignore"
    fi

    echo "  → 生成完了"
  fi

  # この実行のタスクを投入（タイムスタンプ $TS で識別）
  TASK_FILE="$TEAM_DIR/$FIRST_NAME/inbox/${TS}_from-user_to-${FIRST_NAME}_タスク.md"
  jq -r '.task_template // "# タスク"' "$CONFIG" > "$TASK_FILE"

  tmux kill-session -t "$SESSION" 2>/dev/null || true
  mkdir -p "$TEAM_DIR/logs"

  # 1ペイン目
  tmux new-session -d -s "$SESSION" -c "$TEAM_DIR/${AGENTS[0]}" -n agents
  tmux pipe-pane -t "$SESSION:agents.0" -o "cat >> $TEAM_DIR/logs/${AGENTS[0]}.log"

  # 以降を縦分割
  for i in $(seq 1 $((${#AGENTS[@]} - 1))); do
    tmux split-window -v -c "$TEAM_DIR/${AGENTS[$i]}"
    tmux pipe-pane -t "$SESSION:agents.$i" -o "cat >> $TEAM_DIR/logs/${AGENTS[$i]}.log"
  done

  # editor に自動トリガー（毎回、最新のタスクを指定）
  FIRST="${AGENTS[0]}"
  tmux send-keys -t "$SESSION:agents.0" \
    "cd $TEAM_DIR/$FIRST && pi -p 'inbox/${TS}_from-user_to-${FIRST}_タスク.md を処理してください'" Enter
  echo "  → $FIRST に自動トリガーを送信しました (${TS})"

  # 外部ターミナルで開く
  if [ -n "$WT" ]; then
    "$WT" wsl tmux attach -t "$SESSION" &
    echo "  → Windows Terminal で開きました"
  elif which cmd.exe >/dev/null 2>&1; then
    cmd.exe /c start "tmux" wsl tmux attach -t "$SESSION"
    echo "  → 別窓で開きました"
  else
    tmux attach -t "$SESSION"
  fi

  echo ""
  echo "=== エージェントの動作ログ (Ctrl+C で終了) ==="
  FIRST_NAME="${AGENTS[0]}"

  # ANSIコードを除去して表示（ラインバッファ）
  tail -f "$TEAM_DIR/logs/"*.log 2>/dev/null | stdbuf -oL sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\r//g' &
  TAILPID=$!

  # 承認完了を検出（この実行より新しい承認ファイルを対象）
  for i in $(seq 1 30); do
    sleep 10
    # 本文の先頭行に完了マーカーがあるファイルを検出
    APPROVAL=
    while IFS= read -r _f; do
      head -1 "$_f" 2>/dev/null | grep -q "✅ ワークフロー完了" && { APPROVAL="$_f"; break; }
    done < <(find "$TEAM_DIR/$FIRST_NAME/inbox/" -type f -newer "$TASK_FILE" 2>/dev/null)
    # フォールバック: ファイル名に承認/合格を含む
    if [ -z "$APPROVAL" ]; then
      APPROVAL=$(find "$TEAM_DIR/$FIRST_NAME/inbox/" \( -name "*承認*" -o -name "*合格*" \) -newer "$TASK_FILE" 2>/dev/null | head -1)
    fi
    if [ -n "$APPROVAL" ]; then
      kill $TAILPID 2>/dev/null || true
      sleep 1
      echo ""
      echo "╔════════════════════════════════════════╗"
      echo "║      ✅ ワークフロー完了！            ║"
      echo "╚════════════════════════════════════════╝"
      echo "  完了ファイル: $(basename "$APPROVAL")"
      echo "  生成物: $(find "$TEAM_DIR" -maxdepth 2 -type f -newer "$TASK_FILE" ! -name "*.md" ! -path "*/.pi-gl-mem/*" 2>/dev/null | sed "s|$TEAM_DIR/||" | head -3 | tr '\n' ' ')"
      echo "  通信: $(find "$TEAM_DIR" \( -path "*/inbox/*" -o -path "*/outbox/*" \) -newer "$TASK_FILE" ! -name "*from-user*" 2>/dev/null | sed "s|$TEAM_DIR/||" | head -5 | tr '\n' ' ')"
      echo ""
      exit 0
    fi
  done

  kill $TAILPID 2>/dev/null || true
  echo ""
  echo "⏰ タイムアウト"
  exit 1
fi

# ============================================================
# 生成モード
# ============================================================
echo "=== $TEAM_NAME を生成します ==="

# エージェント名・役割を配列に
AGENT_NAMES=(); AGENT_ROLES=()
for entry in "${DEFAULT_AGENTS[@]}"; do
  AGENT_NAMES+=("${entry%%:*}")
  AGENT_ROLES+=("${entry#*:}")
done

# ペイン番号マップ生成
PANE_MAP=""
for i in "${!AGENT_NAMES[@]}"; do
  [ -n "$PANE_MAP" ] && PANE_MAP+=" / "
  PANE_MAP+="${AGENT_NAMES[$i]}=$i"
done

# ワークフロー生成（循環: (0)→(1)→...→(n)→(0)）
WORKFLOW=""
for i in "${!AGENT_NAMES[@]}"; do
  [ -n "$WORKFLOW" ] && WORKFLOW+="→"
  WORKFLOW+="${AGENT_NAMES[$i]}($i)"
done
WORKFLOW+="→${AGENT_NAMES[0]}(0)"

# JSON設定ファイル（Pythonで生成）
LOOP_TEXT="agent3_reviewer↔agent2_writer: 最低1回、最大3回まで繰り返し"
python3 << PYEOF > "$CONFIG"
import json

session = "writing-team"
timeout = 180
workflow = """$WORKFLOW"""
pane_map = """$PANE_MAP"""
loop_text = """$LOOP_TEXT"""

agent_defs = [
    ("${AGENT_NAMES[0]}", """${AGENT_ROLES[0]}"""),
    ("${AGENT_NAMES[1]}", """${AGENT_ROLES[1]}"""),
    ("${AGENT_NAMES[2]}", """${AGENT_ROLES[2]}"""),
]

agents = []
for i, (name, role) in enumerate(agent_defs):
    is_final = (i == 0)
    rules = [
        "inbox/ にファイルが来たら読んで着手",
        f"完了後: 自分の outbox/ と相手の inbox/ にファイル作成。ファイル名: {{TS}}_{{short}}_to-{{相手}}_件名.md。パス: ../{{相手}}/inbox/",
        f"通知: tmux send-keys -t {session}:agents.{{相手ペイン}} \"timeout {timeout} pi -p 'inbox/{{ファイル名}} を処理'\" Enter。ペイン番号: {pane_map}",
        f"ワークフロー: {workflow}",
    ]
    if loop_text:
        rules.append(f"ループポリシー: {loop_text}")
    if is_final:
        rules.append('【厳守】ワークフロー完了時（自分が最終承認者）: 応答の先頭行に "=== ✅ ワークフロー完了 ===" のみを出力せよ。「以上で完了しました」などの言い換えは一切禁止。これが守れないとワークフローが正常終了できない。完了報告は2行目以降に書け')
    rules.append("ユーザーはtmux外。連絡はinbox/へのファイル作成")
    rules.append("ログ: write_local_memory target=daily")
    agents.append({"name": name, "role": role, "rules": rules})

config = {
    "session": session,
    "timeout": timeout,
    "workflow": workflow,
    "loops": [
        {"between": ["agent3_reviewer", "agent2_writer"], "min": 1, "max": 3}
    ],
    "task_template": "# タスク\n\nCLI ツール greet を作成してください。\n\n仕様:\n- ファイル名: greet\n- 引数なし: \"Hello, World!\" と出力\n- 引数あり: \"Hello, <名前>!\" と出力\n- Bash スクリプト、実行権限付与\n\n役割に従い writer・reviewer と連携して進めてください。",
    "agents": agents
}

print(json.dumps(config, ensure_ascii=False, indent=2))
PYEOF
echo "  → $TEAM_NAME.json 作成"
echo ""
echo "=== $TEAM_NAME.json 作成完了 ==="
echo ""

# 生成後、RUNモードで起動（ディレクトリ・MEMORY.mdはRUNモード側で作る）
exec bash "$0" "$TEAM_NAME"
