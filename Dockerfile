FROM sandlerr/ruby:2.2.2

RUN mkdir /app
WORKDIR /app

ADD Gemfile /app/Gemfile
ADD Gemfile.lock /app/Gemfile.lock
ADD vendor/cache /app/vendor/cache
ADD bin /app/bin
ADD lib /app/lib

RUN cd /app && bundle install --quiet --local --jobs 4

CMD bundle exec bin/secrets
