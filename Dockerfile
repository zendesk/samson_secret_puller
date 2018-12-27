#FROM ruby:2.5.3-alpine
FROM ruby@sha256:1780a51835cad01073b306d78ec55fe095ad29b66105a9efbee48921f5a71800

RUN apk add --update --no-cache \
  bash openssl curl && \
  wget -O /usr/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v1.2.0/dumb-init_1.2.0_amd64 && \
  chmod +x /usr/bin/dumb-init

WORKDIR /app

# bundle
COPY .ruby-version Gemfile Gemfile.lock ./
RUN bundle install --quiet --jobs 4

# code
COPY bin /app/bin
COPY lib /app/lib

# run as unpriviledged user
RUN adduser -S app -u 1000
USER 1000

CMD ["/usr/bin/dumb-init", "--", "bundle", "exec", "bin/secrets"]
