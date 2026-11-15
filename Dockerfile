FROM ruby:2.7
RUN apt-get update && apt-get install -y --no-install-recommends libpq-dev nodejs \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without development && bundle install
COPY . .
ENV RACK_ENV=production
CMD bundle exec puma -p ${PORT:-10000} -e production config.ru
