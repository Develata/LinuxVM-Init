#!/usr/bin/env bash

check_nftables_ruleset_generation() {
  local tmp_file nft_output nft_rc
  tmp_file="$(mktemp /tmp/linuxvm-init-selfcheck-nftables.XXXXXX)" || {
    fail 'failed to create nftables selfcheck temp file'
    return
  }

  if nftables_render_ruleset "$tmp_file" 34521 '2001:db8::1' '80,443' '53' 'essential' 'docker'; then
    ok 'nftables ruleset renders successfully'
  else
    fail 'nftables ruleset render failed'
    rm -f "$tmp_file"
    return
  fi

  if command -v nft >/dev/null 2>&1; then
    nft_output="$(nft -c -f "$tmp_file" 2>&1)"
    nft_rc=$?
    if [ "$nft_rc" -eq 0 ]; then
      ok 'nftables ruleset syntax check passed'
    elif printf '%s\n' "$nft_output" | grep -Eq 'Operation not permitted|cache initialization failed'; then
      warn 'nftables syntax check skipped: nft lacks netlink permission'
    else
      printf '%s\n' "$nft_output"
      fail 'nftables ruleset syntax check failed'
    fi
  else
    warn 'command missing: nft'
  fi

  rm -f "$tmp_file"
}
