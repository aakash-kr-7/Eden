# ═══════════════════════════════════════════════════════════════════
# FILE: memory/embedder.py
# PURPOSE: Loads SentenceTransformers model and generates 384-dim vectors.
# CONTEXT: Called by memory store and retriever. Model loads once at startup.
# ═══════════════════════════════════════════════════════════════════

from sentence_transformers import SentenceTransformer
import numpy as np
import logging

logger = logging.getLogger(__name__)

class Embedder:
    _instance: SentenceTransformer | None = None
    MODEL_NAME = "all-MiniLM-L6-v2"
    DIMENSIONS = 384
    
    @classmethod
    def get(cls) -> SentenceTransformer:
        if cls._instance is None:
            logger.info(f"Loading embedding model {cls.MODEL_NAME}...")
            cls._instance = SentenceTransformer(cls.MODEL_NAME)
            logger.info("Embedding model loaded.")
        return cls._instance
    
    @classmethod
    def embed(cls, text: str) -> bytes:
        """
        Returns a 384-dim vector as bytes (for sqlite-vec storage).
        """
        model = cls.get()
        vector = model.encode([text], normalize_embeddings=True)[0]
        return vector.astype(np.float32).tobytes()
    
    @classmethod
    def embed_for_search(cls, text: str) -> np.ndarray:
        """
        Returns a 384-dim numpy array for distance computation.
        """
        model = cls.get()
        return model.encode([text], normalize_embeddings=True)[0].astype(np.float32)
