# syntax=docker/dockerfile:1
FROM ruby:4.0.1-slim-bookworm

ENV APP_HOME=/workspace \
    RUN_MODE=container

WORKDIR /app

COPY . .

RUN bundle config set without 'development test' \
    && bundle install

# Provide APP_START_CMD via --env-file.
CMD ["bash", "scripts/build.sh"]
