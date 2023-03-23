FROM ruby:2.7-alpine3.16

WORKDIR /app

# bundle
COPY .ruby-version Gemfile Gemfile.lock ./
RUN bundle config set without 'test' && \
    bundle install --quiet --jobs 4

# code
COPY bin /app/bin
COPY lib /app/lib

# run as unpriviledged user
RUN adduser -S app -u 1000
USER 1000

CMD ["bundle", "exec", "bin/secrets"]
