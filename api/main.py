import logging
import time
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from fastapi import FastAPI

# --- OpenTelemetry Imports ---
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import ConsoleSpanExporter, SimpleSpanProcessor

from api.config import get_settings
from api.logging_config import configure_logging
from api.repositories.postgres_repository import PostgresDB
from api.routers.journal_router import router as journal_router

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None]:
    configure_logging()
    settings = get_settings()
    async with PostgresDB(settings.database_url) as database:
        app.state.database = database

        logger.info("API is ready to accept requests")
        try:
            # TODO (Task 3): Log API readiness at INFO after the database is ready.
            logger.info("API is ready to accept requests")
            yield
        finally:
            logger.info("API is shutting down")
            # TODO (Task 3): Log API shutdown at INFO during cleanup.
            logger.info("API is shutting down")
            del app.state.database


# --- OTel Configuration ---
resource = Resource.create({"service.name": "journal-api", "service.version": "1.0.0"})

tracer_provider = TracerProvider(resource=resource)

console_exporter = ConsoleSpanExporter()
tracer_provider.add_span_processor(SimpleSpanProcessor(console_exporter))

trace.set_tracer_provider(tracer_provider)


app = FastAPI(
    title="Journal API",
    description="A simple journal API for tracking daily work, struggles, and intentions",
    lifespan=lifespan,
)
app.include_router(journal_router)


# Simulated in-memory database
journal_entries = []


@app.get("/entries")
def get_entries():
    time.sleep(0.1)
    return {"entries": journal_entries}


@app.post("/entries")
def create_entry(title: str, content: str):
    time.sleep(0.2)
    entry = {"id": len(journal_entries) + 1, "title": title, "content": content}
    journal_entries.append(entry)
    return {"message": "Entry created", "entry": entry}
