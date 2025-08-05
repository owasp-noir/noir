+++
template = "landing.html"

[extra]
version = "v0.1.0"

[extra.hero]
title = "Noir"
description = "OWASP Noir empowers security teams with advanced attack surface detection, uncovering endpoints and vulnerabilities through static analysis."
image = "/images/noir-wallpaper.jpg"
cta_buttons = [
    { text = "Get Started", url = "/get_started/overview", style = "primary" },
    { text = "View on GitHub", url = "https://github.com/owasp-noir/noir", style = "secondary" },
]

[[extra.features]]
title = "Endpoint Extraction"
desc = "Extract API and web endpoints along with parameters directly from source code for comprehensive security analysis."
icon = "fa-solid fa-code"

[[extra.features]]
title = "Multi-Language Support"
desc = "Supports multiple programming languages and frameworks, ensuring broad compatibility for diverse projects."
icon = "fa-solid fa-globe"

[[extra.features]]
title = "Security Issue Detection"
desc = "Perform rule-based passive scanning to identify potential security vulnerabilities with detailed insights."
icon = "fa-solid fa-shield-halved"

[[extra.features]]
title = "DevOps Integration"
desc = "Seamlessly integrate with DevOps tools like curl, ZAP, and Caido to enhance security pipelines."
icon = "fa-solid fa-gears"

[[extra.features]]
title = "Flexible Output Formats"
desc = "Generate clear, actionable results in JSON, YAML, and OAS formats for easy consumption."
icon = "fa-solid fa-file-export"

[[extra.features]]
title = "AI-Enhanced Discovery"
desc = "Leverage AI to uncover hidden APIs and endpoints in unfamiliar frameworks."
icon = "fa-solid fa-robot"

[extra.trust_section]
title = "Tech Stack"
logos = [
    { src = "/resources/owasp.svg", alt = "OWASP" },
    { src = "/resources/crystal.svg", alt = "Crystal" },
]

[extra.social_proof_section]
title = "What Our Users Say"
testimonials = [
    { author = "KSG", role = "Security Developer", quote = "Without extra tools, it includes practical features like search, multilingual support, and comments out of the box", avatar = "/resources/ksg.jpg" },
    { author = "Lina", role = "Security Engineer", quote = "It's so simple and fast, yet I can apply an incredibly beautiful theme, which I absolutely love! I'm ready to embark on a journey to find the calm in my heart with this theme!", avatar = "/resources/lina.jpg" },
    { author = "Bori Bae", role = "Security Engineer", quote = "The theme is clean and the settings are intuitive, so even first-time users can easily use it!", avatar = "/resources/bori.png" },
]

[extra.final_cta_section]
title = "Contributing"
description = "OWASP Noir is an open-source project made with ❤️. If you want to contribute, please see CONTRIBUTING.md and submit a pull request with your awesome content!"
button = { text = "View Contributing Guide", url = "https://github.com/hahwul/goyo/blob/main/CONTRIBUTING.md" }
+++
