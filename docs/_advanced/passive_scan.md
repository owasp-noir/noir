---
title: Passive Scan
has_children: true
nav_order: 4
layout: page
---

## Passive Scan
{: .d-inline-block }

Since (v0.18.0) 
{: .label .label-green }

A Passive Scan is a feature where additional actions are performed by the Detector to identify security issues according to scan rules. This functionality typically includes:

* Regular Expression Matching: It uses regular expressions to match patterns that could indicate security vulnerabilities.
* String Matching: Besides regex, it looks for specific strings within the code that could be indicative of security concerns.
* Default Rule Set: Comes with a predefined set of rules to check against common security issues.

```bash
noir -b <BASE_PATH> -P

# You can check the format list with the -h flag.
#  PASSIVE SCAN:
#    -P, --passive-scan               Perform a passive scan for security issues using rules from the specified path
#    --passive-scan-path PATH         Specify the path for the rules used in the passive security scan
```

Usage Example:

When you run a command like:

```bash
noir -b ./your_app -P
```

The passive scan might produce results like:

```
★ Passive Results:
[critical][hahwul-test][secret] use x-api-key
  ├── extract:   env.request.headers["x-api-key"].as(String)
  └── file: ./spec/functional_test/fixtures/crystal_kemal/src/testapp.cr:4
```

Explanation of Output:

* Label: `[critical][hahwul-test][secret]` - This line indicates the severity, test context, and type of issue found. Here, it's critical, related to a test named hahwul-test, and concerns a secret.
* Extract: This shows where or how the sensitive information is being accessed or used. In this case, it's extracting an x-api-key from the request headers.
* File: Indicates the location of the potential security issue within the codebase, pointing to the exact file and line number where the issue was detected.

This output helps developers immediately identify where and what kind of security issues exist in their code, focusing on passive analysis without actively exploiting the vulnerabilities.