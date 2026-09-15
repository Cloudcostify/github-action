#!/usr/bin/env bash
# Shared, sourceable functions used by action.yml and tests/lib_test.sh.
# Every value here may originate from a workflow caller's inputs and must be
# treated as untrusted: validate before use, never eval, never interpolate
# raw values into a shell command string.

SUPPORTED_PROVIDERS=(pulumi)
SUPPORTED_RIDS=(linux-x64 linux-arm64 osx-x64 osx-arm64 win-x64)

validate_provider() {
  local value="$1" p
  for p in "${SUPPORTED_PROVIDERS[@]}"; do
    if [[ "$value" == "$p" ]]; then
      return 0
    fi
  done
  echo "::error::Unsupported provider '${value}'. Supported providers: ${SUPPORTED_PROVIDERS[*]}" >&2
  return 1
}

validate_budget() {
  local value="$1"
  if [[ -z "$value" ]]; then
    return 0
  fi
  if [[ ! "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "::error::Invalid budget '${value}'. Must be a non-negative number." >&2
    return 1
  fi
  return 0
}

validate_cli_version() {
  local value="$1"
  if [[ "$value" == "latest" ]]; then
    return 0
  fi
  if [[ ! "$value" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    echo "::error::Invalid cli-version '${value}'. Use 'latest' or a release tag such as 'v1.2.3'." >&2
    return 1
  fi
  return 0
}

# Normalizes a raw `uname -m` value to a .NET RID architecture segment.
# Rejects (rather than silently passing through) anything unrecognized.
normalize_arch() {
  local arch="$1"
  case "$arch" in
    x86_64|amd64)
      echo "x64"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    *)
      echo "::error::Unsupported architecture '${arch}'." >&2
      return 1
      ;;
  esac
}

# Resolves a lowercased `uname -s` value plus a normalized arch to a
# supported .NET RID. Rejects unknown operating systems instead of
# defaulting to Windows.
resolve_rid() {
  local os="$1" arch="$2" rid="" supported

  case "$os" in
    linux)
      rid="linux-${arch}"
      ;;
    darwin)
      rid="osx-${arch}"
      ;;
    windows|msys*|mingw*|cygwin*)
      rid="win-${arch}"
      ;;
    *)
      echo "::error::Unsupported operating system '${os}'." >&2
      return 1
      ;;
  esac

  for supported in "${SUPPORTED_RIDS[@]}"; do
    if [[ "$rid" == "$supported" ]]; then
      echo "$rid"
      return 0
    fi
  done

  echo "::error::Unsupported platform '${rid}'. Supported: ${SUPPORTED_RIDS[*]}" >&2
  return 1
}

# Detects the current platform's RID via `uname`, rejecting anything not in
# SUPPORTED_RIDS. Factored out (rather than inlined in action.yml) so it can
# be exercised in tests by shadowing `uname`.
detect_rid() {
  local os_raw arch_raw arch
  os_raw=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch_raw=$(uname -m)
  arch=$(normalize_arch "$arch_raw") || return 1
  resolve_rid "$os_raw" "$arch"
}

binary_filename() {
  local rid="$1"
  case "$rid" in
    win-*)
      echo "cloudcostify-${rid}.exe"
      ;;
    *)
      echo "cloudcostify-${rid}"
      ;;
  esac
}

# Verifies file_path against the checksum recorded for filename in a
# `sha256sum`-format manifest (sums_file). Fails closed: missing manifest,
# missing entry, malformed hash, and mismatch are all treated as failure.
verify_checksum() {
  local file_path="$1" filename="$2" sums_file="$3" expected="" actual line hash name

  if [[ ! -f "$sums_file" ]]; then
    echo "::error::Checksum manifest '${sums_file}' not found." >&2
    return 1
  fi

  # Parsed as exact literal fields, not a regex/glob match against
  # filename, so an entry like "evil-${filename}" or a filename containing
  # "." or "*" cannot be mistaken for the entry actually being looked up.
  while IFS= read -r line; do
    hash="${line%%  *}"
    name="${line#*  }"
    if [[ "$name" == "$filename" ]]; then
      expected="$hash"
      break
    fi
  done < "$sums_file"

  if [[ -z "$expected" ]]; then
    echo "::error::No checksum entry for '${filename}' in manifest." >&2
    return 1
  fi

  if [[ ! "$expected" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "::error::Malformed checksum entry for '${filename}'." >&2
    return 1
  fi

  if [[ ! -f "$file_path" ]]; then
    echo "::error::Downloaded file '${file_path}' not found." >&2
    return 1
  fi

  actual=$(sha256sum "$file_path" | awk '{print $1}')

  if [[ "${actual,,}" != "${expected,,}" ]]; then
    echo "::error::Checksum mismatch for '${filename}'. Expected ${expected}, got ${actual}." >&2
    return 1
  fi

  return 0
}
