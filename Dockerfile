# ── Stage 1: Builder ──────────────────────────────────────────────────────────
# Use specific version tag — Kyverno disallows :latest
FROM python:3.12-slim AS builder

WORKDIR /build

# Install dependencies into a separate directory
# so we copy only what's needed into the final image
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: Final image ───────────────────────────────────────────────────────
FROM python:3.12-slim

# Labels for traceability
LABEL maintainer="Devi.M <2024HT66021@pilani.bits-pilani.ac.in>"
LABEL org.opencontainers.image.title="secure-app"
LABEL org.opencontainers.image.description="Secure CI/CD Pipeline Demo App"

# ── Create non-root user (Kyverno: runAsNonRoot) ──────────────────────────────
RUN groupadd -g 3000 appgroup && \
    useradd -u 1000 -g appgroup -s /bin/sh -m appuser

# ── Copy installed packages from builder ──────────────────────────────────────
COPY --from=builder /install /usr/local

# ── Copy application code ─────────────────────────────────────────────────────
WORKDIR /app
COPY app.py .

# Set ownership to non-root user
RUN chown -R appuser:appgroup /app

# ── Switch to non-root user (Kyverno: runAsNonRoot + runAsUser: 1000) ─────────
USER 1000

# ── Expose port ───────────────────────────────────────────────────────────────
EXPOSE 8080

# ── Health check ──────────────────────────────────────────────────────────────
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')"

# ── Run with gunicorn (production WSGI server) ────────────────────────────────
# --tmp-upload-dir /tmp satisfies readOnlyRootFilesystem by using the
# emptyDir volume mounted at /tmp in the deployment yaml
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", \
     "--tmp-upload-dir", "/tmp", "app:app"]
