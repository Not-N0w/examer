#!/bin/sh
cd "$(dirname "$0")"
. ../env/db.env

if [ "$1" = "-d" ]; then
    docker-compose down
    exit
fi

if [ "$1" = "-c" ]; then
    docker-compose down -v
fi

docker-compose up -d db

if [ "$1" = "-i" ]; then
    sleep 5
    for f in init.sql triggers.sql functions.sql indexes.sql; do
        docker-compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "$f"
    done
fi