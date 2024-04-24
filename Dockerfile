# vim:set ft=dockerfile:
#
# Copyright The CloudNativePG Contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
FROM postgres:16.2-bullseye

# Do not split the description, otherwise we will see a blank space in the labels
LABEL name="PostgreSQL Container Images" \
      vendor="The CloudNativePG Contributors" \
      version="${PG_VERSION}" \
      release="14" \
      summary="PostgreSQL Container images." \
      description="This Docker image contains PostgreSQL and Barman Cloud based on Postgres 16.2-bullseye."

LABEL org.opencontainers.image.description="This Docker image contains PostgreSQL and Barman Cloud based on Postgres 16.2-bullseye."

COPY requirements.txt /

# Install additional extensions
RUN set -xe; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		"postgresql-${PG_MAJOR}-pgaudit" \
		"postgresql-${PG_MAJOR}-pgvector" \
		"postgresql-${PG_MAJOR}-pg-failover-slots";

# Install barman-cloud
RUN set -xe; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		curl \
		python3-pip \
		python3-psycopg2 \
		python3-setuptools \
	; \
	pip3 install --upgrade pip; \
# TODO: Remove --no-deps once https://github.com/pypa/pip/issues/9644 is solved
	pip3 install --no-deps -r requirements.txt; \
	rm -fr /tmp/* ; \
	rm -rf /var/lib/apt/lists/*;
	
# Change the uid of postgres to 26
RUN usermod -u 26 postgres && chown -R postgres:postgres /opt /var/lib/
USER 26

WORKDIR /opt

ARG PGEDGE_INSTALL_URL="https://pgedge-download.s3.amazonaws.com/REPO/install.py"
ARG PGV="16"
ENV PGV=${PGV}
ENV PGDATA="/opt/pgedge/data/pg${PGV}"
ENV PATH="/opt/pgedge/pg${PGV}/bin:/opt/pgedge:${PATH}"
ARG INIT_USERNAME="pgedge_init"
ARG INIT_DATABASE="pgedge_init"
ARG INIT_PASSWORD="U2D2GY7F"

RUN python3 -c "$(curl -fsSL ${PGEDGE_INSTALL_URL})"
RUN ./pgedge/ctl install pgedge -U ${INIT_USERNAME} -d ${INIT_DATABASE} -P ${INIT_PASSWORD} --pg ${PGV} -p 5432 && pg_ctl stop

ARG SHARED_BUFFERS="512MB"
ARG MAINTENANCE_WORK_MEM="128MB"
ARG EFFECTIVE_CACHE_SIZE="1024MB"
ARG LOG_DESTINATION="stderr"
ARG LOG_STATEMENT="ddl"
ARG PASSWORD_ENCRYPTION="md5"
RUN PGEDGE_CONF="${PGDATA}/postgresql.conf"; \
	PGEDGE_HBA="${PGDATA}/pg_hba.conf"; \
	sed -i "s/^#\?password_encryption.*/password_encryption = ${PASSWORD_ENCRYPTION}/g" ${PGEDGE_CONF} \
	&& sed -i "s/^#\?shared_buffers.*/shared_buffers = ${SHARED_BUFFERS}/g" ${PGEDGE_CONF} \
	&& sed -i "s/^#\?maintenance_work_mem.*/maintenance_work_mem = ${MAINTENANCE_WORK_MEM}/g" ${PGEDGE_CONF} \
	&& sed -i "s/^#\?effective_cache_size.*/effective_cache_size = ${EFFECTIVE_CACHE_SIZE}/g" ${PGEDGE_CONF} \
	&& sed -i "s/^#\?log_destination.*/log_destination = '${LOG_DESTINATION}'/g" ${PGEDGE_CONF} \
	&& sed -i "s/^#\?log_statement.*/log_statement = '${LOG_STATEMENT}'/g" ${PGEDGE_CONF} \
	&& sed -i "s/^#\?logging_collector.*/logging_collector = 'off'/g" ${PGEDGE_CONF} \
	&& sed -i "s/^#\?log_connections.*/log_connections = 'off'/g" ${PGEDGE_CONF} \
	&& sed -i "s/^#\?log_disconnections.*/log_disconnections = 'off'/g" ${PGEDGE_CONF} \
	&& sed -i "s/scram-sha-256/md5/g" ${PGEDGE_HBA}

# Now it's safe to set PGDATA to the intended runtime value
ENV PGDATA="/var/lib/postgres/data"

RUN rm -f ~/.pgpass

# Place entrypoint scripts in the pgedge user's home directory
RUN mkdir -p /opt/scripts
COPY scripts/run-database.sh /opt/scripts/
COPY scripts/init-database.py /opt/scripts/
COPY config/db.json /opt/db.json

CMD ["sh", "-c", "sleep infinity"]