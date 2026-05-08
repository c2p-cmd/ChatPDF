# ChatPDF

A macOS application that lets you chat with PDF documents using local large language models powered by MLX.

## Overview

ChatPDF brings conversational AI to your PDF documents. Upload any PDF and ask questions about its content—all processing happens locally on your machine for privacy and performance.

## Features

- **Local LLM Processing** - Powered by MLX for efficient on-device inference
- **PDF Chat Interface** - Ask questions and get answers from your documents
- **Privacy First** - All processing happens locally, no data sent to external services
- **macOS Native** - Built for a seamless macOS experience

## Getting Started

### Prerequisites

- Python 3.10+
- macOS with MLX support

### Installation

1. Clone the repository:
```bash
git clone https://github.com/c2p-cmd/ChatPDF.git
cd ChatPDF
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

3. Download the embedding model:
```bash
python download_model.py
```

4. Run the application:
```bash
python main.py
```

## Model

This project uses:
- **Embedding Model**: `mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ`
- **Framework**: MLX

## License

[Add your license here]

## Contributing

Contributions are welcome. Please feel free to submit a Pull Request.
