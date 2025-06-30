FROM ruby:3.4.2

RUN apt-get update && apt-get install nodejs npm yarn -y --no-install-recommends

WORKDIR /abid
COPY . /abid

RUN yarn install
RUN bundle install

EXPOSE 4455
ENV RACK_ENV Production

ENTRYPOINT ["bundle", "exec", "rackup", "-p", "4455", "-o", "0.0.0.0"]
