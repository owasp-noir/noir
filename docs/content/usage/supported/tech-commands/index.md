+++
title = "Managing Technology Scopes"
description = "Learn how to control which technologies Noir scans by using the `techs` and `exclude-techs` commands. This allows you to focus your scans on specific languages or frameworks."
weight = 3
sort_by = "weight"

[extra]
+++

Noir is capable of analyzing many different programming languages and frameworks. To give you more control over the scanning process, Noir provides commands that allow you to specify exactly which technologies you want to include or exclude.

This can be useful for:

*   **Focusing a scan**: If you know a project is built with a specific technology (like Rails), you can tell Noir to only look for Rails-related code, which can speed up the scan.
*   **Reducing noise**: If a project contains code from multiple frameworks, you can exclude the ones you aren't interested in to get a cleaner and more relevant output.

## How to Control the Technology Scope

You can manage the technology scope with the following flags:

*   `--techs <TECHS>`: Tell Noir to *only* use the specified technologies. You can provide a comma-separated list (e.g., `rails,django`).
*   `--exclude-techs <TECHS>`: Tell Noir to *exclude* the specified technologies from the scan.
*   `--list-techs`: Show a list of all the technologies that Noir supports.

### Example: Focusing on a Single Technology

To scan a directory but only look for code related to Ruby on Rails, you would use the `--techs` flag:

```bash
noir -b . --techs rails
```

### Example: Excluding a Technology

If you have a project that contains both PHP and JavaScript code, but you only want to see the results for PHP, you could exclude JavaScript:

```bash
noir -b . --exclude-techs express,koa
```

### Listing Available Technologies

To see a full list of all the technologies that Noir can recognize, use the `--list-techs` flag:

```bash
noir --list-techs
```

By using these commands, you can fine-tune your scans to get the most relevant results for your specific needs.
