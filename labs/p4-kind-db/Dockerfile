# LAB ONLY (DRF-45 part B). Not the published workload image: that one is built
# in P4-T3.1 (DRF-50) with hash-pinned dependencies and no psql.
#
# docker build -f labs/p4-kind-db/Dockerfile \
#   --load --build-context app=workloads/rag-sandbox -t zdr-ragsandbox:lab labs/p4-kind-db
FROM python:3.13-slim@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90

# psql for the owner's checks; lab only.
RUN apt-get update \
 && apt-get install -y --no-install-recommends postgresql-client \
 && rm -rf /var/lib/apt/lists/*

COPY --from=app requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir --root-user-action=ignore -r /app/requirements.txt
COPY --from=app src /app/src
COPY seed_master.py psql-as /usr/local/bin/
RUN chmod 0755 /usr/local/bin/psql-as /usr/local/bin/seed_master.py

ENV PYTHONPATH=/app/src PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
# Same uid as the postgres image, so both can use the lab secret volume.
USER 999:999
WORKDIR /tmp
