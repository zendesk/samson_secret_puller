# ruby:2.4.1-alpine
FROM ruby@sha256:502ebe671776e96520a01cecad973a1a78a749f6408a48f840bada7a306bc433

RUN apk add --update --no-cache \
  bash curl elixir erlang-crypto

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

RUN mix local.hex --force

CMD bundle exec bin/secrets
