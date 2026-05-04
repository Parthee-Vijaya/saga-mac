"""Pre-download Hviske weights til ~/.cache/huggingface/hub."""

from __future__ import annotations

import logging
import sys

from huggingface_hub import snapshot_download

from .config import Config

logging.basicConfig(level=logging.INFO, format="%(message)s")
log = logging.getLogger(__name__)


def main() -> int:
    cfg = Config.from_env()
    log.info("Henter '%s' (4-8 GB første gang)...", cfg.model_id)
    try:
        path = snapshot_download(repo_id=cfg.model_id, allow_patterns=None)
    except Exception:
        log.exception("Download fejlede. Tjek netværk og at huggingface-cli er logget ind hvis modellen er gated.")
        return 1
    log.info("Færdig. Cached i: %s", path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
