SHELL := /bin/bash
BATS  ?= bats

# Every plugin is a folder under plugins/, found here rather than listed, so a
# new plugin is a folder and a catalog entry and nothing in this file changes.
# PLUGIN=<name> limits a run to that one.
PLUGINS := $(if $(PLUGIN),$(PLUGIN),$(notdir $(patsubst %/,%,$(wildcard plugins/*/))))

.PHONY: check check-bash32 lint-identifiers validate $(addprefix plugin/,$(PLUGINS))

check: lint-identifiers $(addprefix plugin/,$(PLUGINS)) validate

# One plugin: shellcheck over every executable under its skills/, then its own
# bats suite, run from the plugin's folder.
$(addprefix plugin/,$(PLUGINS)): plugin/%:
	@[ -d "plugins/$*" ] || { echo "finding: no plugin folder plugins/$*" >&2; exit 2; }
	@if [ -d "plugins/$*/skills" ]; then \
	  find "plugins/$*/skills" -type f -perm -u+x -exec shellcheck -s bash {} +; \
	fi
	@if ls "plugins/$*"/tests/*.bats >/dev/null 2>&1; then \
	  cd "plugins/$*" && $(BATS) tests; \
	else \
	  echo "plugins/$*: no tests yet"; \
	fi

# macOS ships bash 3.2 as /bin/bash, and every script finds bash through PATH.
# This runs the same checks with that bash first on PATH, bats included.
check-bash32:
	@mkdir -p .tmp/bash32 && ln -sf /bin/bash .tmp/bash32/bash
	@PATH="$(CURDIR)/.tmp/bash32:$$PATH" $(MAKE) --no-print-directory check

# The manifests, checked by Claude Code's own validator when it is installed.
# CI does not install it: that would be a global npm install on every run for
# a check this target already makes before anything is pushed.
validate:
	@if command -v claude >/dev/null 2>&1; then \
	  claude plugin validate --strict . || exit 1; \
	  for p in $(PLUGINS); do claude plugin validate --strict "plugins/$$p" || exit 1; done; \
	else \
	  echo "claude is not on PATH; skipping claude plugin validate --strict"; \
	fi

# Account names that are also ordinary words or shared CI defaults. A name equal
# to one of these is dropped before the search: a CI runner's account is called
# runner, and matching it would fail every file that uses the word normally.
GENERIC_ACCOUNTS := runner ubuntu root admin build ci user vagrant jenkins docker \
                    dev git log run tmp test www ftp

# Nothing personal is tracked, and neither is the list of what counts as
# personal: it is built here, at run time, from this machine's home directory
# and account name, and thrown away after. Paths match anywhere; names match
# only as whole words. In CI those values are the runner's, so two generic
# home-path shapes are searched as well. They are spelt from parts so this file
# does not match itself.
#
# A match is judged by what grep printed, not by its exit status: xargs may
# split the file list, and its status then says nothing about a match.
lint-identifiers:
	@tmp="$$(mktemp -d)"; trap 'rm -rf "$$tmp"' EXIT; \
	[ "$$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ] \
	  || { echo "finding: cannot check identifiers: not inside a git work tree" >&2; exit 2; }; \
	printf '%s\n' $(GENERIC_ACCOUNTS) > "$$tmp/generic"; \
	printf '%s\n' "$$HOME" | awk 'length >= 4' > "$$tmp/paths"; \
	{ whoami; basename "$$HOME"; } 2>/dev/null | grep -vxF -f "$$tmp/generic" \
	  | awk 'length >= 4' | sort -u > "$$tmp/names"; \
	printf '/%s/\n' Users home > "$$tmp/shapes"; \
	: > "$$tmp/found"; \
	if [ -s "$$tmp/paths" ]; then \
	  git ls-files -z | xargs -0 grep -nIF -f "$$tmp/paths" -- >> "$$tmp/found" 2>/dev/null; \
	fi; \
	if [ -s "$$tmp/names" ]; then \
	  git ls-files -z | xargs -0 grep -nIwF -f "$$tmp/names" -- >> "$$tmp/found" 2>/dev/null; \
	fi; \
	git ls-files -z | xargs -0 grep -nIF -f "$$tmp/shapes" -- >> "$$tmp/found" 2>/dev/null; \
	[ ! -s "$$tmp/found" ] || { cat "$$tmp/found"; \
	  echo "finding: personal identifiers or home paths in tracked files, listed above; remove them" >&2; exit 2; }
