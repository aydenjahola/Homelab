# One-off: copy WatchYourLAN's hosts and history from the old SQLite scan.db into the standalone
# Postgres (watchyourlan-db). Runbook: docs/embedded-db-migrations.md. Run ONLY while the
# watchyourlan app group is scaled to 0 and after the app has created its tables in Postgres once.
# The SQLite dir is mounted read-only; scan.db and its WAL are copied into the alloc dir first.
#
# Tables (GORM AutoMigrate of models.Host, v2.1.4): now, history
#   "ID" bigserial, "NAME" "DNS" "IFACE" "IP" "MAC" "HW" "DATE" text, "KNOWN" "NOW" bigint
job "watchyourlan-sqlite-to-pg" {
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
          "/storage/nomad/watchyourlan/watchyourlan:/src:ro",
        ]
      }

      template {
        destination          = "secrets/db.env"
        env                  = true
        perms                = "0600"
        change_mode          = "noop"
        error_on_missing_key = true
        data                 = <<EOH
PGUSER     = {{ key "watchyourlan/db/user" }}
PGPASSWORD = {{ key "watchyourlan/db/password" }}
PGDATABASE = {{ key "watchyourlan/db/name" }}
{{- range service "watchyourlan-db" }}
PGHOST = {{ .Address }}
PGPORT = {{ .Port }}
{{- end }}
APP_INSTANCES = "{{ range service "watchyourlan|any" }}{{ .Node }} {{ end }}"
EOH
      }

      template {
        destination = "local/prepare.sh"
        change_mode = "noop"
        data        = <<EOH
set -eu
: "$PGHOST" "$PGPORT"
if [ -n "$(echo $APP_INSTANCES)" ]; then
  echo "ABORT: watchyourlan service still registered on: $APP_INSTANCES (scale the watchyourlan group to 0 first)"; exit 1
fi
apk add --no-cache sqlite >/dev/null

n=$(psql -tAc "select count(*) from information_schema.tables where table_schema='public' and table_name in ('now','history')" 2>/dev/null || echo 0)
if [ "$n" != 2 ]; then
  echo "ABORT: tables now/history not found in Postgres. Start watchyourlan once against the empty DB first."; exit 1
fi
echo "==> Postgres tables present"

mkdir -p /alloc/data/src
cp /src/scan.db /alloc/data/src/
# the WAL holds recent writes; -shm is rebuilt by sqlite and is not copied
[ -f /src/scan.db-wal ] && cp /src/scan.db-wal /alloc/data/src/
sqlite3 /alloc/data/src/scan.db "PRAGMA integrity_check" | tee /dev/stderr | grep -qx ok
rm -f /alloc/data/scan.db
sqlite3 /alloc/data/src/scan.db ".backup '/alloc/data/scan.db'"

echo "==> SQLite baseline:"
sqlite3 /alloc/data/scan.db "select 'now', count(*), sum(KNOWN), sum(NAME <> ''), max(ID) from now; select 'history', count(*), '', '', max(ID) from history" \
  | awk -F'|' '{ printf "  %s rows=%s known=%s named=%s max_id=%s\n", $1, $2, $3, $4, $5 }'
EOH
      }

      resources {
        cpu        = 100
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
        args = ["-c", "test -s /alloc/data/scan.db && exec pgloader --no-ssl-cert-verification /local/watchyourlan.load"]
      }

      template {
        destination          = "secrets/db.env"
        env                  = true
        perms                = "0600"
        change_mode          = "noop"
        error_on_missing_key = true
        data                 = <<EOH
PGUSER     = {{ key "watchyourlan/db/user" }}
PGPASSWORD = {{ key "watchyourlan/db/password" }}
PGDATABASE = {{ key "watchyourlan/db/name" }}
{{- range service "watchyourlan-db" }}
PGHOST = {{ .Address }}
PGPORT = {{ .Port }}
{{- end }}
EOH
      }

      # {{...}} is pgloader's own mustache templating (filled from the env above), so this
      # template uses [[ ]] delimiters to leave it alone. No password is written to the file.
      template {
        destination     = "local/watchyourlan.load"
        change_mode     = "noop"
        left_delimiter  = "[["
        right_delimiter = "]]"
        data            = <<EOH
LOAD DATABASE
  FROM sqlite:///alloc/data/scan.db
  INTO postgresql://{{PGUSER}}@{{PGHOST}}:{{PGPORT}}/{{PGDATABASE}}

-- columns are upper case ("ID", "MAC", ...), hence quote identifiers. pgloader 3.6.x "reset sequences"
-- double-quotes the already quoted "ID" and aborts, so sequences are reset in AFTER LOAD instead.
WITH data only, truncate, reset no sequences, quote identifiers, on error stop,
     prefetch rows = 10000, batch rows = 10000

INCLUDING ONLY TABLE NAMES LIKE 'now', 'history'

AFTER LOAD DO
  $$ select setval(pg_get_serial_sequence('now', 'ID'), coalesce((select max("ID") from now), 0) + 1, false); $$,
  $$ select setval(pg_get_serial_sequence('history', 'ID'), coalesce((select max("ID") from history), 0) + 1, false); $$;
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
PGUSER     = {{ key "watchyourlan/db/user" }}
PGPASSWORD = {{ key "watchyourlan/db/password" }}
PGDATABASE = {{ key "watchyourlan/db/name" }}
{{- range service "watchyourlan-db" }}
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
DB=/alloc/data/scan.db
[ -f "$DB" ] || { echo "no prepared SQLite copy, nothing to verify"; exit 1; }
apk add --no-cache sqlite >/dev/null
s=$(sqlite3 $DB "select (select count(*) from now)||'|'||(select coalesce(sum(KNOWN),0) from now)||'|'||(select sum(NAME <> '') from now)||'|'||(select count(*) from history)||'|'||(select coalesce(max(ID),0) + 1 from history)")
p=$(psql -tAc "select (select count(*) from now)||'|'||(select coalesce(sum(\"KNOWN\"),0) from now)||'|'||(select sum((\"NAME\" <> '')::int) from now)||'|'||(select count(*) from history)||'|'||(select last_value from \"history_ID_seq\")")
echo "  now_rows|known|named|history_rows|next_history_id"
echo "  sqlite:   $s"
echo "  postgres: $p"
rm -rf /alloc/data/src /alloc/data/scan.db
if [ "$s" = "$p" ]; then echo "==> VERIFY OK"; else echo "==> VERIFY FAILED"; exit 1; fi
EOH
      }

      resources {
        cpu        = 100
        memory     = 128
        memory_max = 256
      }
    }
  }
}
