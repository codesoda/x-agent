#!/usr/bin/env bash

# This script has shellcheck violations at warning severity.

# SC2034 (warning): my_unused appears unused. Verify use (or export/eval).
my_unused="this is never used"

# SC2154 (warning): unset_var is referenced but not assigned.
echo "$unset_var"
