# Use a lightweight, official Python image
FROM python:3.14

# Install the 'uv' package manager
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Set the working directory inside the container
WORKDIR /app

# Copy dependency files first. 
# Docker caches layers, so if dependencies don't change, it skips reinstalling them.
COPY pyproject.toml uv.lock ./

# Install only production dependencies (no dev tools like pytest or ruff)
RUN uv sync --frozen --no-dev

# Copy the rest of the application code
COPY . .

# Expose the port the app runs on
EXPOSE 8000

# Command to run the application
CMD ["uv", "run", "uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]