# syntax=docker/dockerfile:1.7
# check=error=true
FROM alpine:edge

ARG ZVM_VERSION=v0.8.20
ARG ZIG_VERSION=0.16.0

ENV GOBIN=/usr/local/bin
ENV PATH=/root/.zvm/bin:${PATH}

RUN apk add --no-cache build-base libgit2-dev go \
    && go install github.com/tristanisham/zvm@${ZVM_VERSION} \
    && zvm install ${ZIG_VERSION} \
    && zvm use ${ZIG_VERSION}

WORKDIR /app
COPY . .
RUN zig build

CMD [ "/app/zig-out/bin/ishi", "init", \
    "--target", "vdb", "--git", \
    "--limit", "100" ]
