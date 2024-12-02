#################
# Builder stage #
#################
FROM alpine:3.20 AS builder

RUN apk add --no-cache gcc ldc dub musl-dev zlib-dev openssl-dev
ENV DC=ldc2

WORKDIR /build

# Fetch and build dependendecies
COPY dub.sdl dub.selections.json /build/
RUN mkdir /build/source && echo "void main(){}" > /build/source/main.d
RUN dub build --build=release
RUN rm -rf /build/source

# Build project
COPY source/ /build/source/
COPY views/ /build/views/
RUN dub build --build=release

################
# Runner stage #
################
FROM alpine:3.20

RUN apk add --no-cache ldc-runtime zlib libssl3

WORKDIR /app
COPY --from=builder /build/d-status /app/
COPY public/ /app/public
COPY config.json /app/

RUN addgroup -S web && adduser -S web -G web

EXPOSE 8080

CMD ["./d-status", "--user=web", "--group=web"]
