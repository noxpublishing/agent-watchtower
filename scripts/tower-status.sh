#!/usr/bin/env bash
# The whole fleet in a few lines, kept short because the tower reads it often.
exec "$(cd "$(dirname "$0")" && pwd)/tower-board.sh" --plain "$@"
