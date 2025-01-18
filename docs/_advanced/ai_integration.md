---
title: AI Integration
has_children: false
nav_order: 5
layout: page
---

# AI Integration
{: .d-inline-block }

New (v0.19.0) 
{: .label .label-green }


## Overview Flags

* `--ollama http://localhost:11434` Specify the Ollama server URL to connect to.
* `--ollama-model MODEL` Specify the Ollama model name to be used for analysis.


## How to Use AI Integration
### Step 1: Install and Run Ollama

1. Install Ollama: Follow the instructions on the official Ollama website to install the required software.
2. Run the Model: Start the Ollama server and ensure the desired model is available. For example:

```bash
# Download LLM model
ollama pull llama3

# Run LLM model
ollama run llama3
```

### Step 2: Run Noir with AI Analysis

To leverage AI capabilities for additional analysis, use the following command:

```bash
noir -b . --ollama http://localhost:11434 --ollama-model llama3
```

This command performs the standard Noir operations while utilizing the specified AI model for enhanced analysis.

![](../../images/advanced/ollama.jpeg)

## Benefits of AI Integration

* Using an LLM allows Noir to handle frameworks or languages that are beyond its original support scope.
* Additional endpoints that might be missed during a standard Noir scan can be identified.
* Note that there is a possibility of false positives, and the scanning speed may decrease depending on the number of LLM parameters and the performance of the machine hosting the service.

## Notes

* Ensure that the Ollama server is running and accessible at the specified URL before executing the command.
* Replace llama3 with the name of the desired model as required.