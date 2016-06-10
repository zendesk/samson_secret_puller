# ruby:2.3.1-alpine
FROM ruby@sha256:4a8993318e41d8814ea6a30ca2eccf36078b59ed2ab2f9cf2b4be81331d8caa3

RUN apk add --update --no-cache \
  bash

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

CMD mkdir /secrets/bin ;; cp /app/bin/wait_for_it /secrets/bin && bundle exec bin/secrets
