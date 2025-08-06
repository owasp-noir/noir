+++
title = "Running Noir"
description = "Learn the basic commands to get started with Noir. This guide shows you how to run a scan on a directory and view the available command-line options."
weight = 3
sort_by = "weight"

[extra]
+++

Once you have Noir installed, you can start using it to analyze your code. The most fundamental command is running a scan on a directory.

## Basic Scan

To analyze a codebase, you need to tell Noir where to find the source code. You can do this with the `-b` or `--base-path` flag, followed by the path to the directory you want to scan.

For example, to scan the current directory, you would run:

```bash
noir -b .
```

If your code is in a subdirectory named `my_app`, you would use:

```bash
noir -b ./my_app
```

When you run this command, Noir will analyze the code in the specified directory and output a list of the endpoints it discovers.

![](./running.png)

## Viewing Help Information

To see a full list of all available commands and flags, you can use the `-h` or `--help` flag:

```bash
noir -h
```

This will display the help documentation, which provides a comprehensive overview of Noir's capabilities.
