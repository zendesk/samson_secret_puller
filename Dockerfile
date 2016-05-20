FROM sandlerr/ruby:2.2.2

RUN mkdir /app
WORKDIR /app

ADD Gemfile /app/Gemfile
ADD Gemfile.lock /app/Gemfile.lock
ADD vendor /app/vendor
ADD bin /app/bin

RUN cd /app && bundle install --quiet --local --jobs 4 || bundle check

ADD . /app

CMD bundle exec bin/secrets
