FROM ruby:2.7-bullseye
# Debian 11 has moved to the archive mirrors
RUN sed -i 's|deb.debian.org|archive.debian.org|g; s|security.debian.org|archive.debian.org|g; /bullseye-updates/d' /etc/apt/sources.list 2>/dev/null || true \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && apt-get install -y --no-install-recommends libpq-dev postgresql-server-dev-13 python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*
# DuckDB reads Overture Maps places for a player's area while the app runs (tools/fetch_overture.py)
RUN pip3 install --no-cache-dir duckdb==1.4.5 \
    && python3 -c "import duckdb; duckdb.connect().execute('INSTALL httpfs')"
# JavaScript runtime for compiling CoffeeScript (ExecJS)
COPY --from=node:16-bullseye-slim /usr/local/bin/node /usr/local/bin/node
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN gem install bundler:1.17.2 && bundle install --jobs 4
COPY . .
# Compile CoffeeScript at build time (fast first page load). Build with
# PRECOMPILE_JS=0 to skip it, so development-mode live compiling still works.
ARG PRECOMPILE_JS=1
RUN if [ "$PRECOMPILE_JS" = "1" ]; then bundle exec ruby lib/precompile_coffee.rb; fi
CMD ["sh", "-c", "bundle exec puma -w 0 -t 1:5 -p ${PORT:-10000} -e ${RACK_ENV:-production} config.ru"]
