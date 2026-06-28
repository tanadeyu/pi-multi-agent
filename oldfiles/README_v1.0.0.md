# pi-multi-agent v1.0.0

> **pi + tmux + pi-gl-mem** による最小構成のマルチエージェント連携システム
> 3つの AI エージェント（編集者・ライター・レビュアー）が協調してワークフローを実行する

---

## 概要

`pi-team-run.sh`（257行の単一スクリプト）と `team_a.json`（JSON設定）だけで構成された、シンプルかつ自己完結型のマルチエージェントシステムです。

各エージェントは `pi -p`（非対話モード）で起動し、処理後に自動終了。tmux の `send-keys` で次エージェントを即時呼び出し、inbox/outbox のファイルを介して連携します。

### 動作確認済み

- ✅ 3エージェントのワークフロー連鎖（editor → writer → reviewer → editor）
- ✅ `pi -p` 非対話モードでの完全自動実行
- ✅ tmux send-keys によるリアルタイム通知
- ✅ 完了検出（✅ マーカー / ファイル名フォールバック）
- ✅ 差し戻しループ（reviewer ↔ writer）

---

## ディレクトリ構成

```
pi-multi-agent/
├── pi-team-run.sh          # 単一エントリポイント（生成＋起動、257行）
├── team_a.json             # チーム設定（JSON、自己完結型）
├── teams/team_a/           # チームデータディレクトリ
│   ├── agent1_editor/      # 編集者（ディレクター）
│   │   ├── inbox/          # 受信ファイル
│   │   ├── outbox/         # 送信記録
│   │   └── .pi-gl-mem/     # 長期記憶・日次ログ
│   ├── agent2_writer/      # ライター（実装者）
│   │   ├── inbox/
│   │   ├── outbox/
│   │   └── .pi-gl-mem/
│   ├── agent3_reviewer/    # レビュアー
│   │   ├── inbox/
│   │   ├── outbox/
│   │   └── .pi-gl-mem/
│   └── logs/               # tmux pipe-pane ログ
├── README.md               # 本ファイル
├── 仕様書.md               # 詳細設計書
├── テスト結果1.md          # 動作確認レポート
└── .gitignore
    └── .pi-gl-mem/
```

---

## クイックスタート

```bash
# 初回実行（JSON生成 → チーム作成 → 起動）
bash pi-team-run.sh team_a

# 2回目以降（新しいタスクを投入して再実行）
bash pi-team-run.sh team_a

# 別チームを作る場合
bash pi-team-run.sh team_b
```

### 動作の流れ

1. `team_a.json` がなければ自動生成（CREATE モード）→ RUN モードに移行
2. `teams/team_a/` がなければ各エージェントのディレクトリ＋MEMORY.md を生成
3. タスクファイルを編集者の inbox に投入（タイムスタンプ付き）
4. tmux 3ペイン（縦分割）を作成
5. 編集者に自動トリガーを送信 → ワークフロー開始
6. ログを表示しながら完了検出（最大5分ポーリング）

---

## ワークフロー

```
ユーザー
  │
  ▼ (タスクファイル)
agent1_editor (ペイン0) ──指示──→ agent2_writer (ペイン1)
  ▲                              │
  │                              ▼  (レビュー依頼)
  │                          agent3_reviewer (ペイン2)
  │                              │
  └──── 承認報告 ────────────────┘
         ↻ 差し戻しループ（最小1回、最大3回）
```

---

## エージェントの役割

| エージェント | 略称 | ペイン | 役割 | ルール数 |
|------------|------|--------|------|---------|
| `agent1_editor` | a1 | 0 | タスク分解・指示・最終承認 | 8 |
| `agent2_writer` | a2 | 1 | 実装・レビュー提出 | 7 |
| `agent3_reviewer` | a3 | 2 | レビュー・合格/差し戻し | 7 |

各エージェントは `.pi-gl-mem/MEMORY.md` に役割とルールを持ち、pi-gl-mem により自動ロードされます。

---

## カスタマイズ

### タスク内容を変える

```bash
jq '.task_template = "新しいタスク内容"' team_a.json > tmp && mv tmp team_a.json
```

### エージェントの役割を変える

`pi-team-run.sh` 内の `DEFAULT_AGENTS` 配列を編集し、`team_a.json` を削除して再実行。

### タイムアウト・セッション名

`team_a.json` の `timeout` `session` を直接編集。

### 別チーム

`team_a.json` を `team_b.json` にコピーし、`session` 名を変更。

---

## 依存関係

| コマンド | 用途 | 必須 |
|---------|------|------|
| `pi` | AI エージェント | ✅ |
| `tmux` | ペイン管理・通知 | ✅ |
| `jq` | JSON パース | ✅ |
| `python3` | JSON 生成（初回のみ） | ✅ |
| `wt.exe` | Windows Terminal 別窓 | WSL のみ任意 |
| `stdbuf` | ログラインバッファ | GNU coreutils |

---

## 設計思想

| 原則 | 説明 |
|------|------|
| **最小構成** | スクリプト1個(257行) + JSON設定1個、依存最小限 |
| **自己完結** | JSON に全ルール。スクリプトにルールロジックは持たない |
| **非永続プロセス** | 全エージェント `pi -p`（処理後終了） |
| **ファイルベース通信** | inbox/outbox の Markdown。シンプルで追跡容易 |
| **タイムスタンプ識別** | 全ファイルに実行 TS。履歴と現実行を区別 |
| **学習継続** | `.pi-gl-mem/` は保持。再実行時に過去の記憶を参照 |

---

## ライセンス

MIT
