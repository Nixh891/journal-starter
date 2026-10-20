import logging
import sys


def configure_logging(level: int = logging.INFO) -> None:
    """Configure application logging at the requested level, defaulting to INFO."""
    
    logging.basicConfig(
        level=level,
        format="%(levelname)s:%(name)s:%(message)s",
        stream=sys.stdout,
    )
    
    # Explicitly set the root logger's level to ensure it updates 
    # even if a test runner has already installed handlers.
    logging.getLogger().setLevel(level)