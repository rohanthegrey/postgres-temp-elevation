# Custom PostgreSQL image with pg_cron extension
FROM postgres:15

# Install pg_cron extension
RUN apt-get update && apt-get install -y \
    postgresql-15-cron \
    && rm -rf /var/lib/apt/lists/*

# Add pg_cron to shared_preload_libraries in postgresql.conf
RUN echo "shared_preload_libraries = 'pg_cron'" >> /usr/share/postgresql/postgresql.conf.sample
RUN echo "cron.database_name = 'testdb'" >> /usr/share/postgresql/postgresql.conf.sample
