FROM ruby:2.7-bullseye
# Debian 11 has moved to the archive mirrors
RUN sed -i 's|deb.debian.org|archive.debian.org|g; s|security.debian.org|archive.debian.org|g; /bullseye-updates/d' /etc/apt/sources.list 2>/dev/null || true \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && apt-get install -y --no-install-recommends libpq-dev postgresql-server-dev-13 \
    && rm -rf /var/lib/apt/lists/*
# JavaScript runtime for compiling CoffeeScript (ExecJS)
COPY --from=node:16-bullseye-slim /usr/local/bin/node /usr/local/bin/node
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN gem install bundler:1.17.2 && bundle install --jobs 4
COPY . .
RUN bundle exec ruby lib/precompile_coffee.rb
CMD ["sh", "-c", "bundle exec puma -w 0 -t 1:5 -p ${PORT:-10000} -e ${RACK_ENV:-production} config.ru"]
