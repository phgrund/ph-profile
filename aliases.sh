project_root() {
	local dir="$PWD"

	while [ "$dir" != "/" ]; do
		if [ -f "$dir/composer.json" ] || [ -f "$dir/vendor/bin/sail" ]; then
			printf '%s\n' "$dir"
			return 0
		fi
		dir=$(dirname "$dir")
	done

	printf '%s\n' "$PWD"
}

project_uses_sail() {
	local root
	root=$(project_root)
	[ -f "$root/vendor/bin/sail" ]
}

project_php_required_version() {
	local root composer_line version
	root=$(project_root)

	[ -f "$root/composer.json" ] || return 1

	composer_line=$(grep -m 1 -E '"php"[[:space:]]*:[[:space:]]*"' "$root/composer.json") || return 1
	version=$(printf '%s\n' "$composer_line" | grep -oE '[0-9]+\.[0-9]+' | head -n 1)

	[ -n "$version" ] || return 1
	printf '%s\n' "$version"
}

project_php_binary() {
	local required_version major_version default_version candidate
	required_version=$(project_php_required_version 2>/dev/null)

	if [ -n "$required_version" ]; then
		for candidate in "php$required_version" "php${required_version/.}"; do
			if command -v "$candidate" >/dev/null 2>&1; then
				printf '%s\n' "$candidate"
				return 0
			fi
		done

		if command -v php >/dev/null 2>&1; then
			default_version=$(php -r 'echo PHP_MAJOR_VERSION, ".", PHP_MINOR_VERSION;' 2>/dev/null)
			if [ "$default_version" = "$required_version" ]; then
				printf '%s\n' "php"
				return 0
			fi
		fi

		major_version=${required_version%%.*}
		candidate="php$major_version"
		if command -v "$candidate" >/dev/null 2>&1; then
			printf '%s\n' "$candidate"
			return 0
		fi
	fi

	printf '%s\n' "php"
}

project_php() {
	local root php_bin
	root=$(project_root)

	if project_uses_sail; then
		if [ -f "$root/sail" ]; then
			(
				cd "$root" || exit 1
				bash sail php "$@"
			)
		else
			"$root/vendor/bin/sail" php "$@"
		fi
	else
		php_bin=$(project_php_binary)
		"$php_bin" "$@"
	fi
}

alias pp="project_php"
alias pa="project_php artisan"
alias cleardb="project_php artisan database:fresh --seed -y"
alias pas="project_php artisan serve"
alias pat="project_php artisan tinker"
alias pam="project_php artisan migrate"
alias pamr="project_php artisan migrate:rollback"
alias pasw="project_php artisan schedule:work"
alias paql="project_php artisan queue:listen"
alias dev-composer="COMPOSER=composer.dev.json composer"

sail() { [ -f sail ] && bash sail "$@" || bash vendor/bin/sail "$@"; }
alias sail-start="docker run --rm \
    -u '$(id -u):$(id -g)' \
    -v $(pwd):/var/www/html \
    -w /var/www/html \
    laravelsail/php80-composer:latest \
    composer install --ignore-platform-reqs"

alias pint="./vendor/bin/pint"
alias pintd="pint --dirty"

alias qd="quasar dev"
alias qb="quasar build"
alias qs="quasar serve --history dist/spa"
alias qc="quasar c"
alias qtst="yarn run test:e2e"
alias qbpwa="quasar build -m pwa"
alias qspwa="quasar serve --history dist/pwa"

alias mh="~/go/bin/MailHog"
