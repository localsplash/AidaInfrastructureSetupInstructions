#!/bin/bash
# Runs only on a NEW aida-dev MySQL volume through the official image entrypoint.
# It creates Aida-owned stores, never platform_db, echo_db, or the vendor PBX DB.
(
set -eu

for variable in AIDA_RUNTIME_DB_PASSWORD AIDA_ADMIN_DB_PASSWORD AIDA_RUNTIME_READER_DB_PASSWORD; do
  value="${!variable:-}"
  if [[ ! "$value" =~ ^[a-fA-F0-9]{64}$ ]]; then
    echo "Invalid $variable: use 64 independently generated hex characters" >&2
    exit 1
  fi
done

# mysql entrypoint sources non-executable .sh scripts and provides docker_process_sql.
# Fixed identifiers and validated hex passwords avoid SQL/URL quoting ambiguity.
docker_process_sql <<SQL
CREATE DATABASE IF NOT EXISTS aidacalls_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS aida_admin_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'aida_runtime'@'%' IDENTIFIED BY '${AIDA_RUNTIME_DB_PASSWORD}';
CREATE USER 'aida_admin'@'%' IDENTIFIED BY '${AIDA_ADMIN_DB_PASSWORD}';
CREATE USER 'aida_runtime_reader'@'%' IDENTIFIED BY '${AIDA_RUNTIME_READER_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON aidacalls_db.* TO 'aida_runtime'@'%';
GRANT ALL PRIVILEGES ON aida_admin_db.* TO 'aida_admin'@'%';
GRANT SELECT ON aidacalls_db.* TO 'aida_runtime_reader'@'%';
SQL
)
