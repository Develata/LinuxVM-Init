#!/usr/bin/env bash
set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELFCHECK_DIR="$BASE_DIR/selfcheck"

# shellcheck source=selfcheck/common.sh
source "$SELFCHECK_DIR/common.sh" || { printf '%s\n' 'failed to load selfcheck/common.sh' >&2; exit 1; }
# shellcheck source=selfcheck/module_checks.sh
source "$SELFCHECK_DIR/module_checks.sh" || { printf '%s\n' 'failed to load selfcheck/module_checks.sh' >&2; exit 1; }
# shellcheck source=selfcheck/nftables.sh
source "$SELFCHECK_DIR/nftables.sh" || { printf '%s\n' 'failed to load selfcheck/nftables.sh' >&2; exit 1; }
# shellcheck source=selfcheck/network_stack.sh
source "$SELFCHECK_DIR/network_stack.sh" || { printf '%s\n' 'failed to load selfcheck/network_stack.sh' >&2; exit 1; }
# shellcheck source=selfcheck/iptables_frontend.sh
source "$SELFCHECK_DIR/iptables_frontend.sh" || { printf '%s\n' 'failed to load selfcheck/iptables_frontend.sh' >&2; exit 1; }

printf 'LinuxVM-Init selfcheck\n'
printf 'Root path: %s\n\n' "$BASE_DIR"

check_required_files
check_shell_syntax
check_shellcheck
check_module_sources
check_nftables_ruleset_generation
check_network_stack_detection
check_network_stack_rendering
check_iptables_frontend_detection
check_required_functions
check_required_commands
print_selfcheck_summary
