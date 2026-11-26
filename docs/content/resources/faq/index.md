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
  "Not unless you ask it to. A plain noir scan makes no network requests. Options you add can: --ai-provider sends source code to the LLM provider, -P downloads rules with git, --probe, --probe-via, --status-codes and --exclude-codes send a request for each endpoint found, and the --export options send the list of endpoints, which includes source snippets when --ai-context is on.",
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

Not unless you ask it to. A plain `noir scan`, with none of the options below on the command line or in the config file, makes no network requests. These options do:

- `--ai-provider` sends the source code being analyzed to the LLM provider. Credentials files (`.env`, `*.pem`, `id_rsa` and the like) are withheld by file name unless you pass `--ai-include-sensitive`. See [What Gets Sent](@/get_started/ai_power/index.md#what-gets-sent)
- `-P` (passive scan) runs `git clone` or `git fetch` on the rules repository. No code is sent, and `--passive-scan-path` or `--passive-scan-no-update-check` skips the download. See [Default Passive Scan Rules](@/usage/passive_scan/default_rules/index.md)
- `--probe`, `--probe-via`, `--status-codes` and `--exclude-codes` send an HTTP request for each endpoint found. Most go to the target given with `-u`. An endpoint whose source names its own scheme and host is requested on that host. See [Delivering Results to Other Tools](@/usage/more_features/deliver/index.md)
- `--export-es`, `--export-opensearch` and `--export-webhook` send the list of endpoints found, with file paths and line numbers. With `--ai-context`, each endpoint also carries snippets of its source. See [Delivering Results to Other Tools](@/usage/more_features/deliver/index.md)

### How do I report bugs or request features?

Open a [GitHub Issue](https://github.com/owasp-noir/noir/issues) to report bugs or request features.
