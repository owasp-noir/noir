+++
template = "landing.html"

[extra]
version = "v0.22.0"

[extra.hero]
title = "NOIR"
description = "Noir is an attack surface detector that enhances white-box security testing and streamlines security pipelines by discovering endpoints and potential vulnerabilities through static analysis."
image = "/images/noir-wallpaper.jpg"
cta_buttons = [
    { text = "Get Started", url = "/get_started/overview", style = "primary" },
    { text = "View on GitHub", url = "https://github.com/owasp-noir/noir", style = "secondary" },
]

[[extra.features]]
title = "Endpoint Discovery"
desc = "Extracts API and web endpoints, along with their parameters, directly from your source code for a comprehensive analysis of your application's attack surface."
icon = "fa-solid fa-code"

[[extra.features]]
title = "Multi-Language Support"
desc = "Supports a wide range of programming languages and frameworks, ensuring broad compatibility across your diverse portfolio of projects."
icon = "fa-solid fa-globe"

[[extra.features]]
title = "Vulnerability Detection"
desc = "Performs rule-based passive scanning to identify potential security vulnerabilities and provides detailed insights to help you remediate them quickly."
icon = "fa-solid fa-shield-halved"

[[extra.features]]
title = "DevOps Integration"
desc = "Seamlessly integrates with popular DevOps and security tools like cURL, ZAP, and Caido to enhance your existing security pipelines."
icon = "fa-solid fa-gears"

[[extra.features]]
title = "Flexible Output Formats"
desc = "Generates clear and actionable results in a variety of formats, including JSON, YAML, and OpenAPI, making it easy to consume the data in other tools."
icon = "fa-solid fa-file-export"

[[extra.features]]
title = "AI-Powered Analysis"
desc = "Leverages the power of AI and Large Language Models (LLMs) to uncover hidden APIs and endpoints in unfamiliar or unsupported frameworks."
icon = "fa-solid fa-robot"

[extra.trust_section]
title = "Our Tech Stack"
logos = [
    { src = "./resoruces/owasp.png", alt = "OWASP" },
    { src = "./resoruces/crystal.png", alt = "Crystal" },
]

[extra.social_proof_section]
title = "What Our Users Say"
testimonials = [
    { author = "KSG", role = "Security Developer", quote = "Noir provides practical features like multi-language support and search out of the box, without needing extra tools.", avatar = "/images/ksg.jpg" },
    { author = "Lina", role = "Security Engineer", quote = "It's so simple and fast, and the beautiful theme is a joy to work with. I'm ready to find my inner calm with this tool!", avatar = "/images/lina.jpg" },
    { author = "Bori Bae", role = "Security Engineer", quote = "The theme is clean and the settings are intuitive, making it easy for even first-time users to get started.", avatar = "/images/bori.png" },
]

[extra.final_cta_section]
title = "Contributing to Noir"
description = "OWASP Noir is an open-source project built with ❤️ by the community. If you would like to contribute, please see our contributing guide and submit a pull request with your awesome changes!"
button = { text = "View Contributing Guide", url = "https://github.com/owasp-noir/noir/blob/main/CONTRIBUTING.md" }
+++
