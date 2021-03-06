## VT building image

FROM clojure:alpine AS vt

WORKDIR /app/vt

COPY vt/project.clj /app/vt/
COPY vt/src /app/vt/src
COPY vt/resources /app/vt/resources
RUN lein deps
RUN lein cljsbuild once main

## Release building image

FROM elixir:1.7.3-alpine AS builder

ARG MIX_ENV=prod

WORKDIR /opt/app

RUN apk upgrade && \
  apk add \
    nodejs \
    npm \
    build-base && \
  mix local.rebar --force && \
  mix local.hex --force

COPY mix.* ./
RUN mix do deps.get --only prod, deps.compile

COPY assets/ assets/
RUN cd assets && \
  npm install && \
  npm run deploy

RUN mix phx.digest

COPY config/*.exs config/
COPY lib lib/
COPY priv priv/
COPY rel rel/
RUN mix compile

COPY --from=vt /app/vt/main.js priv/vt/
COPY vt/liner.js priv/vt/

RUN  mix release --verbose && \
  mkdir -p /opt/built && \
  cd /opt/built && \
  tar -xzf /opt/app/_build/${MIX_ENV}/rel/asciinema/releases/0.0.1/asciinema.tar.gz

# Final image

FROM alpine:3.8

RUN apk add --no-cache \
  bash \
  librsvg \
  ttf-dejavu \
  pngquant \
  nodejs

WORKDIR /opt/app

COPY --from=builder /opt/built .
COPY config/custom.exs.sample /opt/app/etc/custom.exs
COPY .iex.exs .
COPY docker/bin/ bin/

ENV PORT 4000
ENV DATABASE_URL "postgresql://postgres@postgres/postgres"
ENV REDIS_URL "redis://redis:6379"
ENV RSVG_FONT_FAMILY "Dejavu Sans Mono"
ENV PATH "/opt/app/bin:${PATH}"

VOLUME /opt/app/uploads
VOLUME /opt/app/cache

CMD trap 'exit' INT; /opt/app/bin/asciinema foreground

EXPOSE 4000
