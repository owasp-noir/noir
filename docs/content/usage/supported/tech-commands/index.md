+++
title = "Managing Technology Scopes"
description = "Control which technologies Noir scans with the techs, only-techs, and exclude-techs flags."
weight = 3
sort_by = "weight"

+++

Noir detects the technologies in your code on its own. Use these flags when you want to add, limit, or drop some of them.

## Flags

*   `-t`, `--techs <TECHS>`: Add these techs to the analyzer set, on top of the auto-detected ones (comma-separated, e.g. `rails,django`).
*   `--only-techs <TECHS>`: Run only these tech detectors (comma-separated, e.g. `rails,django`).
*   `--exclude-techs <TECHS>`: Drop these techs from the result after detection.
*   `noir list techs`: List all technologies Noir supports.

All three flags can be repeated. Tech names accept short forms: `rails` matches `ruby_rails`, and `kemal` matches `crystal_kemal`.

`--techs` and `--only-techs` look alike but work differently. `--only-techs` limits which detectors run, so the scan is faster and only those techs can be found. `--techs` forces a tech's analyzer to run even if detection missed it. Use both for "only these techs, and run them even if they weren't detected".

### Include specific technologies

```bash
noir scan . --techs rails
```

### Restrict auto-detection to specific technologies

```bash
noir scan . --only-techs rails
```

### Exclude specific technologies

```bash
noir scan . --exclude-techs express,koa
```

### List available technologies

```bash
noir list techs
noir list techs -f json   # machine-readable
```
