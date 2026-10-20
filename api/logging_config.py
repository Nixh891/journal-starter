"""Application logging configuration, completed in Task 3."""

import logging
import sys


def configure_logging(level: int = logging.INFO) -> None:
    """Configure application logging at the requested level, defaulting to INFO."""

    if not logging.getLogger().hasHandlers():
        logging.basicConfig(
            level=level,
            format="%(levelname)s:%(name)s:%(message)s",
            stream=sys.stdout,
        )

    logging.getLogger().setLevel(level)
