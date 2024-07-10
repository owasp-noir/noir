---
title: Introduction
layout: page
permalink: /introduction/
nav_order: 1
---

## What is noir?
Noir is an open-source project specializing in identifying attack surfaces for enhanced whitebox security testing and security pipeline. This includes the capability to discover API endpoints, web endpoints, and other potential entry points within source code for thorough security analysis.

## How it works?

Noir is composed of several key components: detector, analyzer, deliver, minilexer, output-builder, and tagger. These components interact and work together to effectively analyze source code. Through this process, they help identify endpoints, parameters, headers, and more within the source code.

```mermaid
flowchart LR
    SourceCode --> Detectors

    subgraph Detectors
        direction LR
        Detector1 & Detector2 & Detector3
    end

    Detectors --> Analyzers

    subgraph Analyzers
        direction LR
        Analyzer1 & Analyzer2 & Analyzer3
        Analyzer2 --> |Condition| Minilexer
        Analyzer3 --> |Condition| Miniparser
    end

    Analyzers --> |Condition| Deliver
    Analyzers --> |Condition| Tagger
    Deliver --> OutputBuilder
    Tagger --> OutputBuilder
    Analyzers --> OutputBuilder
    OutputBuilder --> Endpoints

```