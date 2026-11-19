# RAGSandbox reference workload: one image, entry points db-init, bootstrap,
# cleanup, serve (SPEC-P4 §1, P4-T3.1 B, D8). Build context: this directory.
#   docker build --load -t ragsandbox:dev workloads/rag-sandbox
# Published by .github/workflows/rag-sandbox-image.yml; consumers pin @sha256.
ARG PYTHON=python:3.13-slim@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90

FROM ${PYTHON} AS build
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_CACHE_DIR=1
RUN python -m venv /opt/venv
COPY requirements.txt /tmp/requirements.txt
# Every package in the tree is pinned by hash; wheels only, nothing compiled here.
RUN /opt/venv/bin/pip install --require-hashes --no-deps --only-binary=:all: -r /tmp/requirements.txt
COPY src/ragsandbox /opt/app/ragsandbox
# Bytecode at build time, so a read-only root filesystem needs no write.
RUN /opt/venv/bin/python -m compileall -q /opt/app /opt/venv/lib

FROM ${PYTHON}
LABEL org.opencontainers.image.source="https://github.com/EurusDevSec/Zero-D-Rift" \
      org.opencontainers.image.description="Zero D-Rift RAGSandbox reference workload" \
      org.opencontainers.image.licenses="MIT"
# RDS CA bundle (VERSION_MATRIX §8). The build fails if AWS rotates the file.
ADD --chmod=0644 --checksum=sha256:b1711d12bae51838581281e23b6cb97b1074016873b4dafc80ed14002462dd77 \
    https://truststore.pki.rds.amazonaws.com/us-east-1/us-east-1-bundle.pem /opt/rds/us-east-1-bundle.pem
# ADD --chmod also sets the mode of the directory it creates; make it traversable.
RUN chmod 0755 /opt/rds
COPY --from=build /opt/venv /opt/venv
COPY --from=build /opt/app /opt/app
ENV PATH=/opt/venv/bin:$PATH \
    PYTHONPATH=/opt/app \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DB_SSLROOTCERT=/opt/rds/us-east-1-bundle.pem
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["python", "-m", "ragsandbox"]
CMD ["serve"]
