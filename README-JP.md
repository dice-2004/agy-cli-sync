# agy-cli-sync

使い捨て環境（Dev Container など）と中央サーバー間で、`antigravity-CLI`（agy）の設定ファイルおよび会話履歴を双方向同期するためのプロジェクトです。

このリポジトリに含まれるスクリプトを利用することで、コンテナを再作成しても過去の会話履歴（brain）を保持でき、継続して `agy` を利用できます。

> **前提環境**
>
> 誰でも同じ環境を再現できるよう、このドキュメントでは同期サーバーの IP アドレスを `10.10.10.51`、SSH ポートを `2222` としています。実際の環境に合わせて適宜変更してください。

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

# 2. クライアント側の準備（ホスト：WSL / Ubuntu など）

コンテナ内から `agy` を利用するため、ホスト側のユーザー固有ファイルと、手順0で作成した秘密鍵を、コンテナから参照できる共有ディレクトリ（例：プロジェクト内の `.local/`）へコピーします。

以下は一例です。環境に合わせてパスを変更してください。

```bash
# 1. 共有ディレクトリを作成
mkdir -p /path/to/project/.local/.gemini

# 2. agy 実行ファイルをコピー
cp ~/.local/bin/agy /path/to/project/.local/agy

# 3. ログイン状態（認証キャッシュ）をコピー
cp -r ~/.gemini/antigravity-cli /path/to/project/.local/.gemini/

# 4. 手順0で作成した秘密鍵をコピー
cp ~/.ssh/agy_key /path/to/project/.local/agy_key
```

> **補足**
>
> このリポジトリに含まれるセットアップスクリプト（`setup-agy-init.sh`、`setup-agy-start.sh`）も、コンテナ内から参照できる場所へ配置してください。

---

# 3. コンテナのセットアップと同期開始

Dev Container などのコンテナへ接続したら、このリポジトリに含まれるセットアップスクリプトを実行して同期を開始します。

利用状況に応じて、以下のどちらかを実行してください。

## A. コンテナを新規作成した直後

このスクリプトでは以下を自動で実施します。

* agy 本体と認証情報のシンボリックリンク作成
* `rsync` のインストール
* 初回同期（サーバーから取得）
* バックグラウンドで継続同期を開始（2秒ごと）

```bash
bash /path/to/setup-agy-init.sh
```

---

## B. 既存コンテナを再起動した場合

すでに `rsync` がインストール済みであることを前提としています。

シンボリックリンクを確認し、バックグラウンド同期のみを開始します。

```bash
bash /path/to/setup-agy-start.sh
```

---

# システム構成

```mermaid
flowchart LR
    subgraph ClientA["パターンA：Dev Container 構成"]
        direction TB
        subgraph Host["ホストマシン（WSL / Ubuntu）"]
            OriginalAgy["agy本体 / 認証情報\nSSH秘密鍵"]
        end

        subgraph DevContainer["使い捨て環境（Dev Container）"]
            SharedDir["共有ディレクトリ\n(scratch)"]
            AgyCmdA["agy コマンド"]
            SyncScriptA["バックグラウンド同期\n(rsyncループ)"]

            SharedDir -. シンボリックリンク .-> AgyCmdA
            SharedDir -. 秘密鍵を利用 .-> SyncScriptA
        end

        OriginalAgy == "① 事前コピー" ===> SharedDir
    end

    subgraph ClientB["パターンB：通常ホスト（複数端末）"]
        direction TB
        HostB["別ホスト（ノートPCなど）"]
        AgyCmdB["agy コマンド"]
        SyncScriptB["バックグラウンド同期\n(rsyncループなど)"]

        HostB --- AgyCmdB
        HostB -. 秘密鍵を利用 .-> SyncScriptB
    end

    subgraph CentralServer["中央同期サーバー（10.10.10.51）"]
        direction TB
        SSHD["SSHサーバー\n(port:2222)"]
        BrainData[/"会話履歴\n(brain)"/]
        SSHD --- BrainData
    end

    SyncScriptA <== "② 双方向同期" ===> SSHD
    SyncScriptB <== "双方向同期" ===> SSHD
```

---

# 💡 動作確認

セットアップ完了後は、以下のコマンドで正常に動作しているか確認できます。

```bash
# agy コマンドが利用可能か確認
agy --version

# バックグラウンドで rsync が動作しているか確認
ps aux | grep rsync
```

これらが正常に動作していれば、コンテナを再作成しても設定ファイルや会話履歴（brain）が中央サーバーと継続的に双方向同期されるようになります。
