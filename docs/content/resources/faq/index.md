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
  "How do I report bugs or request features?"
]
faq_answers = [
  "An open-source static analysis tool that discovers API endpoints, web pages, and other attack surface entry points from source code.",
  "Via Homebrew, Snapcraft, Docker, and more. See the Installation page.",
  "See the full list on the Supported Languages and Frameworks page.",
  "Read the Contributing Guide to get started.",
  "Yes, Noir is free and open-source under the MIT license. You can use it freely for commercial purposes.",
  "You can integrate with ZAP, Burp Suite, Caido, and more. See the Pipeline for DAST guide.",
  "Noir supports JSON, YAML, OpenAPI Specification, cURL, and many more formats. See the Output Formats section.",
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

Noir supports JSON, YAML, OpenAPI Specification, cURL, and many more formats. See the [Output Formats](@/usage/output_formats/_index.md) section.

### How do I report bugs or request features?

Open a [GitHub Issue](https://github.com/owasp-noir/noir/issues) to report bugs or request features.
