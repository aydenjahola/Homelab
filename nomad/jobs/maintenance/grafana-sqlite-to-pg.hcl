# One-off: copy Grafana's data from the old SQLite file into the standalone Postgres (grafana-db).
# Runbook: docs/embedded-db-migrations.md. Run ONLY while the grafana app group is scaled to 0 and
# after Grafana has created its schema in Postgres once. The SQLite source is mounted read-only and
# copied into the alloc dir first, so the original file is never written.
#
#   prepare (prestart): refuse if grafana is running or the schema is missing; copy + sanitize SQLite
#   load    (main)    : pgloader data only, truncate, reset sequences (ids preserved)
#   verify  (poststop): per-table row counts SQLite == Postgres, non-zero exit on mismatch
job "grafana-sqlite-to-pg" {
  datacenters = ["dc1"]
  type        = "batch"

  group "migrate" {
    count = 1

    restart {
      attempts = 0
      mode     = "fail"
    }

    reschedule {
      attempts  = 0
      unlimited = false
    }

    task "prepare" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image   = "postgres:17-alpine"
        command = "/bin/sh"
        args    = ["/local/prepare.sh"]

        volumes = [
          "/storage/nomad/grafana/grafana:/src:ro",
        ]
      }

      template {
        destination          = "secrets/db.env"
        env                  = true
        perms                = "0600"
        change_mode          = "noop"
        error_on_missing_key = true
        data                 = <<EOH
PGUSER     = {{ key "grafana/db/user" }}
PGPASSWORD = {{ key "grafana/db/password" }}
PGDATABASE = {{ key "grafana/db/name" }}
{{- range service "grafana-db" }}
PGHOST = {{ .Address }}
PGPORT = {{ .Port }}
{{- end }}
APP_INSTANCES = "{{ range service "grafana|any" }}{{ .Node }} {{ end }}"
EOH
      }

      template {
        destination = "local/prepare.sh"
        change_mode = "noop"
        data        = <<EOH
set -eu
: "$PGHOST" "$PGPORT"
if [ -n "$(echo $APP_INSTANCES)" ]; then
  echo "ABORT: grafana service still registered on: $APP_INSTANCES (scale the grafana group to 0 first)"; exit 1
fi
apk add --no-cache sqlite >/dev/null

n=$(psql -tAc "select count(*) from migration_log" 2>/dev/null || echo 0)
if [ "$n" -lt 100 ]; then
  echo "ABORT: Grafana schema not found in Postgres (migration_log=$n). Start grafana once against the empty DB first."; exit 1
fi
echo "==> Postgres schema present (migration_log=$n)"

mkdir -p /alloc/data/src
cp /src/grafana.db /alloc/data/src/
for f in /src/grafana.db-wal /src/grafana.db-journal; do [ -f "$f" ] && cp "$f" /alloc/data/src/; done
sqlite3 /alloc/data/src/grafana.db "PRAGMA integrity_check" | tee /dev/stderr | grep -qx ok
rm -f /alloc/data/grafana.db
sqlite3 /alloc/data/src/grafana.db ".backup '/alloc/data/grafana.db'"
DB=/alloc/data/grafana.db

# Go time.String() values ("... +0000 UTC m=+5.96") are not valid Postgres timestamps; keep the first 19 chars.
for t in $(sqlite3 $DB "select name from sqlite_master where type='table' and name not like 'sqlite_%'"); do
  for c in $(sqlite3 $DB "select name from pragma_table_info('$t')"); do
    k=$(sqlite3 $DB "select count(*) from \"$t\" where typeof(\"$c\")='text' and \"$c\" like '% m=+%'")
    if [ "$k" != 0 ]; then
      echo "==> sanitize $t.$c ($k rows)"
      sqlite3 $DB "update \"$t\" set \"$c\" = substr(\"$c\", 1, 19) where typeof(\"$c\")='text' and \"$c\" like '% m=+%'"
    fi
  done
done

echo "==> SQLite baseline (non-empty tables):"
for t in $(sqlite3 $DB "select name from sqlite_master where type='table' and name not like 'sqlite_%' order by 1"); do
  k=$(sqlite3 $DB "select count(*) from \"$t\"")
  [ "$k" != 0 ] && echo "  $t $k"
done
echo "==> SQLite dashboards/folders in unified storage:"
sqlite3 $DB "select resource, count(*) from resource where resource in ('dashboards','folders') group by 1"
EOH
      }

      resources {
        cpu        = 200
        memory     = 128
        memory_max = 256
      }
    }

    task "load" {
      driver = "docker"

      config {
        # amd64 only upstream; matches the cluster
        image   = "ghcr.io/dimitri/pgloader:3.6.9"
        command = "/bin/sh"
        # a missing source would make sqlite open an empty db and "succeed" with 0 rows
        args = ["-c", "test -s /alloc/data/grafana.db && exec pgloader --no-ssl-cert-verification /local/grafana.load"]
      }

      template {
        destination          = "secrets/db.env"
        env                  = true
        perms                = "0600"
        change_mode          = "noop"
        error_on_missing_key = true
        data                 = <<EOH
PGUSER     = {{ key "grafana/db/user" }}
PGPASSWORD = {{ key "grafana/db/password" }}
PGDATABASE = {{ key "grafana/db/name" }}
{{- range service "grafana-db" }}
PGHOST = {{ .Address }}
PGPORT = {{ .Port }}
{{- end }}
EOH
      }

      # {{...}} is pgloader's own mustache templating (filled from the env above), so this
      # template uses [[ ]] delimiters to leave it alone. No password is written to the file.
      template {
        destination     = "local/grafana.load"
        change_mode     = "noop"
        left_delimiter  = "[["
        right_delimiter = "]]"
        data            = <<EOH
LOAD DATABASE
  FROM sqlite:///alloc/data/grafana.db
  INTO postgresql://{{PGUSER}}@{{PGHOST}}:{{PGPORT}}/{{PGDATABASE}}

WITH data only, truncate, reset sequences, on error stop, prefetch rows = 1000, batch rows = 1000

SET work_mem to '64MB', maintenance_work_mem to '128MB'

-- *migration_log tables stay as Grafana wrote them for Postgres; the 3 legacy tables do not exist in the PG schema.
EXCLUDING TABLE NAMES LIKE 'migration_log', 'resource_migration_log', 'secret_migration_log',
                           'unifiedstorage_migration_log', 'entity_event', 'playlist', 'playlist_item',
                           'sqlite_sequence', 'sqlite_stat1';
EOH
      }

      resources {
        cpu        = 500
        memory     = 512
        memory_max = 1024
      }
    }

    task "verify" {
      driver = "docker"

      lifecycle {
        hook = "poststop"
      }

      config {
        image   = "postgres:17-alpine"
        command = "/bin/sh"
        args    = ["/local/verify.sh"]
      }

      template {
        destination          = "secrets/db.env"
        env                  = true
        perms                = "0600"
        change_mode          = "noop"
        error_on_missing_key = true
        data                 = <<EOH
PGUSER     = {{ key "grafana/db/user" }}
PGPASSWORD = {{ key "grafana/db/password" }}
PGDATABASE = {{ key "grafana/db/name" }}
{{- range service "grafana-db" }}
PGHOST = {{ .Address }}
PGPORT = {{ .Port }}
{{- end }}
EOH
      }

      template {
        destination = "local/verify.sh"
        change_mode = "noop"
        data        = <<EOH
set -eu
DB=/alloc/data/grafana.db
[ -f "$DB" ] || { echo "no prepared SQLite copy, nothing to verify"; exit 1; }
apk add --no-cache sqlite >/dev/null
bad=0
for t in $(sqlite3 $DB "select name from sqlite_master where type='table' and name not like 'sqlite_%' and name not like '%migration_log' and name not in ('entity_event','playlist','playlist_item') order by 1"); do
  s=$(sqlite3 $DB "select count(*) from \"$t\"")
  p=$(psql -tAc "select count(*) from \"$t\"")
  if [ "$s" != "$p" ]; then bad=1; echo "MISMATCH $t sqlite=$s pg=$p"; elif [ "$s" != 0 ]; then echo "  ok $t $s"; fi
done
echo "==> Postgres dashboards/folders in unified storage:"
psql -tAc "select resource, count(*) from resource where resource in ('dashboards','folders') group by 1"
if [ $bad = 0 ]; then echo "==> VERIFY OK: all table counts match"; else echo "==> VERIFY FAILED"; fi
rm -rf /alloc/data/src /alloc/data/grafana.db
exit $bad
EOH
      }

      resources {
        cpu        = 200
        memory     = 128
        memory_max = 256
      }
    }
  }
}
