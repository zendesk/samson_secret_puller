# ruby:2.3.1-alpine
FROM ruby@sha256:8d5ca285f1a24ed333aad70cfa54157f77ff130f810c91d5664e98a093d751bc

RUN apk add --update --no-cache \
  bash curl elixir

RUN mkdir /app
WORKDIR /app

# bundle
ADD Gemfile .
ADD Gemfile.lock .
ADD vendor/cache /app/vendor/cache
RUN cd /app && bundle install --quiet --local --jobs 4

# app
ADD bin /app/bin
ADD lib /app/lib

# test
ADD Rakefile .
ADD .travis.yml .
ADD .rubocop.yml .
ADD test /app/test

# clients
ADD gem gem
ADD elixir elixir

CMD bundle exec bin/secrets
