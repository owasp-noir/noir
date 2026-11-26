+++
title = "FAQ"
description = "Common questions about OWASP Noir."
weight = 3
sort_by = "weight"
schema_type = "FAQ"
faq_questions = [
  "What is OWASP Noir?",
  "How do I install Noir?",
  "What languages and frameworks does Noir support?",
  "How can I contribute to Noir?",
  "Is Noir free?",
  "How do I integrate with other security tools?",
  "How do I export results?",
  "Does Noir send my code anywhere?",
  "How do I report bugs or request features?"
]
faq_answers = [
  "An open-source static analysis tool that discovers API endpoints, web pages, and other attack surface entry points from source code.",
  "Via Homebrew, Snapcraft, Docker, and more. See the Installation page.",
  "See the full list on the Supported Languages and Frameworks page.",
  "Read the Contributing Guide to get started.",
  "Yes, Noir is free and open-source under the MIT license. You can use it freely for commercial purposes.",
  "You can integrate with ZAP, Burp Suite, Caido, and more. See the Pipeline for DAST guide.",
  "Noir exports JSON, YAML, OpenAPI Specification, cURL, and many other formats. See the Output Formats section.",
  "No. A plain noir scan makes no network requests. Only options you add do: --ai-provider sends source code to the LLM provider, -P downloads rules with git, --probe sends requests to your target, and the --export options send the list of endpoints found.",
  "Open a GitHub Issue to report bugs or request features."
]

+++

{% mascot(mood="question") %}
Got a question that isn't here? Open a discussion and I'll add it.
{% end %}

### What is OWASP Noir?

An open-source static analysis tool that discovers API endpoints, web pages, and other attack surface entry points from source code.

### How do I install Noir?

Via Homebrew, Snapcraft, Docker, and more. See the [Installation](@/get_started/installation/index.md) page.

### What languages and frameworks does Noir support?

See the full list on the [Supported Languages and Frameworks](@/usage/supported/language_and_frameworks/index.md) page.

### How can I contribute to Noir?

Read the [Contributing Guide](https://github.com/owasp-noir/noir/blob/main/.github/CONTRIBUTING.md) to get started.

### Is Noir free?

Yes, Noir is free and open-source under the MIT license. You can use it freely for commercial purposes.

### How do I integrate with other security tools?

You can integrate with ZAP, Burp Suite, Caido, and more. See the [Pipeline for DAST](@/usage/more_features/pipeline-for-dast/index.md) guide.

### How do I export results?

Noir exports JSON, YAML, OpenAPI Specification, cURL, and many other formats. See the [Output Formats](@/usage/output_formats/_index.md) section.

### Does Noir send my code anywhere?

No. A plain `noir scan` makes no network requests. Only these options do:

- `--ai-provider` sends the source code being analyzed to the LLM provider. Credentials files are withheld. See [What Gets Sent](@/get_started/ai_power/index.md)
- `-P` (passive scan) runs `git clone` or `git fetch` on the rules repository. No code is sent, and `--passive-scan-path` or `--passive-scan-no-update-check` skips the download. See [Default Passive Scan Rules](@/usage/passive_scan/default_rules/index.md)
- `--probe` and `--probe-via` send HTTP requests for the endpoints found to the target given with `-u`. See [Delivering Results to Other Tools](@/usage/more_features/deliver/index.md)
- `--export-es`, `--export-opensearch` and `--export-webhook` send the list of endpoints found, not the code. See [Delivering Results to Other Tools](@/usage/more_features/deliver/index.md)

### How do I report bugs or request features?

Open a [GitHub Issue](https://github.com/owasp-noir/noir/issues) to report bugs or request features.
