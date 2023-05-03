#!/bin/bash
docker-compose \
  -f docker-compose.yml \
  -f geoip/docker-compose.geoip.yml \
  up -d
