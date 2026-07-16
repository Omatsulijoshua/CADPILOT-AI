#!/bin/sh
set -eu

: "${DATABASE_URL:?DATABASE_URL must be configured}"
: "${JWT_ACCESS_SECRET:?JWT_ACCESS_SECRET must be configured}"
: "${JWT_REFRESH_SECRET:?JWT_REFRESH_SECRET must be configured}"

exec "$@"
