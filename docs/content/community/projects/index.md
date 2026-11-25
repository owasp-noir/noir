+++
title = "Related Projects"
description = "Projects built with or around OWASP Noir, including official companion tools."
weight = 10
sort_by = "weight"

+++

Projects that use Noir, or sit next to it. Want yours listed? Open an issue or a pull request.

## alibi

[alibi](https://github.com/owasp-noir/alibi) cross-checks the views of an attack surface and finds the endpoints that cannot corroborate each other. It runs [OWASP Noir](https://github.com/owasp-noir/noir) once per view, then compares the JSON. Noir collects code, contracts, traffic, gateways, and infrastructure. alibi checks whether those results agree.

It is maintained in the [owasp-noir](https://github.com/owasp-noir) organization. It needs Noir 1.0.0 or newer on `PATH`.

```bash
uv tool install noir-alibi   # or: pipx install noir-alibi
alibi scan ./service
```

Announcement: [alibi: the endpoints that can't account for themselves](@/blog/introducing-alibi/index.md).
