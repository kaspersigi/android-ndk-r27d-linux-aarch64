#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

resolve_build_jobs() {
    local host_jobs resolved_jobs

    host_jobs=$(nproc)
    if [[ "${GITHUB_ACTIONS:-false}" == "true" ]]; then
        resolved_jobs=${JOBS:-$host_jobs}
    else
        if [[ ${JOBS+x} == x && "$JOBS" != "$host_jobs" ]]; then
            echo "error: local builds must use all $host_jobs processors reported by nproc" >&2
            echo "       JOBS is reserved for GitHub Actions resource limits" >&2
            return 2
        fi
        resolved_jobs=$host_jobs
    fi

    if [[ ! "$resolved_jobs" =~ ^[1-9][0-9]*$ ]]; then
        echo "error: JOBS must be a positive integer" >&2
        return 2
    fi
    printf '%s\n' "$resolved_jobs"
}
