# FROM ruby:2.6.2-alpine
FROM ruby@sha256:9fee6680610546f3f50e3d00e63ca73b53f6bc04a2b0ed4cd70b126956358e4e

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
