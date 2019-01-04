#FROM ruby:2.5.3-alpine
FROM ruby@sha256:1780a51835cad01073b306d78ec55fe095ad29b66105a9efbee48921f5a71800

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

CMD ["bundle", "exec", "bin/secrets"]
