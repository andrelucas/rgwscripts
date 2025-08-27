#!/bin/bash

docker pull otel/opentelemetry-collector-contrib:0.114.0
go install github.com/open-telemetry/opentelemetry-collector-contrib/cmd/telemetrygen@latest
docker run \
  --name otel_collector_$LOGNAME \
  -p 127.0.0.1:4317:4317 \
  -p 127.0.0.1:4318:4318 \
  -p 127.0.0.1:55679:55679 \
  --rm \
  otel/opentelemetry-collector-contrib:0.114.0 \
  2>&1 | tee collector-output.txt # Optionally tee output for easier search later

