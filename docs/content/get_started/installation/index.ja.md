+++
title = "インストール"
description = "システムにOWASP Noirをインストールする方法を学びます。このガイドでは、Homebrew、Snapcraft、Docker、またはソースからのビルドを使用してNoirをインストールする手順を提供します。"
weight = 2
sort_by = "weight"

[extra]
+++

OWASP Noirをインストールする方法はいくつかあるので、お使いのオペレーティングシステムとワークフローに最も適した方法を選択できます。

## Homebrew（macOSおよびLinux）

macOSまたはLinuxをお使いの場合、Noirをインストールする最も簡単な方法は[Homebrew](https://brew.sh/)を使用することです。

```bash
brew install noir
```

{% alert_info() %}
Homebrewユーザーの場合、Zsh、Bash、Fishのシェル補完が自動的にインストールされるので、すぐに使い始めることができます。
{% end %}

## Snapcraft（Linux）

[Snap](https://snapcraft.io/)をサポートするLinuxディストリビューションをお使いの場合、Snap StoreからNoirをインストールできます。

```bash
sudo snap install noir
```

## Docker

Dockerの使用を好む場合は、GitHub Container Registry（GHCR）から公式のNoirイメージをプルできます。

```bash
docker pull ghcr.io/owasp-noir/noir:latest
```

利用可能なすべてのタグのリストは、[GitHub Packagesページ](https://github.com/owasp-noir/noir/pkgs/container/noir)で見つけることができます。

## ソースからのビルド

{% alert_warning() %}
Noirをソースからビルドしたい場合は、Crystalプログラミング言語をインストールしている必要があります。
{% end %}

1.  **リポジトリをクローン**：

    ```bash
    git clone https://github.com/owasp-noir/noir
    cd noir
    ```

2.  **依存関係をインストール**：

    ```bash
    shards install
    ```

3.  **プロジェクトをビルド**：

    ```bash
    shards build --release --no-debug
    ```

    コンパイルされたバイナリは`./bin/noir`に配置されます。

## インストールの確認

Noirをインストールしたら、以下を実行して正しく動作していることを確認できます：

```bash
noir --version
```

これにより、インストールされているNoirのバージョンが表示されます。