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
5. **LLM Generation** - Sends query + context to local Qwen 3 model for answer generation
6. **Source Citation** - Returns answers with page numbers and chunk references

## Features

- **Native SwiftUI App** - Built with modern SwiftUI for a seamless macOS experience
- **Local LLM Processing** - Runs Qwen 3 4B 4-bit model locally on Apple Silicon
- **Semantic Search** - Vector-based retrieval finds contextually relevant document sections
- **Privacy First** - All processing happens on-device; no data leaves your computer
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

- macOS 12.0 or later
- Xcode 14.0 or later
- Apple Silicon Mac (M1/M2/M3/M4 or later) - required for MLX

### Installation

1. Clone the repository:
```bash
git clone https://github.com/c2p-cmd/ChatPDF.git
cd ChatPDF
```

2. Open the Xcode project:
```bash
open ChatPDF.xcodeproj
```

3. Build and run (⌘B to build, ⌘R to run)

The app will guide you through downloading the LLM model on first launch.

## Usage

1. **Launch the app** - First time setup downloads the Qwen 3 4B model (~2GB)
2. **Upload PDF** - Drag & drop or select a PDF file
3. **Chat** - Ask questions about the document's content
4. **View Sources** - Click "Sources" in responses to see which document sections were used

## Models

- **LLM**: `Qwen 3 4B 4-bit quantized` - Downloads from Hugging Face on first use
- **Embeddings**: `Qwen3-Embedding-0.6B-4bit-DWQ` - Pre-configured embedding model

## Project Structure

```
ChatPDF/
├── ChatPDFApp.swift          # App entry point
├── ContentView.swift         # Main navigation and routing
├── ViewModels.swift          # State management (AppViewModel, ChatViewModel)
├── Service.swift             # Core RAG pipeline and ML integration
├── ChatView.swift            # Chat interface with message display
├── UploadView.swift          # PDF upload interface
├── PDFPreview.swift          # PDF viewer component
├── ModelDownloadView.swift   # LLM download progress UI
├── LoadingView.swift         # Processing indicator
├── Theme.swift               # Styling utilities
└── Mocks.swift              # Data models and mock services
```

## Configuration

### Chunking Parameters (in Service.swift)
- Default chunk size: 256 tokens
- Overlap: 15%
- These can be adjusted in the `ingest(url:)` method

### Search Parameters (in Service.swift)
- Relevance score threshold: 0.22
- Max chunks returned: 5
- Adjust in the `reply(to:)` method's `search()` call

## License

[Add your license here]

## Contributing

Contributions are welcome. Please feel free to submit a Pull Request.
