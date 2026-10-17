# ChatPDF

A native macOS application that enables interactive conversations with PDF documents using local large language models and semantic search powered by MLX.

## Overview

ChatPDF brings conversational AI to your PDF documents using a local-first approach. Upload any PDF and ask natural language questions about its content. The app uses vector embeddings and semantic search to retrieve relevant sections, then generates answers with an on-device LLM—all without sending data to external services.

## Architecture

ChatPDF implements a **Retrieval Augmented Generation (RAG)** pipeline:

1. **PDF Ingestion** - Extracts text and splits into token-aware chunks (256 tokens with 15% overlap)
2. **Embeddings** - Converts text chunks to vector embeddings using MLX embedders
3. **Vector Search** - Finds semantically similar chunks using VecturaKit vector database
4. **Context Assembly** - Builds context from top matching chunks (filtered by relevance score)
5. **Intent Routing** - Before retrieval, an embedding-based classifier sorts each question into one of three intents:
   - *General* ("what is this about?", "summarize") - the whole document is used as context (or a spread of page excerpts if it is too long)
   - *Topical* - the top retrieved chunks are used as context
   - *Unrelated* - the app declines with a short message and makes no LLM call
   It defaults to *topical* whenever it is unsure, so a real question is never refused by mistake.
6. **LLM Generation** - Sends query + context to the local model for answer generation
7. **Source Citation** - Returns answers with page numbers and chunk references

## Features

- **Native SwiftUI App** - Built with modern SwiftUI for a seamless macOS experience
- **Local LLM Processing** - Runs a 4-bit MLX model locally on Apple Silicon (downloaded Qwen 3 4B by default, or any compatible model folder you choose)
- **Bring Your Own Model** - "Use Local Model Folder..." on the start screen loads a model from disk; the choice is remembered across launches
- **Intent Routing** - Summary questions get the whole document, specific questions get retrieved chunks, off-topic questions are declined
- **Semantic Search** - Vector-based retrieval finds contextually relevant document sections
- **Privacy First** - All processing happens on-device; no data leaves your computer (only the one-time model download uses the network)
- **Safe Output** - Model answers have images, links, HTML and URLs stripped, so a malicious PDF cannot make the app fetch a remote URL
- **Source Citation** - Answers include page numbers and relevance scores for verification
- **Token-Aware Chunking** - Uses exact token counts to split documents intelligently
- **PDF Rendering** - Built-in PDF viewer alongside chat interface

## Tech Stack

- **Framework**: SwiftUI + Swift Concurrency (async/await, actors)
- **LLM Inference**: [MLXLLM](https://github.com/ml-explore/mlx-swift) - Qwen 3 4B 4-bit quantized
- **Embeddings**: [MLXEmbedders](https://github.com/ml-explore/mlx-swift) - Text-to-vector conversion
- **Vector DB**: [VecturaKit](https://github.com/jakechang/VecturaKit) - Semantic search
- **PDF**: PDFKit - Document rendering and text extraction
- **Tokenization**: MLXLMTokenizers - Token counting for precise chunking
- **Markdown**: MarkdownUI - Render model responses with formatting

## Getting Started

### Prerequisites

- macOS 26.6 or later (the build targets macOS 26 and the UI uses Liquid Glass)
- A recent Xcode that includes the macOS 26 SDK (developed with Xcode 27)
- Apple Silicon Mac (M1/M2/M3/M4 or later) - required for MLX
- Python 3 with `huggingface_hub` (only to fetch the embedding model once)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/c2p-cmd/ChatPDF.git
cd ChatPDF
```

2. Download the embedding model. It is bundled into the app, so **this must be done before building** (the folder is git-ignored and is about 0.5 GB):
```bash
pip install huggingface_hub
python3 download_model.py
```

3. Open the Xcode project:
```bash
open ChatPDF.xcodeproj
```

4. Build and run (⌘B to build, ⌘R to run)

The app will guide you through downloading the LLM model on first launch, or you can point it at a model folder you already have.

## Usage

1. **Launch the app** - First time setup downloads the Qwen 3 4B model (~2GB), or choose **Use Local Model Folder...** to load one you already have
2. **Upload PDF** - Drag & drop or select a PDF file
3. **Chat** - Ask questions about the document's content
4. **View Sources** - Click "Sources" in responses to see which document sections were used

## Models

- **LLM**: `Qwen 3 4B 4-bit quantized` - Downloads from Hugging Face on first use
- **Embeddings**: `Qwen3-Embedding-0.6B-4bit-DWQ` - Fetched with `download_model.py`, bundled into the app; also drives the intent router

### Using your own model

Pick a folder containing `config.json` and `*.safetensors` (an MLX-format model supported by `MLXLLM`). Measured on an M3 Pro with the project's test PDFs:

| Model | Topical answer | Whole-document summary | Notes |
|---|---|---|---|
| Phi-4-mini 4-bit | ~2.0 s | ~8.8 s | Fastest and most concise |
| Qwen3.5-4B 4-bit | ~3.2 s | ~11.5 s | Richer summaries; one intermittent crash seen in an MLX kernel |
| DeepSeek-R1-Distill 1.5B | ~11 s | ~18 s | Not recommended: always reasons out loud and its reasoning cannot be stripped |

## Notes

- The embedding model folder `ChatPDF/qwen3-embedding` is git-ignored. If the app fails at launch, run `download_model.py` first.
- `gemma-4-e4b-it-4bit` (mlx-vlm conversion) currently fails to load with the pinned `mlx-swift-lm`.
- Pages with little selectable text (scans, slide decks exported as images) are OCR'd with Apple's Vision framework during ingest, so ingesting them is slower. A PDF is only rejected as empty if neither the text layer nor OCR finds anything.
- Model folders are read through a security-scoped bookmark; if the folder is moved or deleted the app returns to the start screen.

## Project Structure

```
ChatPDF/
├── ChatPDFApp.swift          # App entry point
├── ContentView.swift         # Main navigation and routing
├── ViewModels.swift          # State management (AppViewModel, ChatViewModel, model bookmark)
├── Service.swift             # Core RAG pipeline and ML integration
├── IntentRouter.swift        # General / topical / unrelated question classifier
├── ChatView.swift            # Chat interface with message display
├── UploadView.swift          # PDF upload interface
├── PDFPreview.swift          # PDF viewer component
├── ModelDownloadView.swift   # LLM download progress UI
├── LoadingView.swift         # Processing indicator
├── Theme.swift               # Styling utilities
└── Mocks.swift              # Data models and mock services

ChatPDFTests/                 # Retrieval, intent, sanitizer and local-model tests
├── Fixtures/                 # Sample PDFs used by the tests
└── LLMBenchmarkTests.swift   # Opt-in LLM benchmark (TEST_RUNNER_RUN_BENCH=1)
```

## Testing

```bash
xcodebuild -project ChatPDF.xcodeproj -scheme ChatPDF -destination 'platform=macOS' test
```

The default run covers retrieval, the intent router, output sanitising and local-model validation. The end-to-end and LLM benchmark suites are opt-in because they need a chat model (`TEST_RUNNER_RUN_E2E=1`, `TEST_RUNNER_RUN_BENCH=1`).

## Configuration

### Chunking Parameters (in Service.swift)
- Default chunk size: 256 tokens
- Overlap: 15%
- These can be adjusted in the `ingest(url:)` method

### Search Parameters (in Service.swift)
- Relevance score threshold: 0.22 (also gates the "unrelated" decline)
- Max chunks returned: 5, of which up to 4 reach the prompt. The best 2 are always kept even when every score is below the threshold (the model can say "not found" itself), so a low-scoring document never gets an empty context
- Adjust in `performReply(to:)`; the retrieval step itself is `retrieve(_:)`

### Intent Router (in IntentRouter.swift)
- A non-topical intent must beat *topical* by a cosine margin of 0.08, otherwise the question is treated as topical
- Whole-document context is used when the document fits 3,000 tokens

## License

[Add your license here]

## Contributing

Contributions are welcome. Please feel free to submit a Pull Request.
