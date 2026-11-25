# BatchTrainingJob reference workload: one image, entry points submit, train,
# cleanup, probe (SPEC-P6 P6-T2.1, D10). Build context: this directory.
#   docker build --load -t batchtraining:dev workloads/batch-training
# Published by .github/workflows/batch-training-image.yml; consumers pin @sha256.
ARG PYTHON=python:3.12-slim@sha256:191083cdf6c7bda8c76158983163ead5d5cf7b77cf3033e805bb0f5296f51b4b

FROM ${PYTHON} AS build
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_CACHE_DIR=1
RUN python -m venv /opt/venv
COPY requirements.txt /tmp/requirements.txt
# Every package in the tree is pinned by hash; wheels only, nothing compiled here.
RUN /opt/venv/bin/pip install --require-hashes --no-deps --only-binary=:all: -r /tmp/requirements.txt
COPY src/batchtraining /opt/app/batchtraining
# Bytecode at build time, so a read-only root filesystem needs no write.
RUN /opt/venv/bin/python -m compileall -q /opt/app /opt/venv/lib

FROM ${PYTHON}
LABEL org.opencontainers.image.source="https://github.com/EurusDevSec/Zero-D-Rift" \
      org.opencontainers.image.description="Zero D-Rift BatchTrainingJob reference workload" \
      org.opencontainers.image.licenses="MIT"
COPY --from=build /opt/venv /opt/venv
COPY --from=build /opt/app /opt/app
ENV PATH=/opt/venv/bin:$PATH \
    PYTHONPATH=/opt/app \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
USER 10001:10001
ENTRYPOINT ["python", "-m", "batchtraining"]
CMD ["train"]
