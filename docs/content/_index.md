+++
template = "landing.html"

[extra]
version = "v0.28.0"

[extra.hero]
title = " "
badge = "v0.28.0"
description = "Hunt every Endpoint in your code, expose Shadow APIs, map the Attack Surface."
image = "./images/noir-wallpaper.jpg"
cta_buttons = [
    { text = "Get Started", url = "./get_started/overview", style = "primary" },
    { text = "View on GitHub", url = "https://github.com/owasp-noir/noir", style = "secondary" },
]

[extra.features_section]
title = "Essential Features"
description = "Discover Noir's essential features for comprehensive attack surface detection and analysis."

[[extra.features]]
title = "Attack Surface Discovery"
desc = "Analyzes your source code to uncover the complete attack surface of your application, including hidden endpoints, shadow APIs, and other security blind spots."
icon = "fa-solid fa-code"

[[extra.features]]
title = "Multi-Language Support"
desc = "Supports a wide range of programming languages and frameworks, ensuring broad compatibility across your diverse portfolio of projects."
icon = "fa-solid fa-globe"

[[extra.features]]
title = "DevSecOps Ready"
desc = "Designed for seamless integration into CI/CD pipelines and security workflows, with support for popular tools like cURL, ZAP, Caido, and more."
icon = "fa-solid fa-gears"

[[extra.features]]
title = "AI-Powered Analysis"
desc = "Leverages Large Language Models (LLMs) to detect endpoints in any language or framework—even those not natively supported—ensuring no endpoint goes undetected."
icon = "fa-solid fa-robot"

[[extra.features]]
title = "SAST-to-DAST Bridge"
desc = "Bridges static code analysis and dynamic testing by providing discovered endpoints to DAST tools like ZAP and Burp Suite, enabling more comprehensive security scans."
icon = "fa-solid fa-bridge"

[[extra.features]]
title = "Flexible Output Formats"
desc = "Generates clear and actionable results in a variety of formats, including JSON, YAML, and OpenAPI, making it easy to consume the data in other tools."
icon = "fa-solid fa-file-export"

[extra.trust_section]
title = "Built With"
logos = [
    { src = "./resources/owasp.png", alt = "OWASP" },
    { src = "./resources/crystal.png", alt = "Crystal" },
]

[extra.final_cta_section]
title = "Open Source Project"
description = "OWASP Noir is an open-source project built with ❤️ by the community. If you would like to contribute, please see our contributing guide and submit a pull request with your awesome changes!"
button = { text = "View Contributing Guide", url = "https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md" }
image = "https://github.com/owasp-noir/noir/raw/main/docs/static/CONTRIBUTORS.svg"
+++
