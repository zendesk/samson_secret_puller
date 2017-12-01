# ruby:2.4.2-alpine
FROM ruby@sha256:6b85a95c42eaf84f46884c82376aa653b343a0bd81ce3350dea2c56e0b15dcd6

RUN apk add --update --no-cache \
  bash openssl curl elixir erlang-crypto && \
  mkdir /app && \
  wget -O /usr/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v1.2.0/dumb-init_1.2.0_amd64 && \
  chmod +x /usr/bin/dumb-init

WORKDIR /app

# bundle
COPY .ruby-version Gemfile Gemfile.lock ./
RUN cd /app && bundle install --quiet --jobs 4

# app
ADD bin /app/bin
ADD lib /app/lib

# test
COPY Rakefile .travis.yml .rubocop.yml ./
ADD test /app/test

# clients
ADD gem gem
ADD elixir elixir

# tests need to write in elixir/_build
RUN chmod -R a+w elixir

RUN adduser -S app -u 1000
USER 1000

RUN mix local.hex --force

CMD ["/usr/bin/dumb-init", "--", "bundle", "exec", "bin/secrets"]
