#!/usr/bin/env bash
#
# Run a VRL program against one or more JSON inputs and print the resulting
# object (or array) to stdout. Used by the write-vrl skill to iterate on a
# transformation until its output matches expectations.
#
# Usage:
#   test_vrl.sh [--verbose] [--lookup-table NAME=PATH.csv]... [--mmdb-table NAME=PATH.mmdb]... <program.vrl> <input.json> [<input2.json> ...]
#
# Without enrichment-table flags:
#   Runs via `vector vrl` (single-event mode, fast). Good for pure
#   transformations that don't call find_enrichment_table_records or
#   get_enrichment_table_record.
#
# With one or more --lookup-table or --mmdb-table:
#   Synthesizes a full Vector pipeline so the corresponding VRL function
#   resolves against the given file. NAME must match the literal table name
#   passed to the function inside the VRL program. Either flag is repeatable
#   and they can be mixed in one run.
#     --lookup-table NAME=PATH.csv   -> find_enrichment_table_records!(NAME, ...)
#     --mmdb-table   NAME=PATH.mmdb  -> get_enrichment_table_record(NAME, ...)
#
# Output: one JSON value per input, in order, with a per-input header when
#   multiple inputs are given. A line of just `[]   # DROPPED -- ...` means
#   the empty-array drop fired (Scanner skips indexing the event).
#
# Exit code: 0 if every input ran without VRL errors, non-zero otherwise.
#
# Requires: a local `vector` binary on PATH or at ~/.vector/bin/vector.
#   Install with:
#     curl --proto '=https' --tlsv1.2 -sSf https://sh.vector.dev | bash
#   or see https://vector.dev/docs/setup/installation/

set -eo pipefail

VERBOSE=0
declare -a LOOKUP_TABLES=()
declare -a MMDB_TABLES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose)
      VERBOSE=1
      shift
      ;;
    --lookup-table)
      if [[ $# -lt 2 ]]; then
        echo "test_vrl: --lookup-table needs a value (NAME=PATH.csv)" >&2
        exit 2
      fi
      LOOKUP_TABLES+=("$2")
      shift 2
      ;;
    --lookup-table=*)
      LOOKUP_TABLES+=("${1#--lookup-table=}")
      shift
      ;;
    --mmdb-table)
      if [[ $# -lt 2 ]]; then
        echo "test_vrl: --mmdb-table needs a value (NAME=PATH.mmdb)" >&2
        exit 2
      fi
      MMDB_TABLES+=("$2")
      shift 2
      ;;
    --mmdb-table=*)
      MMDB_TABLES+=("${1#--mmdb-table=}")
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "test_vrl: unknown flag: $1" >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -lt 2 ]]; then
  cat >&2 <<'USAGE'
Usage: test_vrl.sh [--verbose] [--lookup-table NAME=PATH.csv]... [--mmdb-table NAME=PATH.mmdb]... <program.vrl> <input.json> [<input.json>...]

  Without enrichment flags: runs via `vector vrl` (fast, single-event).
  With --lookup-table:      synthesizes a Vector pipeline so
                            find_enrichment_table_records!(NAME, ...) resolves
                            against the given CSV. Repeatable.
  With --mmdb-table:        same idea for get_enrichment_table_record(NAME, ...)
                            against an MMDB (MaxMind DB) file. Repeatable.
  NAME must match the literal name passed to the VRL function. Flags can be
  mixed in one run.
USAGE
  exit 2
fi

PROGRAM="$1"
shift

if [[ ! -f "$PROGRAM" ]]; then
  echo "test_vrl: program not found: $PROGRAM" >&2
  exit 2
fi

for input in "$@"; do
  if [[ ! -f "$input" ]]; then
    echo "test_vrl: input not found: $input" >&2
    exit 2
  fi
done

VECTOR_BIN=""
if command -v vector >/dev/null 2>&1; then
  VECTOR_BIN="vector"
elif [[ -x "$HOME/.vector/bin/vector" ]]; then
  VECTOR_BIN="$HOME/.vector/bin/vector"
fi

if [[ -z "$VECTOR_BIN" ]]; then
  cat >&2 <<'INSTALL'
test_vrl: vector binary not found on PATH or at ~/.vector/bin/vector.
Install with:
  curl --proto '=https' --tlsv1.2 -sSf https://sh.vector.dev | bash
or see https://vector.dev/docs/setup/installation/
INSTALL
  exit 2
fi

TOTAL_TABLES=$(( ${#LOOKUP_TABLES[@]} + ${#MMDB_TABLES[@]} ))

if [[ $VERBOSE -eq 1 ]]; then
  echo "# backend: $VECTOR_BIN ($("$VECTOR_BIN" --version 2>/dev/null | head -1))" >&2
  if [[ $TOTAL_TABLES -gt 0 ]]; then
    echo "# mode: pipeline (${#LOOKUP_TABLES[@]} CSV + ${#MMDB_TABLES[@]} MMDB table(s))" >&2
  else
    echo "# mode: vrl" >&2
  fi
fi

ERR_LOG=$(mktemp)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$ERR_LOG" "$TMP_DIR"' EXIT

# ---------- Pipeline mode (with enrichment tables) ----------

if [[ $TOTAL_TABLES -gt 0 ]]; then
  CONFIG="$TMP_DIR/vector.toml"
  : > "$CONFIG"

  for spec in "${LOOKUP_TABLES[@]}"; do
    name="${spec%%=*}"
    path="${spec#*=}"
    if [[ -z "$name" || "$name" == "$spec" || -z "$path" ]]; then
      echo "test_vrl: bad --lookup-table value (want NAME=PATH.csv): $spec" >&2
      exit 2
    fi
    if [[ ! -f "$path" ]]; then
      echo "test_vrl: lookup-table CSV not found: $path" >&2
      exit 2
    fi
    abs_path=$(cd "$(dirname "$path")" && pwd)/$(basename "$path")
    cat >>"$CONFIG" <<EOF
[enrichment_tables.$name]
type = "file"
file.path = "$abs_path"
file.encoding.type = "csv"

EOF
  done

  for spec in "${MMDB_TABLES[@]}"; do
    name="${spec%%=*}"
    path="${spec#*=}"
    if [[ -z "$name" || "$name" == "$spec" || -z "$path" ]]; then
      echo "test_vrl: bad --mmdb-table value (want NAME=PATH.mmdb): $spec" >&2
      exit 2
    fi
    if [[ ! -f "$path" ]]; then
      echo "test_vrl: mmdb-table file not found: $path" >&2
      exit 2
    fi
    abs_path=$(cd "$(dirname "$path")" && pwd)/$(basename "$path")
    cat >>"$CONFIG" <<EOF
[enrichment_tables.$name]
type = "mmdb"
path = "$abs_path"

EOF
  done

  abs_prog=$(cd "$(dirname "$PROGRAM")" && pwd)/$(basename "$PROGRAM")
  cat >>"$CONFIG" <<EOF
[sources.input]
type = "stdin"

[transforms.unwrap]
type = "remap"
inputs = ["input"]
source = '. = parse_json!(.message)'

[transforms.remap]
type = "remap"
inputs = ["unwrap"]
file = "$abs_prog"

[sinks.output]
type = "console"
inputs = ["remap"]
target = "stdout"
encoding.codec = "json"
EOF

  if [[ $VERBOSE -eq 1 ]]; then
    echo "# config: $CONFIG" >&2
    sed 's/^/#   /' "$CONFIG" >&2
  fi

  if ! ALL_OUT=$(cat "$@" | "$VECTOR_BIN" --config "$CONFIG" --quiet 2>"$ERR_LOG"); then
    echo "# Vector pipeline failed:" >&2
    sed 's/^/#   /' "$ERR_LOG" >&2
    exit 1
  fi

  i=0
  inputs=("$@")
  multi=$(( ${#inputs[@]} > 1 ? 1 : 0 ))
  while IFS= read -r line; do
    if [[ $multi -eq 1 && $i -lt ${#inputs[@]} ]]; then
      echo "# === $(basename "${inputs[$i]}") ==="
    fi
    if [[ "$line" == "[]" ]]; then
      echo "[]   # DROPPED -- empty array tells Scanner to skip indexing this event"
    else
      echo "$line"
    fi
    i=$((i + 1))
  done <<<"$ALL_OUT"

  exit 0
fi

# ---------- VRL-subcommand mode (no enrichment tables) ----------

FAILED=0
for input in "$@"; do
  if [[ $# -gt 1 ]]; then
    echo "# === $(basename "$input") ==="
  fi
  if out=$("$VECTOR_BIN" vrl -i "$input" -p "$PROGRAM" -o 2> "$ERR_LOG"); then
    json_line=$(echo "$out" | grep -v '^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T.*INFO ' | tail -n 1)
    if [[ "$json_line" == "[]" ]]; then
      echo "[]   # DROPPED -- empty array tells Scanner to skip indexing this event"
    else
      echo "$json_line"
    fi
  else
    FAILED=1
    echo "# VRL error on $(basename "$input"):" >&2
    sed 's/^/#   /' "$ERR_LOG" >&2
  fi
done

exit $FAILED
