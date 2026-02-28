+++
title = "AI-Powered Analysis"
description = "Connect Noir to LLM providers for deeper code analysis and endpoint discovery."
weight = 4
sort_by = "weight"

+++

Connect Noir to Large Language Models (cloud-based, local, or ACP agent-based) for deeper code analysis. AI helps identify endpoints in unsupported languages and frameworks.

![](./ai_integration.jpeg)

## Usage

Specify an AI provider, model, and API key:

```bash
noir -b . --ai-provider <PROVIDER> --ai-model <MODEL_NAME> --ai-key <YOUR_API_KEY>
```

For ACP providers (`acp:*`), `--ai-model` is optional and `--ai-key` is usually not required:

```bash
noir -b . --ai-provider acp:codex
```

### Command-Line Flags

| Flag | Description |
|---|---|
| `--ai-provider` | Provider prefix (e.g., `openai`, `ollama`, `acp:codex`) or custom API URL |
| `--ai-model` | Model name (e.g., `gpt-4o`), optional for `acp:*` |
| `--ai-key` | API key (or use `NOIR_AI_KEY` env var) |
| `--ai-agent` | Enable agentic AI workflow (iterative tool-calling loop) |
| `--ai-agent-max-steps` | Max steps for AI agent loop (default: `20`) |
| `--ai-native-tools-allowlist` | Provider allowlist for native tool-calling (comma-separated, default: `openai,xai,github`) |
| `--ai-max-token` | Max tokens for AI requests (optional) |
| `--cache-disable` | Disable LLM response cache |
| `--cache-clear` | Clear LLM cache before run |

### Supported AI Providers

Noir has built-in presets for several popular AI providers:

| Prefix | Default Host |
|---|---|
| `openai` | `https://api.openai.com` |
| `xai` | `https://api.x.ai` |
| `github` | `https://models.github.ai` |
| `azure` | `https://models.inference.ai.azure.com` |
| `openrouter` | `https://openrouter.ai/api/v1` |
| `vllm` | `http://localhost:8000` |
| `ollama` | `http://localhost:11434` |
| `lmstudio` | `http://localhost:1234` |
| `acp:codex` | `npx @zed-industries/codex-acp` |
| `acp:gemini` | `gemini --experimental-acp` |
| `acp:claude` | `npx @zed-industries/claude-agent-acp` |

For custom providers, use the full API URL: `--ai-provider=http://my-custom-api:9000`.

For raw ACP and agent stderr logs, set `NOIR_ACP_RAW_LOG=1`.

## How AI-Powered Analysis Works

{% mermaid() %}
flowchart TB
    Start([Start AI Analysis]) --> InitAdapter[Initialize LLM Adapter]
    InitAdapter --> ProviderCheck{Provider Type?}
    
    ProviderCheck -->|OpenAI/xAI/etc| GeneralAdapter[General Adapter<br/>OpenAI-compatible API]
    ProviderCheck -->|Ollama/Local| OllamaAdapter[Ollama Adapter<br/>with Context Reuse]
    ProviderCheck -->|ACP Agent| ACPAdapter[ACP Adapter<br/>Codex/Gemini/Claude/Custom]
    
    GeneralAdapter --> FileSelection
    OllamaAdapter --> FileSelection
    ACPAdapter --> FileSelection
    
    FileSelection[File Selection] --> FileCount{File Count?}
    
    FileCount -->|≤ 10 files| AnalyzeAll[Analyze All Files]
    FileCount -->|> 10 files| LLMFilter[LLM-Based Filtering]
    
    LLMFilter --> CacheCheck1{Cache Hit?}
    CacheCheck1 -->|Yes| UseCached1[Use Cached Filter]
    CacheCheck1 -->|No| FilterLLM[Call LLM with<br/>FILTER prompt]
    FilterLLM --> StoreCache1[Store in Cache]
    UseCached1 --> TargetFiles
    StoreCache1 --> TargetFiles
    
    TargetFiles[Selected Target Files] --> BundleCheck{Large File Set<br/>and Token Limit?}
    
    AnalyzeAll --> BundleCheck
    
    BundleCheck -->|Yes| BundleMode[Bundle Analysis Mode]
    BundleCheck -->|No| SingleMode[Single File Mode]
    
    BundleMode --> CreateBundles[Create File Bundles<br/>within Token Limits]
    CreateBundles --> ParallelBundles[Process Bundles<br/>Concurrently]
    
    ParallelBundles --> BundleLoop{For Each Bundle}
    BundleLoop --> CacheCheck2{Cache Hit?}
    CacheCheck2 -->|Yes| UseCached2[Use Cached Analysis]
    CacheCheck2 -->|No| BundleLLM[Call LLM with<br/>BUNDLE_ANALYZE prompt]
    BundleLLM --> StoreCache2[Store in Cache]
    UseCached2 --> ParseEndpoints1
    StoreCache2 --> ParseEndpoints1
    ParseEndpoints1[Parse Endpoints<br/>from Response] --> BundleLoop
    BundleLoop -->|Done| Combine
    
    SingleMode --> FileLoop{For Each File}
    FileLoop --> CacheCheck3{Cache Hit?}
    CacheCheck3 -->|Yes| UseCached3[Use Cached Analysis]
    CacheCheck3 -->|No| AnalyzeLLM[Call LLM with<br/>ANALYZE prompt]
    AnalyzeLLM --> StoreCache3[Store in Cache]
    UseCached3 --> ParseEndpoints2
    StoreCache3 --> ParseEndpoints2
    ParseEndpoints2[Parse Endpoints<br/>from Response] --> FileLoop
    FileLoop -->|Done| Combine
    
    Combine[Combine All Endpoints] --> LLMOptCheck{LLM Optimization<br/>Enabled?}
    
    LLMOptCheck -->|Yes| FindCandidates[Find Optimization<br/>Candidates]
    FindCandidates --> OptLoop{For Each Candidate}
    OptLoop --> OptimizeLLM[Call LLM with<br/>OPTIMIZE prompt]
    OptimizeLLM --> ApplyOpt[Apply Optimizations<br/>to Endpoint]
    ApplyOpt --> OptLoop
    OptLoop -->|Done| FinalResults
    
    LLMOptCheck -->|No| FinalResults[Final Optimized Results]
    
    FinalResults --> End([End])
    
    style Start fill:#e1f5e1
    style End fill:#e1f5e1
    style LLMFilter fill:#fff4e1
    style FilterLLM fill:#e1f0ff
    style BundleLLM fill:#e1f0ff
    style AnalyzeLLM fill:#e1f0ff
    style OptimizeLLM fill:#e1f0ff
    style CacheCheck1 fill:#ffe1e1
    style CacheCheck2 fill:#ffe1e1
    style CacheCheck3 fill:#ffe1e1
    style UseCached1 fill:#e1ffe1
    style UseCached2 fill:#e1ffe1
    style UseCached3 fill:#e1ffe1
{% end %}

### Key Components

#### LLM Adapter Layer
Provider-agnostic adapters: **General** (OpenAI-compatible APIs), **Ollama** (with server-side context reuse), and **ACP** (agent runtimes like `acp:codex`).

#### Intelligent File Filtering
For projects with >10 files, the LLM filters the file list to identify likely endpoint files before analysis.

#### Bundle Analysis
Groups files into token-limited bundles and processes them concurrently to maximize throughput on large codebases.

#### Response Caching
LLM responses are cached on disk (SHA256-keyed) at `~/.local/share/noir/cache/ai/`. Use `--cache-disable` or `--cache-clear` to control caching.

#### LLM Optimizer
Optional post-processing that normalizes URLs, parameter names, and applies RESTful conventions to improve endpoint quality.
