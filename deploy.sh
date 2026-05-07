__apta_active_deploy_runs() {
	local workflow="$1"
	local active_window_seconds="${APTA_DEPLOY_ACTIVE_WINDOW_SECONDS:-21600}"

	case "$active_window_seconds" in
		''|*[!0-9]*)
			active_window_seconds="21600"
			;;
	esac

	gh run list \
		--repo vix-tecnologia/apta-deploy \
		--workflow "$workflow" \
		--json status,updatedAt \
		--jq "[
			.[]
			| select(
				.status == \"in_progress\"
				or (
					(.status == \"queued\" or .status == \"waiting\" or .status == \"pending\" or .status == \"requested\")
					and .updatedAt != null
					and ((now - (.updatedAt | fromdateiso8601)) < $active_window_seconds)
				)
			)
		] | length" 2>/dev/null
}

__apta_run_deploy_workflows() {
	local environment="$1"
	local ref_input="$2"
	local ref_value="$3"
	local notify="$4"
	local db_migrations="$5"
	local deploy_front="$6"
	local deploy_back="$7"

	local workflow active_runs

	if [ "$deploy_front" = "true" ]; then
		workflow="frontend-${environment}-deploy.yml"
		active_runs=$(__apta_active_deploy_runs "$workflow")
		if [ "${active_runs:-0}" -gt 0 ]; then
			printf 'Warning: %s is already running. Skipping.\n' "$workflow" >&2
		else
			gh workflow run "$workflow" \
				--repo vix-tecnologia/apta-deploy \
				--ref main \
				-f notify="$notify" \
				-f "$ref_input=$ref_value"
		fi
	fi

	if [ "$deploy_back" = "true" ]; then
		workflow="backend-${environment}-deploy.yml"
		active_runs=$(__apta_active_deploy_runs "$workflow")
		if [ "${active_runs:-0}" -gt 0 ]; then
			printf 'Warning: %s is already running. Skipping.\n' "$workflow" >&2
		else
			gh workflow run "$workflow" \
				--repo vix-tecnologia/apta-deploy \
				--ref main \
				-f notify="$notify" \
				-f db-migrations="$db_migrations" \
				-f "$ref_input=$ref_value"
		fi
	fi
}

dev-deploy() {
	local notify="true"
	local db_migrations="true"
	local branch="develop"
	local deploy_front="false"
	local deploy_back="false"
	local explicit_target="false"

	while [ "$#" -gt 0 ]; do
		case "$1" in
			--front)
				deploy_front="true"
				explicit_target="true"
				;;
			--back)
				deploy_back="true"
				explicit_target="true"
				;;
			--notify=*)
				notify="${1#*=}"
				;;
			--notify)
				shift
				if [ -z "$1" ]; then
					printf '%s\n' "Missing value for --notify." >&2
					return 2
				fi
				notify="$1"
				;;
			--db-migrations=*)
				db_migrations="${1#*=}"
				;;
			--db-migrations)
				shift
				if [ -z "$1" ]; then
					printf '%s\n' "Missing value for --db-migrations." >&2
					return 2
				fi
				db_migrations="$1"
				;;
			--branch=*)
				branch="${1#*=}"
				;;
			--branch)
				shift
				if [ -z "$1" ]; then
					printf '%s\n' "Missing value for --branch." >&2
					return 2
				fi
				branch="$1"
				;;
			--help|-h)
				printf '%s\n' \
					"Usage: dev-deploy [--front] [--back] [--notify=true|false] [--db-migrations=true|false] [--branch=name]" \
					"" \
					"Defaults: notify=true db-migrations=true branch=develop" \
					"Without --front or --back, both frontend and backend deploys are triggered."
				return 0
				;;
			--*)
				printf 'Unknown option: %s\n' "$1" >&2
				return 2
				;;
			*)
				printf 'Unexpected argument: %s\n' "$1" >&2
				return 2
				;;
		esac

		shift
	done

	if [ "$explicit_target" = "false" ]; then
		deploy_front="true"
		deploy_back="true"
	fi

	__apta_run_deploy_workflows "dev" "branch" "$branch" "$notify" "$db_migrations" "$deploy_front" "$deploy_back"
}

stage-deploy() {
	local notify="true"
	local db_migrations="true"
	local version=""
	local branch=""
	local deploy_front="false"
	local deploy_back="false"
	local explicit_target="false"

	while [ "$#" -gt 0 ]; do
		case "$1" in
			--front)
				deploy_front="true"
				explicit_target="true"
				;;
			--back)
				deploy_back="true"
				explicit_target="true"
				;;
			--notify=*)
				notify="${1#*=}"
				;;
			--notify)
				shift
				if [ -z "$1" ]; then
					printf '%s\n' "Missing value for --notify." >&2
					return 2
				fi
				notify="$1"
				;;
			--db-migrations=*)
				db_migrations="${1#*=}"
				;;
			--db-migrations)
				shift
				if [ -z "$1" ]; then
					printf '%s\n' "Missing value for --db-migrations." >&2
					return 2
				fi
				db_migrations="$1"
				;;
			--version=*)
				version="${1#*=}"
				;;
			--version)
				shift
				if [ -z "$1" ]; then
					printf '%s\n' "Missing value for --version." >&2
					return 2
				fi
				version="$1"
				;;
			--help|-h)
				printf '%s\n' \
					"Usage: stage-deploy --version=1.35 [--front] [--back] [--notify=true|false] [--db-migrations=true|false]" \
					"       stage-deploy 1.35 [--front] [--back] [--notify=true|false] [--db-migrations=true|false]" \
					"" \
					"Deploys branch release/<version>." \
					"Without --front or --back, both frontend and backend deploys are triggered."
				return 0
				;;
			--*)
				printf 'Unknown option: %s\n' "$1" >&2
				return 2
				;;
			*)
				if [ -n "$version" ]; then
					printf 'Unexpected argument: %s\n' "$1" >&2
					return 2
				fi
				version="$1"
				;;
		esac

		shift
	done

	if [ -z "$version" ]; then
		printf '%s\n' "Missing required version. Example: stage-deploy --version=1.35" >&2
		return 2
	fi

	if [ "$explicit_target" = "false" ]; then
		deploy_front="true"
		deploy_back="true"
	fi

	branch="release/$version"
	__apta_run_deploy_workflows "stage" "branch" "$branch" "$notify" "$db_migrations" "$deploy_front" "$deploy_back"
}

prod-deploy() {
	local notify="true"
	local db_migrations="true"
	local tag=""
	local deploy_front="false"
	local deploy_back="false"
	local explicit_target="false"

	while [ "$#" -gt 0 ]; do
		case "$1" in
			--front)
				deploy_front="true"
				explicit_target="true"
				;;
			--back)
				deploy_back="true"
				explicit_target="true"
				;;
			--notify=*)
				notify="${1#*=}"
				;;
			--notify)
				shift
				if [ -z "$1" ]; then
					printf '%s\n' "Missing value for --notify." >&2
					return 2
				fi
				notify="$1"
				;;
			--db-migrations=*)
				db_migrations="${1#*=}"
				;;
			--db-migrations)
				shift
				if [ -z "$1" ]; then
					printf '%s\n' "Missing value for --db-migrations." >&2
					return 2
				fi
				db_migrations="$1"
				;;
			--tag=*)
				tag="${1#*=}"
				;;
			--tag)
				shift
				if [ -z "$1" ]; then
					printf '%s\n' "Missing value for --tag." >&2
					return 2
				fi
				tag="$1"
				;;
			--help|-h)
				printf '%s\n' \
					"Usage: prod-deploy --tag=v1.35.0 [--front] [--back] [--notify=true|false] [--db-migrations=true|false]" \
					"       prod-deploy v1.35.0 [--front] [--back] [--notify=true|false] [--db-migrations=true|false]" \
					"" \
					"Requires --front or --back."
				return 0
				;;
			--*)
				printf 'Unknown option: %s\n' "$1" >&2
				return 2
				;;
			*)
				if [ -n "$tag" ]; then
					printf 'Unexpected argument: %s\n' "$1" >&2
					return 2
				fi
				tag="$1"
				;;
		esac

		shift
	done

	if [ -z "$tag" ]; then
		printf '%s\n' "Missing required tag. Example: prod-deploy --tag=v1.35.0" >&2
		return 2
	fi

	if [ "$explicit_target" = "false" ]; then
		printf '%s\n' "Missing required target. Use --front or --back." >&2
		return 2
	fi

	__apta_run_deploy_workflows "prod" "tag" "$tag" "$notify" "$db_migrations" "$deploy_front" "$deploy_back"
}
