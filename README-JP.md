# agy-cli-sync

使い捨て環境（Dev Container など）と中央サーバー間で、`antigravity-CLI`（agy）の設定ファイルおよび会話履歴を双方向同期するためのプロジェクトです。

このリポジトリに含まれるスクリプトを利用することで、コンテナを再作成しても過去の会話履歴（brain）を保持でき、継続して `agy` を利用できます。

---

# 🛡️ 安全な同期メカニズム（SQLite DB 破損防止）

`antigravity-CLI`（`agy`）は会話履歴の保存に SQLite データベース（WAL モード）を使用しています。`agy` が会話を保存・更新中に背景で `rsync` 同期が介入すると、WAL ファイルとの不整合が発生して DB が破損し、CLI がハングアップする原因となります。

`agy-cli-sync` では、**プロセス監視型の同期スキップ機構**により、この問題を完全に回避しています：

1. **`agy` プロセス起動中の自動ポーズ**:
   - 常時同期サービスが背景で `agy` プロセスの起動状態を常時監視します。
   - `agy` プロセスが起動している間は、`rsync` 同期を一切行わずスキップ（一時停止）します。
2. **会話終了直後の自動確定同期**:
   - `agy` プロセスの終了（会話完了）を検出した直後に、1 回即時同期（Push & Pull）を実行し、会話履歴を確実にサーバーへ保存します。
   - その後、通常（2秒おき）の常時同期状態へと自動復帰します。
3. **完全な非侵襲（バイナリ・設定の変更なし）**:
   - ユーザーの `agy` バイナリや環境設定・エイリアス等には一切手を加えません。ユーザーは普段通り `agy` コマンドを実行するだけです。

---

# 0. 準備：同期用 SSH キーを作成する

サーバーとコンテナ間で安全にデータを同期するため、専用の SSH キーペアを作成します。

ホストマシン（WSL、Ubuntu など）のターミナルで以下を実行してください。
※パスフレーズは空のままで構いません。

```bash
ssh-keygen -t ed25519 -f ~/.ssh/agy_key -N ""
```

以下の2つのファイルが作成されます。

* 秘密鍵：`~/.ssh/agy_key`
* 公開鍵：`~/.ssh/agy_key.pub`

続いて公開鍵の内容を表示し、コピーしておきます。

```bash
cat ~/.ssh/agy_key.pub

# 出力例
# ssh-ed25519 AAAAC3Nza...（環境ごとに異なります）
```

---

# 1. サーバー側のセットアップ

サーバー（`10.10.10.51`）上に、会話データを保存するための SSH サーバーコンテナを構築します。

このリポジトリに含まれている `docker-compose.yml` をサーバーへ配置してください。

**起動前に、`PUBLIC_KEY` の値を「手順0でコピーした公開鍵」に置き換えてください。**

修正後、以下を実行してコンテナを起動します。

※起動時に `agysync` ユーザーが自動作成され、公開鍵認証が設定されます。

```bash
docker-compose up -d
```

---

# 2. クライアント側の準備（ホスト / Dev Container）

コンテナ内やホストから `agy` を利用するため、`client/` ディレクトリ内のスクリプト群および必要な認証情報を共有ディレクトリ（例：プロジェクト内の `.local/` や任意の配置場所）へコピーします。

### 📦 スクリプト一覧 (`client/` 配下)

| ファイル名 | 役割 | 実行方法 |
| :--- | :--- | :--- |
| **`setup-agy-init.sh`** | 初回初期化スクリプト (`rsync`確認・初回Pull・常駐起動) | **初回に 1 回だけ手動実行** |
| **`setup-agy-start.sh`** | 2回目以降の同期開始スクリプト (プロセス監視付き常駐同期ループ) | 再起動時に自動/手動実行 (または systemd が呼び出し) |
| **`agy-sync.service`** | ホスト環境用の systemd ユーザーサービス定義ファイル | `systemctl` で登録 |

---

# 3. コンテナ / ホストでのセットアップと常駐化

### A. Dev Container 環境でのセットアップ
Dev Container 内へ接続後、用途に合わせて以下を実行してください。

```bash
# 新規コンテナ作成直後 (初回初期化)
bash /path/to/setup-agy-init.sh

# 既存コンテナ再起動時
bash /path/to/setup-agy-start.sh
```

---

### B. ホスト (WSL Ubuntu) での常時常駐化設定（systemd ユーザーサービス）

ホストの Ubuntu 起動時に自動で安全な同期常駐を行う場合、付属の `agy-sync.service` を配置します。

```bash
# 1. サービスファイルの作成・配置 (クライアント側の配置場所からコピー)
mkdir -p ~/.config/systemd/user/
cp /path/to/client/agy-sync.service ~/.config/systemd/user/

# 2. 初回セットアップ (rsync確認・初回Pull)
bash /path/to/client/setup-agy-init.sh

# 3. systemd ユーザーサービスの有効化と起動
systemctl --user daemon-reload
systemctl --user enable --now agy-sync.service
```

---

# 💡 動作確認

セットアップ完了後は、以下のコマンドで正常に動作しているか確認できます。

```bash
# バックグラウンドで同期ループが動作しているか確認
ps aux | grep setup-agy-start.sh

# systemd ユーザーサービスのステータス確認 (ホスト側)
systemctl --user status agy-sync.service
```
