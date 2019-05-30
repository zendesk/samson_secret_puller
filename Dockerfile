# FROM ruby:2.6.3-alpine
FROM ruby@sha256:2749716577d81ef71bc487dfd35962bb067ca11a1b9d6d6d81f8ff7cc3e03f60

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
