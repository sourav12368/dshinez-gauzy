#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
if [[ "$(git branch --show-current)" != dshinez || -n "$(git status --porcelain)" ]] ||
	git rev-parse --verify --quiet MERGE_HEAD >/dev/null; then
	printf 'Start from a clean dshinez branch with no merge in progress.\n' >&2
	exit 1
fi

git fetch --no-tags "${DSHINEZ_UPSTREAM_URL:-https://github.com/ever-co/ever-gauzy.git}" refs/heads/develop
upstream_tip=$(git rev-parse --verify FETCH_HEAD)
if git merge-base --is-ancestor "$upstream_tip" HEAD; then
	printf 'The dshinez branch already contains upstream %s.\n' "$upstream_tip"
	exit 0
fi

# Discard the attempted merge on failure so the next sync starts from the same branch tip.
abort_merge() {
	if git rev-parse --verify --quiet MERGE_HEAD >/dev/null; then
		git merge --abort
	fi
}
trap abort_merge EXIT

# A merge can fail after creating MERGE_HEAD. Clear conflicts in fork-managed files
# before deciding whether source files need manual resolution.
git merge --no-commit --no-ff "$upstream_tip" ||
	git rev-parse --verify --quiet MERGE_HEAD >/dev/null
git restore --source=HEAD --staged --worktree -- .github/workflows README.md

conflicts=$(git diff --name-only --diff-filter=U)
if [[ -n "$conflicts" ]]; then
	printf 'Upstream %s requires manual conflict resolution in:\n%s\n' "$upstream_tip" "$conflicts" >&2
	exit 1
fi

# Preserve the fork landing page and refresh the upstream documentation beside it.
git show "$upstream_tip:README.md" > README.upstream.md
git add README.upstream.md

if ! git diff --cached --quiet -- apps/gauzy/src/assets/branding/dshinez; then
	printf 'Upstream %s changed the D’Shinez theme assets. Review the merge before publishing.\n' "$upstream_tip" >&2
	exit 1
fi

while IFS='|' read -r path hook; do
	if ! git grep --cached --fixed-strings --quiet -e "$hook" -- "$path"; then
		printf 'Brand integration missing after merge: %s in %s\n' "$hook" "$path" >&2
		exit 1
	fi
done <<'HOOKS'
apps/gauzy/src/index.html|class="dshinez-app"
apps/gauzy/src/index.html|<title>D’Shinez OS</title>
apps/gauzy/src/index.html|assets/branding/dshinez/theme.css
apps/gauzy/src/index.html|assets/branding/dshinez/app-icon.png
apps/gauzy/src/app/app.module.ts|PLATFORM_BRAND_NAME: 'D’Shinez OS'
apps/gauzy/src/app/app.module.ts|PLATFORM_LOGO: 'assets/branding/dshinez/wordmark.png'
apps/gauzy/src/manifest.json|"name": "D’Shinez OS"
packages/ui-core/theme/src/lib/components/gauzy-logo/gauzy-logo.component.html|[src]="logoUrl
packages/ui-core/theme/src/lib/layouts/one-column/one-column.layout.html|class="platform-brand"
HOOKS

git commit -m "chore(sync): merge Gauzy develop at ${upstream_tip:0:12}"
