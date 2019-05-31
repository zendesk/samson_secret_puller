FROM ruby:2.6-alpine

WORKDIR /app

# bundle
COPY .ruby-version Gemfile Gemfile.lock ./
RUN bundle install --quiet --jobs 4 --without test

# code
COPY bin /app/bin
COPY lib /app/lib

# run as unpriviledged user
RUN adduser -S app -u 1000
USER 1000

CMD ["bundle", "exec", "bin/secrets"]
