FROM sandlerr/ruby:2.2.2

RUN mkdir /app
WORKDIR /app

ADD Gemfile /app/Gemfile
ADD Gemfile.lock /app/Gemfile.lock
ADD vendor /app/vendor
ADD bin /app/bin

RUN cd /app && bundle install --quiet --local --jobs 4 || bundle check

ADD . /app

#EXPOSE 4242
#CMD bundle exec rackup --port 4242 --host 0.0.0.0
CMD bundle exec bin/secrets
