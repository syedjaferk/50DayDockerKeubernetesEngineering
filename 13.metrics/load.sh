#!/bin/sh
# Send a mix of traffic for N seconds (default 30): fast, slow and flaky requests.
END=$(( $(date +%s) + ${1:-30} ))
while [ "$(date +%s)" -lt "$END" ]; do
  curl -s -o /dev/null localhost:8000/ &
  curl -s -o /dev/null localhost:8000/slow &
  curl -s -o /dev/null localhost:8000/flaky &
  sleep 0.2
done
wait
