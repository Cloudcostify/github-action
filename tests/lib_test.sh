#!/usr/bin/env bash
# Dependency-free test harness for scripts/lib.sh.
#
# Rationale for this over a framework: the repository has no existing test
# tooling and the logic under test is a handful of small, pure bash
# functions. A framework (Bats, shunit2) would add a dependency for a
# surface area this small; plain assert helpers plus `set -uo pipefail`
# cover it without one. Revisit if the script surface grows materially.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../scripts/lib.sh"
# shellcheck source=../scripts/lib.sh
source "$LIB"

pass=0
fail=0

assert_success() {
  local desc="$1"; shift
  local out
  if out=$("$@" 2>&1); then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $desc"
    echo "$out" | sed 's/^/    /'
  fi
}

assert_failure() {
  local desc="$1"; shift
  local out
  if out=$("$@" 2>&1); then
    fail=$((fail + 1))
    echo "FAIL (expected failure but succeeded): $desc"
  else
    pass=$((pass + 1))
  fi
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $desc (expected '$expected', got '$actual')"
  fi
}

# --- validate_provider -------------------------------------------------

assert_success "provider: pulumi is valid" validate_provider "pulumi"
assert_failure "provider: unknown value rejected" validate_provider "aws"
assert_failure "provider: command substitution rejected" validate_provider '$(touch /tmp/pwned)'
assert_failure "provider: quote-and-append injection rejected" validate_provider 'pulumi"; touch /tmp/pwned; echo "'

# --- validate_budget -----------------------------------------------------

assert_success "budget: empty allowed" validate_budget ""
assert_success "budget: integer" validate_budget "500"
assert_success "budget: decimal" validate_budget "12.50"
assert_failure "budget: negative rejected" validate_budget "-5"
assert_failure "budget: non-numeric rejected" validate_budget "abc"
assert_failure "budget: command substitution rejected" validate_budget '$(id)'
assert_failure "budget: trailing metacharacters rejected" validate_budget '5; rm -rf /'

# --- validate_cli_version -------------------------------------------------

assert_success "cli-version: latest" validate_cli_version "latest"
assert_success "cli-version: valid tag" validate_cli_version "v1.0.0"
assert_success "cli-version: valid prerelease tag" validate_cli_version "v1.0.0-beta1"
assert_failure "cli-version: missing v-prefix rejected" validate_cli_version "1.0.0"
assert_failure "cli-version: injected metacharacters rejected" validate_cli_version 'v1.0.0$(touch /tmp/pwned)'
assert_failure "cli-version: path traversal rejected" validate_cli_version '../../etc/passwd'

# --- normalize_arch --------------------------------------------------------

assert_eq "arch: x86_64 normalizes to x64" "x64" "$(normalize_arch x86_64)"
assert_eq "arch: aarch64 normalizes to arm64" "arm64" "$(normalize_arch aarch64)"
assert_failure "arch: unsupported rejected" normalize_arch armv7l

# --- resolve_rid ------------------------------------------------------------

assert_eq "rid: linux x64" "linux-x64" "$(resolve_rid linux x64)"
assert_eq "rid: darwin arm64" "osx-arm64" "$(resolve_rid darwin arm64)"
assert_eq "rid: mingw (windows git-bash) maps to win" "win-x64" "$(resolve_rid mingw64_nt-10.0 x64)"
assert_failure "rid: unsupported os rejected instead of defaulting to windows" resolve_rid freebsd x64

# --- detect_rid (exercises the exact step action.yml runs, via a stubbed
# uname so the test is not tied to the CI runner's real platform) ----------

detect_rid_with() {
  local stub_os="$1" stub_arch="$2"
  uname() {
    case "$1" in
      -s) printf '%s\n' "$stub_os" ;;
      -m) printf '%s\n' "$stub_arch" ;;
    esac
  }
  detect_rid
  local rc=$?
  unset -f uname
  return $rc
}

out=$(detect_rid_with Linux x86_64)
assert_eq "detect_rid: recognized linux/x86_64 resolves" "linux-x64" "$out"
assert_failure "detect_rid: unsupported OS rejected instead of defaulting to windows" \
  detect_rid_with FreeBSD x86_64
assert_failure "detect_rid: unsupported architecture rejected" \
  detect_rid_with Linux armv7l

# --- binary_filename ---------------------------------------------------------

assert_eq "binary filename: linux has no extension" "cloudcostify-linux-x64" "$(binary_filename linux-x64)"
assert_eq "binary filename: windows has .exe" "cloudcostify-win-x64.exe" "$(binary_filename win-x64)"

# --- verify_checksum ---------------------------------------------------------

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

printf 'hello world' > "$tmpdir/cloudcostify-linux-x64"
good_sum=$(sha256sum "$tmpdir/cloudcostify-linux-x64" | awk '{print $1}')

printf '%s  cloudcostify-linux-x64\n' "$good_sum" > "$tmpdir/SUMS.good"
printf '%s  cloudcostify-linux-x64\n' "0000000000000000000000000000000000000000000000000000000000000000" > "$tmpdir/SUMS.mismatch"
printf 'not-a-checksum  cloudcostify-linux-x64\n' > "$tmpdir/SUMS.malformed"
printf '%s  some-other-file\n' "$good_sum" > "$tmpdir/SUMS.missing-entry"
# A decoy entry that is a look-alike but not an exact match must not be
# accepted. In particular, `cloudcostify-win-x64.exe` is a real filename
# this repo produces (see binary_filename), and its literal "." must not be
# treated as a regex/glob wildcard that a line like
# "cloudcostify-win-x64Xexe" could satisfy.
printf '%s  evil-cloudcostify-linux-x64\n' "$good_sum" > "$tmpdir/SUMS.decoy-only"
# Manifest deliberately omits "cloudcostify-win-x64.exe" itself and only has
# a look-alike with the literal "." replaced by another character.
printf '%s  cloudcostify-win-x64Xexe\n' "$good_sum" > "$tmpdir/SUMS.dot-wildcard-decoy"

assert_success "checksum: valid match verifies" \
  verify_checksum "$tmpdir/cloudcostify-linux-x64" "cloudcostify-linux-x64" "$tmpdir/SUMS.good"
assert_failure "checksum: mismatch rejected" \
  verify_checksum "$tmpdir/cloudcostify-linux-x64" "cloudcostify-linux-x64" "$tmpdir/SUMS.mismatch"
assert_failure "checksum: malformed entry rejected" \
  verify_checksum "$tmpdir/cloudcostify-linux-x64" "cloudcostify-linux-x64" "$tmpdir/SUMS.malformed"
assert_failure "checksum: missing entry rejected" \
  verify_checksum "$tmpdir/cloudcostify-linux-x64" "cloudcostify-linux-x64" "$tmpdir/SUMS.missing-entry"
assert_failure "checksum: missing manifest file rejected" \
  verify_checksum "$tmpdir/cloudcostify-linux-x64" "cloudcostify-linux-x64" "$tmpdir/does-not-exist"
assert_failure "checksum: decoy entries (substring/glob-lookalike names) not accepted as a match" \
  verify_checksum "$tmpdir/cloudcostify-linux-x64" "cloudcostify-linux-x64" "$tmpdir/SUMS.decoy-only"

printf 'hello world' > "$tmpdir/cloudcostify-win-x64.exe"
assert_failure "checksum: literal '.' in filename is not a regex/glob wildcard" \
  verify_checksum "$tmpdir/cloudcostify-win-x64.exe" "cloudcostify-win-x64.exe" "$tmpdir/SUMS.dot-wildcard-decoy"

# --- argument-array construction (mirrors action.yml's run step) -----------
# Proves untrusted working-directory/markdown-output values reach the CLI as
# literal argv entries and are never interpreted by the shell, even when they
# contain spaces or shell metacharacters.

mock_cli="$tmpdir/mock-cli.sh"
cat > "$mock_cli" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@"
MOCK
chmod +x "$mock_cli"

build_and_run() {
  local provider="$1" dir="$2" budget="$3" out="$4"
  local args=(--provider "$provider" --directory "$dir")
  [[ -n "$budget" ]] && args+=(--budget "$budget")
  [[ -n "$out" ]] && args+=(--out-markdown "$out")
  "$mock_cli" "${args[@]}"
}

marker="$tmpdir/pwned-marker"

output=$(build_and_run "pulumi" "dir with spaces/\$(touch $marker)" "" "")
if [[ -f "$marker" ]]; then
  fail=$((fail + 1))
  echo "FAIL: command substitution embedded in working-directory was executed"
  rm -f "$marker"
else
  pass=$((pass + 1))
fi
assert_eq "argv: working-directory with spaces and \$() passed through literally" \
  "dir with spaces/\$(touch $marker)" "$(printf '%s\n' "$output" | tail -n1)"

output=$(build_and_run "pulumi" "." "" "\"; touch $marker; echo \"")
if [[ -f "$marker" ]]; then
  fail=$((fail + 1))
  echo "FAIL: shell metacharacters embedded in markdown-output were executed"
  rm -f "$marker"
else
  pass=$((pass + 1))
fi

echo
echo "Passed: $pass  Failed: $fail"
[[ "$fail" -eq 0 ]]
