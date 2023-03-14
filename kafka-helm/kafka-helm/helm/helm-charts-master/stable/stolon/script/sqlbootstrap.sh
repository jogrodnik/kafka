#!/usr/bin/env bash
set -Eeo pipefail

if [ ! -e = $STOLON_DATA/postgres ]; then
	mkdir -p "$STOLON_DATA/postgres"
	chown -R "$STKEEPER_PG_SU_USERNAME" "$STOLON_DATA/postgres" 2>/dev/null || :
	chmod 700 "$STOLON_DATA/postgres" 2>/dev/null || :

		PGUSER="$STKEEPER_PG_SU_USERNAME" \
		pg_ctl -D "$STOLON_DATA" \
			-o "-c listen_addresses='$(hostname -i)'" \
			-w start

		export PGPASSWORD="$(cat $STKEEPER_PG_SU_PASSWORDFILE)"
		psql=( psql -v ON_ERROR_STOP=1 --username "$STKEEPER_PG_SU_USERNAME" -d postgres --no-password )

		echo
		for f in /docker-entrypoint-initdb.d/*; do
			case "$f" in
				*.sh)
					# https://github.com/docker-library/postgres/issues/450#issuecomment-393167936
					# https://github.com/docker-library/postgres/pull/452
					if [ -x "$f" ]; then
						echo "$0: running $f"
						"$f"
					else
						echo "$0: sourcing $f"
						. "$f"
					fi
					;;
				*.sql)    echo "$0: running $f"; "${psql[@]}" -f "$f"; echo ;;
				*.sql.gz) echo "$0: running $f"; gunzip -c "$f" | "${psql[@]}"; echo ;;
				*)        echo "$0: ignoring $f" ;;
			esac
			echo
		done

		PGUSER="${PGUSER:-$POSTGRES_USER}" \
		pg_ctl -D "$PGDATA" -m fast -w stop

		unset PGPASSWORD

		echo
		echo 'PostgreSQL init process complete; ready for start up.'
		echo
    exit 0
	fi
fi

# exec "$@"
