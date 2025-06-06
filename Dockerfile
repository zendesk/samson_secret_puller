FROM ruby:3.2-alpine

WORKDIR /app

# bundle
ENV SKIP_DEV_GEMS true
COPY .ruby-version Gemfile Gemfile.lock ./
RUN bundle install --quiet --jobs 4

# code
COPY bin /app/bin
COPY lib /app/lib

# run as unpriviledged user
RUN adduser -S app -u 1000
USER 1000

CMD ["bundle", "exec", "bin/secrets"]
