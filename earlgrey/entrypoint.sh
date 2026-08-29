#!/usr/bin/env bash
set -euo pipefail

# Wraps earlGrey so -g/-o accept either a local path (bind-mounted for local
# testing) or an s3:// URI (for AWS Batch): s3 inputs are downloaded before
# the run, and if -o is an s3:// URI, results are synced back up afterward.

genome_local=""
output_local=""
output_s3=""
args=("$@")
new_args=()

i=0
while [ $i -lt ${#args[@]} ]; do
	arg="${args[$i]}"
	case "$arg" in
	-g)
		i=$((i + 1))
		val="${args[$i]:-}"
		if [[ "$val" == s3://* ]]; then
			mkdir -p /tmp/earlgrey-input
			genome_local="/tmp/earlgrey-input/$(basename "$val")"
			aws s3 cp "$val" "$genome_local"
			if [[ "$genome_local" == *.gz ]]; then
				gunzip -f "$genome_local"
				genome_local="${genome_local%.gz}"
			fi
			new_args+=("-g" "$genome_local")
		else
			new_args+=("-g" "$val")
		fi
		;;
	-o)
		i=$((i + 1))
		val="${args[$i]:-}"
		if [[ "$val" == s3://* ]]; then
			output_s3="$val"
			output_local="/tmp/earlgrey-output"
			mkdir -p "$output_local"
			new_args+=("-o" "$output_local")
		else
			new_args+=("-o" "$val")
		fi
		;;
	*)
		new_args+=("$arg")
		;;
	esac
	i=$((i + 1))
done

status=0
conda run --no-capture-output -n earlgrey earlGrey "${new_args[@]}" || status=$?

if [ -n "$output_s3" ]; then
	aws s3 sync "$output_local" "$output_s3"
fi

exit "$status"
