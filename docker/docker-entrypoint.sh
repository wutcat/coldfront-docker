#!/bin/bash
# Runs on every start of the ColdFront Docker container

# Stop when an error occures
set -e

# Allows ColdFront to be run as non-root users
umask 002

# Load correct Python3 env
# shellcheck disable=SC1091
source /srv/coldfront/venv/bin/activate

# Try to connect to the DB
DB_WAIT_TIMEOUT=${DB_WAIT_TIMEOUT-3}
MAX_DB_WAIT_TIME=${MAX_DB_WAIT_TIME-30}
CUR_DB_WAIT_TIME=0
while [ "${CUR_DB_WAIT_TIME}" -lt "${MAX_DB_WAIT_TIME}" ]; do
  # Read and truncate connection error tracebacks to last line by default
  exec {psfd}< <(coldfront showmigrations 2>&1)
  read -rd '' DB_ERR <&$psfd || :
  exec {psfd}<&-
  wait $! && break
  if [ -n "$DB_WAIT_DEBUG" ]; then
    echo "$DB_ERR"
  else
    readarray -tn 0 DB_ERR_LINES <<<"$DB_ERR"
    echo "${DB_ERR_LINES[@]: -1}"
    echo "[ Use DB_WAIT_DEBUG=1 in coldfront.env to print full traceback for errors here ]"
  fi
  echo "⏳ Waiting on DB... (${CUR_DB_WAIT_TIME}s / ${MAX_DB_WAIT_TIME}s)"
  sleep "${DB_WAIT_TIMEOUT}"
  CUR_DB_WAIT_TIME=$((CUR_DB_WAIT_TIME + DB_WAIT_TIMEOUT))
done
if [ "${CUR_DB_WAIT_TIME}" -ge "${MAX_DB_WAIT_TIME}" ]; then
  echo "❌ Waited ${MAX_DB_WAIT_TIME}s or more for the DB to become ready."
  exit 1
fi
# Check if update is needed
if ! coldfront migrate --check >/dev/null 2>&1; then
  echo "⚙️ Applying database migrations"
  coldfront migrate --no-input
  echo "⚙️ Removing stale content types"
  coldfront remove_stale_contenttypes --no-input
  echo "⚙️ Removing expired user sessions"
  coldfront clearsessions
fi

# Import stuff
if [ -n "$CF_DO_INITIAL_SETUP" ]; then
  echo "⚙️ Importing field of science data"
  coldfront import_field_of_science_data
  echo "⚙️ Adding default grant options"
  coldfront add_default_grant_options
  echo "⚙️ Adding default project choices"
  coldfront add_default_project_choices
  echo "⚙️ Adding resource defaults"
  coldfront add_resource_defaults
  echo "⚙️ Adding allocation defaults"
  coldfront add_allocation_defaults
  echo "⚙️ Adding default publication sources"
  coldfront add_default_publication_sources
  echo "⚙️ Adding scheduled tasks"
  coldfront add_scheduled_tasks
fi

# Create Superuser if required
if [ "$SKIP_SUPERUSER" == "true" ]; then
  echo "↩️ Skip creating the superuser"
else
  if [ -z ${SUPERUSER_NAME+x} ]; then
    SUPERUSER_NAME='admin'
  fi
  if [ -z ${SUPERUSER_EMAIL+x} ]; then
    SUPERUSER_EMAIL='admin@example.com'
  fi
  if [ -f "/run/secrets/superuser_password" ]; then
    SUPERUSER_PASSWORD="$(</run/secrets/superuser_password)"
  elif [ -z ${SUPERUSER_PASSWORD+x} ]; then
    SUPERUSER_PASSWORD='admin'
  fi

  coldfront shell --interface python <<END
from django.contrib.auth.models import User
if not User.objects.filter(username='${SUPERUSER_NAME}'):
    u=User.objects.create_superuser('${SUPERUSER_NAME}', '${SUPERUSER_EMAIL}', '${SUPERUSER_PASSWORD}')
END

  echo "💡 Superuser Username: ${SUPERUSER_NAME}, E-Mail: ${SUPERUSER_EMAIL}"
fi

chown -R unit:unit /srv/coldfront

# If a SECRET_KEY wasn't supplied, generate one to prevent each unit instance from generating its own.
if [ -z "$SECRET_KEY" ]; then
  echo "Generating SECRET_KEY since one wasn't provided."
  export SECRET_KEY=`python3 << END
import secrets

charset = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*(-_=+)'
print(''.join(secrets.choice(charset) for _ in range(50)))
END`
fi

echo "✅ Initialisation is done."

# Launch whatever is passed by docker
# (i.e. the RUN instruction in the Dockerfile)
exec "$@"
