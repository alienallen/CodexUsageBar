#!/bin/sh
# Read the complete handshake and both requests before returning the fixture.
IFS= read -r init
IFS= read -r initialized
IFS= read -r account
IFS= read -r limits
normalized=$(printf "%s %s %s %s" "$init" "$initialized" "$account" "$limits" | tr -d "\\")
case "$normalized" in
  *initialize*initialized*account/read*account/rateLimits/read*) ;;
  *) printf '%s\n' '{"id":1,"error":{"message":"unexpected handshake"}}'; exit 0 ;;
esac
printf '%s\n' '{"id":1,"result":{}}'
case "${CODEX_TEST_SCENARIO:-success}" in
  success) printf '%s\n' '{"id":3,"result":{"account":{"type":"chatgpt"}}}' '{"id":2,"result":{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":30,"windowDurationMins":300,"resetsAt":1793758831},"secondary":{"usedPercent":75,"windowDurationMins":10080,"resetsAt":1793758831}}}}}' ;;
  reversed) printf '%s\n' '{"id":2,"error":{"message":"failure"}}' '{"id":3,"result":{"account":null}}' ;;
  loggedout) printf '%s\n' '{"id":3,"result":{"account":null}}' '{"id":2,"error":{"message":"failure"}}' ;;
  apikey) printf '%s\n' '{"id":3,"result":{"account":{"type":"apiKey"}}}' '{"id":2,"error":{"message":"failure"}}' ;;
  network) printf '%s\n' '{"id":3,"result":{"account":{"type":"chatgpt"}}}' '{"id":2,"error":{"message":"failure"}}' ;;
  empty) printf '%s\n' '{"id":3,"result":{"account":{"type":"chatgpt"}}}' '{"id":2,"result":{"rateLimits":{"primary":null,"secondary":null}}}' ;;
  timeout) exec /bin/sleep 3 ;;
esac
