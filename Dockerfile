# ruby:2.4.2-alpine
FROM ruby@sha256:6b85a95c42eaf84f46884c82376aa653b343a0bd81ce3350dea2c56e0b15dcd6

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
