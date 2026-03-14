#!/usr/bin/env bash

file_path=$(cat - | jq -r '.tool_input.file_path // empty')

[ -z "$file_path" ] && exit 0

case "$file_path" in
  *.ex|*.exs|*.heex) ;;
  *) exit 0 ;;
esac

dir=$(dirname "$file_path")
while [ "$dir" != / ] && [ ! -f "$dir/mix.exs" ]; do
  dir=$(dirname "$dir")
done

[ -f "$dir/mix.exs" ] && cd "$dir" && mix format "$file_path" 2>/dev/null

exit 0
