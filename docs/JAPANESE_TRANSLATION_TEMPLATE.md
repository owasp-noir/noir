# Japanese (JA) Translation Template for OWASP Noir Documentation

## Overview

This template provides guidance for creating Japanese translations of OWASP Noir documentation files. The Japanese translation system follows the same pattern as the Korean (KO) translation system.

## File Naming Convention

Japanese translation files follow this pattern:
- `index.md` → `index.ja.md`
- `_index.md` → `_index.ja.md`

## Translation Guidelines

### Structure
1. Keep the same frontmatter structure as the original file
2. Translate all content in the frontmatter (title, description, etc.)
3. Translate the markdown content
4. Preserve all formatting, links, and code blocks

### Sample Translation Structure

```markdown
+++
title = "日本語のタイトル"
description = "日本語の説明"
weight = 1
sort_by = "weight"

[extra]
+++

# 翻訳されたコンテンツ

ここに日本語で翻訳されたコンテンツを記載します。

*   **[リンク](path/to/page)**：説明文
*   **[別のリンク](path/to/another)**：別の説明文

```bash
# コードブロックは原文のまま保持
noir --version
```
```

## Current Status

As of this implementation:
- Total documentation files: 44
- Japanese translations completed: 7/44
- Korean translations completed: 44/44

## Completed Translations

- ✅ `_index.ja.md` - Main landing page
- ✅ `get_started/_index.ja.md` - Getting Started section
- ✅ `get_started/overview/index.ja.md` - Overview page  
- ✅ `get_started/installation/index.ja.md` - Installation guide
- ✅ `resoruces/_index.ja.md` - Resources section
- ✅ `resoruces/faq/index.ja.md` - FAQ page
- ✅ `usage/_index.ja.md` - Usage guide section

## How to Check Translation Status

Run the i18n checker to see missing translations:

```bash
# Check Japanese translations only
just docs-i18n-check -l ja

# Check both Korean and Japanese (default)
just docs-i18n-check

# Alternative method
crystal run scripts/check_i18n_docs.cr -- -l ja
```

## Key Translation Guidelines

1. **Technical Terms**: Keep technical terms in English when appropriate (e.g., "API", "JSON", "YAML")
2. **Product Names**: Keep product names in English (e.g., "OWASP Noir", "GitHub", "Docker")
3. **Code Examples**: Keep all code examples unchanged
4. **Links**: Preserve all internal and external links
5. **Consistency**: Use consistent translations for recurring terms

## Common Translation Pairs

| English | Japanese |
|---------|----------|
| Attack Surface | アタックサーフェス |
| Endpoint | エンドポイント |
| Framework | フレームワーク |
| Static Analysis | 静的解析 |
| Vulnerability | 脆弱性 |
| Installation | インストール |
| Configuration | 設定 |
| Documentation | ドキュメント |
| Open Source | オープンソース |
| Contributing | 貢献 |

## Priority Files for Translation

High priority files to translate next:
1. `get_started/running/index.ja.md` - Basic usage instructions
2. `usage/supported/language_and_frameworks/index.ja.md` - Supported technologies
3. `usage/output_formats/_index.ja.md` - Output formats overview
4. `community/_index.ja.md` - Community section

## Testing

After creating translations, test with:
```bash
# Build and test
just build
just test

# Check i18n status  
just docs-i18n-check
```

## Contributing

When contributing Japanese translations:
1. Follow the existing pattern from Korean translations
2. Ensure frontmatter is properly translated
3. Test the translation files
4. Update this template if needed