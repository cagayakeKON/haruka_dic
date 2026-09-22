#!/bin/sh
# This one-shot container receives only local development provisioning files.
set -eu
root_password="$(cat /provision/config/root_password)"
mc alias set local http://minio:9000 haruka_local_root "$root_password" >/dev/null
for environment in dev test; do
  if [ "$environment" = dev ]; then bucket=haruka-local-dev; else bucket=haruka-test-integration; fi
  access_key="$(cat "/provision/config/${environment}_access_key")"
  secret_key="$(cat "/provision/config/${environment}_secret_key")"
  mc mb --ignore-existing "local/$bucket" >/dev/null
  mc anonymous set none "local/$bucket" >/dev/null
  if ! mc admin user info local "$access_key" >/dev/null 2>&1; then
    mc admin user add local "$access_key" "$secret_key" >/dev/null
  fi
  mc admin policy create local "haruka-local-$environment" "/provision/config/$environment-policy.json" >/dev/null
  mc admin policy attach local "haruka-local-$environment" --user "$access_key" >/dev/null
done
printf '%s\n' 'Haruka private buckets and scoped application users provisioned.'
