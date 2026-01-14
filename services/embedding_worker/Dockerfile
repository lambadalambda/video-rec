ARG BASE_IMAGE=pytorch/pytorch:2.9.1-cuda12.8-cudnn9-runtime

FROM ${BASE_IMAGE}

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY requirements*.txt ./
RUN python -m pip install --no-cache-dir -r requirements.txt -r requirements-qwen.txt -r requirements-whisper.txt

COPY embedding_worker ./embedding_worker

EXPOSE 9001

CMD ["python", "-m", "uvicorn", "embedding_worker.main:app", "--host", "0.0.0.0", "--port", "9001"]

