#!/usr/bin/env python3
"""
Download the Qwen3-Embedding model from Hugging Face.

This script downloads the mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ model
to the ChatPDF/qwen3-embedding folder.
"""

from pathlib import Path
from huggingface_hub import snapshot_download


def download_model():
    """Download the Qwen3 embedding model."""
    model_id = "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"
    output_dir = Path("ChatPDF/qwen3-embedding")
    
    # Create directory if it doesn't exist
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"Downloading {model_id}...")
    print(f"Saving to: {output_dir.absolute()}")
    
    try:
        snapshot_download(
            repo_id=model_id,
            local_dir=str(output_dir),
            local_dir_use_symlinks=False,
        )
        print("✓ Model downloaded successfully!")
    except Exception as e:
        print(f"✗ Error downloading model: {e}")
        raise


if __name__ == "__main__":
    download_model()
