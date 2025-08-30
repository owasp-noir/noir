+++
title = "概要"
description = "OWASP Noirとは何か、どのように動作し、その目標は何かを学びます。このページでは、プロジェクトとその主要機能の高レベルな紹介を提供します。"
weight = 1
sort_by = "weight"

[extra]
+++

OWASP Noirは、セキュリティ専門家と開発者がアプリケーションのアタックサーフェスを特定するのに役立つオープンソースツールです。ソースコードに対して静的解析を実行することで、Noirは攻撃者によってターゲットにされる可能性のあるAPIエンドポイント、Webページ、その他の潜在的なエントリーポイントを発見できます。

これにより、ホワイトボックスセキュリティテストや堅牢なセキュリティパイプラインの構築にとって非常に貴重なツールとなります。

[GitHub](https://github.com/owasp-noir/noir) | [OWASPプロジェクトページ](https://owasp.org/www-project-noir)

![noir-usage](./noir-usage.jpg)

## 動作原理

Noirは[Crystal](https://crystal-lang.org)プログラミング言語で構築され、コードを分析するために連携して動作するいくつかの主要コンポーネントで構成されています：

*   **検出器（Detectors）**：コードベースで使用されている技術を特定します。
*   **分析器（Analyzers）**：コードを解析してエンドポイント、パラメータ、その他の興味深い情報を見つけます。
*   **パッシブスキャナー & タガー**：ルールを使用して潜在的な脆弱性を特定し、発見にコンテキストタグを追加します。
*   **配信（Deliver）**：さらなる分析のために結果を他のツールに送信します。
*   **出力ビルダー**：様々な形式でレポートを生成します。

{% mermaid() %}
flowchart LR
    SourceCode:::highlight --> Detectors

    subgraph Detectors
        direction LR
        Detector1 & Detector2 & Detector3 --> |Condition| PassiveScan
    end

    PassiveScan --> |Results| BaseOptimizer

    Detectors --> |Techs| Analyzers

    subgraph Analyzers
        direction LR
        CodeAnalyzers & FileAnalyzer & LLMAnalyzer
        CodeAnalyzers --> |Condition| Minilexer
        CodeAnalyzers --> |Condition| Miniparser
    end
   subgraph Optimizer
       direction LR
       BaseOptimizer[Optimizer] --> LLMOptimizer[LLM Optimizer]
       LLMOptimizer[LLM Optimizer] --> OptimizedResult
       OptimizedResult[Result]
   end

    Analyzers --> |Condition| Deliver
    Analyzers --> |Condition| Tagger
    Deliver --> 3rdParty
    BaseOptimizer --> OptimizedResult
    OptimizedResult --> OutputBuilder
    Tagger --> |Tags| BaseOptimizer
    Analyzers --> |Endpoints| BaseOptimizer
    OutputBuilder --> Report:::highlight

    classDef highlight fill:#000,stroke:#333,stroke-width:4px;
{% end %}

## プロジェクトの目標

Noirの主要な目標は、静的コード分析と動的セキュリティテストの間のギャップを埋めることです。アプリケーションのエンドポイントの包括的で正確なリストを提供することで、NoirはDASTツールがより徹底的で効果的なスキャンを実行できるようにします。

将来的には、より多くの言語とフレームワークのサポートを拡張し、分析の精度を向上させ、AIとLLMをさらに活用して能力を強化する予定です。

## 貢献

OWASP Noirは、コミュニティの貢献によって繁栄するオープンソースプロジェクトです。ツールの改善に興味がある場合は、[コントリビューションガイド](https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md)をご覧ください。誤字の修正から主要な新機能の追加まで、あらゆる規模の貢献を歓迎します。

### 貢献者

Noirに貢献してくださったすべての皆様に感謝いたします！♥️

![](https://raw.githubusercontent.com/owasp-noir/noir/refs/heads/main/CONTRIBUTORS.svg)

## 行動規範

私たちは、歓迎的で包括的なコミュニティの育成に取り組んでいます。GitHubリポジトリの[行動規範](https://github.com/owasp-noir/noir/blob/main/CODE_OF_CONDUCT.md)をご確認ください。

## ヘルプとフィードバック

ご質問、ご提案、問題がございましたら、GitHubの[ディスカッション](https://github.com/orgs/owasp-noir/discussions)や[イシュー](https://github.com/owasp-noir/noir/issues)ページでお気軽にお声がけください。