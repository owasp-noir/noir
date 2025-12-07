+++
title = "AI-Powered Analysis"
description = "Learn how to use Noir's AI integration to get advanced analysis of your code. This guide covers the necessary flags and options for connecting to LLM providers like OpenAI, xAI, and local models."
weight = 4
sort_by = "weight"

[extra]
+++

Noir can connect to Large Language Models (LLMs)—both cloud-based services and local instances—to provide a deeper level of analysis for your codebase. By leveraging AI, Noir can often identify endpoints in languages and frameworks that it doesn't natively support, and can provide additional insights into the functionality of your application.

![](./ai_integration.jpeg)

## How AI-Powered Analysis Works

Noir's AI integration follows a sophisticated workflow that combines intelligent file filtering, optimized bundling, response caching, and endpoint optimization to deliver comprehensive analysis results.

{% mermaid() %}
flowchart TB
    Start([Start AI Analysis]) --> InitAdapter[Initialize LLM Adapter]
    InitAdapter --> ProviderCheck{Provider Type?}
    
    ProviderCheck -->|OpenAI/xAI/etc| GeneralAdapter[General Adapter<br/>OpenAI-compatible API]
    ProviderCheck -->|Ollama/Local| OllamaAdapter[Ollama Adapter<br/>with Context Reuse]
    
    GeneralAdapter --> FileSelection
    OllamaAdapter --> FileSelection
    
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

#### 1. LLM Adapter Layer
Noir uses a provider-agnostic adapter pattern that supports multiple LLM providers:
- **General Adapter**: For OpenAI-compatible APIs (OpenAI, xAI, Azure, GitHub Models, etc.)
- **Ollama Adapter**: Specialized adapter with server-side context reuse for improved performance

#### 2. Intelligent File Filtering
When analyzing projects with many files (>10), Noir uses the LLM to intelligently filter which files are likely to contain endpoints:
- Sends file path list to LLM with FILTER prompt
- LLM identifies potential endpoint files
- Reduces analysis time and costs

#### 3. Bundle Analysis
For large codebases, Noir bundles multiple files together to maximize efficiency:
- Estimates token usage for each file
- Creates bundles within model token limits (with 80% safety margin)
- Processes bundles concurrently for speed
- Uses BUNDLE_ANALYZE prompt to extract endpoints from all files in bundle

#### 4. Response Caching
All LLM responses are cached on disk to improve performance and reduce costs:
- Cache key: SHA256 hash of (provider + model + operation + format + payload)
- Cache location: `~/.local/share/noir/cache/ai/` (or `NOIR_HOME` if set)
- Enables instant re-analysis of unchanged code
- Can be disabled with `--cache-disable` or cleared with `--cache-clear`

#### 5. LLM Optimizer
An optional post-processing step that refines endpoint results:
- Identifies non-standard patterns (wildcards, unusual naming, etc.)
- Normalizes URLs and parameter names
- Applies RESTful conventions
- Improves overall endpoint quality

## How to Use the AI Integration

To enable AI-powered analysis, you need to specify an AI provider, a model, and an API key.

```bash
noir -b . --ai-provider <PROVIDER> --ai-model <MODEL_NAME> --ai-key <YOUR_API_KEY>
```

### Command-Line Flags

*   `--ai-provider`: The AI provider you want to use. This can be a preset prefix (like `openai` or `ollama`) or the full URL of a custom API endpoint.
*   `--ai-model`: The name of the model you want to use for the analysis (e.g., `gpt-4o`).
*   `--ai-key`: Your API key for the AI provider. You can also set this using the `NOIR_AI_KEY` environment variable.
*   `--ai-max-token`: (Optional) The maximum number of tokens to use for AI requests. This can affect the length of the generated text.
*   `--cache-disable`: Disable the on-disk LLM cache for this run.
*   `--cache-clear`: Clear the LLM cache directory before the run.

By default, Noir caches AI responses on disk to speed up repeated analyses and reduce costs. Use the cache flags above to bypass or purge the cache when needed.

### Supported AI Providers

Noir has built-in presets for several popular AI providers:

| Prefix | Default Host |
|---|---|
| `openai` | `https://api.openai.com` |
| `xai` | `https://api.x.ai` |
| `github` | `https://models.github.ai` |
| `azure` | `https://models.inference.ai.azure.com` |
| `vllm` | `http://localhost:8000` |
| `ollama` | `http://localhost:11434` |
| `lmstudio` | `http://localhost:1234` |

If you are using a provider that is not on this list, you can provide the full URL to its API endpoint, for example: `--ai-provider=http://my-custom-api:9000`.

### Benefits and Considerations

*   **Expanded Support**: LLMs can help Noir analyze frameworks and languages that are not yet natively supported.
*   **Deeper Insights**: AI models can often identify subtle or complex endpoints that might be missed by traditional static analysis.
*   **Potential Downsides**: Be aware that AI analysis can sometimes produce false positives (hallucinations) and may be slower than a standard scan, depending on the model and hardware.

By integrating AI into your workflow, you can significantly enhance Noir's analytical capabilities and gain a more comprehensive understanding of your codebase.
