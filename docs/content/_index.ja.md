+++
template = "landing.html"

[extra]
version = "v0.23.1"

[extra.hero]
title = "NOIR"
description = "Noirは、ホワイトボックスセキュリティテストを強化し、静的解析によってエンドポイントと潜在的な脆弱性を発見することで、セキュリティパイプラインを合理化するアタックサーフェス検出器です。"
image = "./images/noir-wallpaper.jpg"
cta_buttons = [
    { text = "スタートガイド", url = "./get_started/overview", style = "primary" },
    { text = "GitHubで見る", url = "https://github.com/owasp-noir/noir", style = "secondary" },
]

[[extra.features]]
title = "エンドポイント検出"
desc = "ソースコードから直接APIやWebエンドポイント、およびそのパラメータを抽出し、アプリケーションのアタックサーフェスを包括的に分析します。"
icon = "fa-solid fa-code"

[[extra.features]]
title = "多言語サポート"
desc = "幅広いプログラミング言語とフレームワークをサポートし、多様なプロジェクトポートフォリオ全体で広範な互換性を確保します。"
icon = "fa-solid fa-globe"

[[extra.features]]
title = "脆弱性検出"
desc = "ルールベースのパッシブスキャンを実行して潜在的なセキュリティ脆弱性を特定し、迅速な修復を支援する詳細なインサイトを提供します。"
icon = "fa-solid fa-shield-halved"

[[extra.features]]
title = "DevOps統合"
desc = "cURL、ZAP、Caidoなどの人気のDevOpsおよびセキュリティツールとシームレスに統合し、既存のセキュリティパイプラインを強化します。"
icon = "fa-solid fa-gears"

[[extra.features]]
title = "柔軟な出力形式"
desc = "JSON、YAML、OpenAPIなど様々な形式で明確で実用的な結果を生成し、他のツールでのデータ利用を容易にします。"
icon = "fa-solid fa-file-export"

[[extra.features]]
title = "AI搭載分析"
desc = "AIと大規模言語モデル（LLM）の力を活用して、馴染みのないまたはサポートされていないフレームワークで隠されたAPIとエンドポイントを発見します。"
icon = "fa-solid fa-robot"

[extra.trust_section]
title = "Built With"
logos = [
    { src = "./resoruces/owasp.png", alt = "OWASP" },
    { src = "./resoruces/crystal.png", alt = "Crystal" },
]

[extra.final_cta_section]
title = "オープンソースプロジェクト"
description = "OWASP Noirは、コミュニティによって❤️で構築されたオープンソースプロジェクトです。貢献をご希望の場合は、コントリビューションガイドをご覧いただき、素晴らしい変更を含むプルリクエストを提出してください！"
button = { text = "コントリビューションガイドを見る", url = "https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md" }
image = "https://github.com/owasp-noir/noir/raw/main/CONTRIBUTORS.svg"
+++