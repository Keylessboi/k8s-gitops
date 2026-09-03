#!/usr/bin/env bash
# doctor.sh - collect everything about one application in one command.
#
#   scripts/doctor.sh immich      one application
#   scripts/doctor.sh             the whole cluster, briefly
#
# WHAT THIS IS FOR
#
# The workflow this cluster is tuned for is: the owner notices something is
# wrong, says so, and a model diagnoses it. The cost of that loop is almost
# entirely in the model's first few commands. Diagnosing the Ghost crash loop
# on 2026-09-03 took roughly forty exploratory kubectl invocations - list pods,
# check restarts, read the deployment, pull events, exec in, curl the endpoint,
# compare live spec to git. A small model will not do that well and a large one
# should not have to.
#
# So this puts the facts that mattered in every past incident into one screen.
#
# WHAT THIS DELIBERATELY DOES NOT DO
#
# It does not tell you what is wrong. There is no "probable cause" field, no
# suggested fix, no table mapping symptoms to remedies. That is a deliberate
# design constraint, not an unfinished feature:
#
#   * A script that names the fault becomes an expert system with a bug for
#     every case it half-covers, and its confident wrong answers are worse than
#     silence, because a small model will believe them.
#
#   * The evidence is in this repo's own history. The obvious reading of the
#     Ghost incident was "the kubelet is probing HTTPS" - that is what the
#     first doctor-log entry concluded, and it was wrong (Ghost 301-redirects
#     plaintext to https on its own host, and the kubelet follows probe
#     redirects into a TLS handshake). Any symptom->cause table would have sent
#     a reader confidently down that same dead end, and one nearly shipped a
#     patch the API server rejects outright.
#
# Correlation is different from interpretation and is safe: "restarts began at
# 14:20, ArgoCD synced at 14:09, here are the events in between" is arithmetic
# on timestamps. Retrieval is safe too: grepping doctor-log.md for prior art is
# a lookup, not a judgement. This script does those two things and stops.
#
# FAILING LOUDLY
#
# Every section says so when it cannot collect its data. A section that is
# missing must never look like a section that is empty - "no events" and
# "could not read events" lead to opposite conclusions, and silently omitting
# the second is how a reader concludes the wrong one.

set -uo pipefail   # NOT -e: a failing section must be reported, not fatal.

LOG_LINES="${LOG_LINES:-40}"
EVENT_LINES="${EVENT_LINES:-15}"
PROM_STS="sts/prometheus-kps-kube-prometheus-stack-prometheus"

# ---------------------------------------------------------------- formatting
hr()  { printf '%s\n' "------------------------------------------------------------"; }
sec() { printf '\n== %s\n' "$1"; }
# Uniform, greppable marker for a section that could not be collected.
nope() { printf '   !! COULD NOT COLLECT: %s\n' "$1"; }

# --------------------------------------------------------------------- probes
have_kubectl() { command -v kubectl >/dev/null 2>&1; }

promq() {
  # Query Prometheus from inside the cluster. Returns raw JSON on stdout.
  kubectl -n monitoring exec "$PROM_STS" -c prometheus -- \
    wget -qO- "http://localhost:9090/api/v1/query?query=$1" 2>/dev/null
}

# ------------------------------------------------------------------ resolving
# app name -> namespace. Most apps are namespace-per-app, but not all: qui
# lives in downloads, bookdl in books, blog in ghost. Try the cheap answer,
# then look for a workload, then an ingress host.
resolve_ns() {
  local app="$1"
  if kubectl get ns "$app" >/dev/null 2>&1; then echo "$app"; return 0; fi
  local ns
  ns=$(kubectl get deploy,sts -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null \
        | awk -v a="$app" '$2==a {print $1; exit}')
  if [ -n "$ns" ]; then echo "$ns"; return 0; fi
  ns=$(kubectl get ingress -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.spec.rules[0].host}{"\n"}{end}' 2>/dev/null \
        | awk -v a="$app" '$2 ~ ("^" a "\\.") {print $1; exit}')
  if [ -n "$ns" ]; then echo "$ns"; return 0; fi
  return 1
}

# ================================================================== cluster
cluster_overview() {
  printf 'doctor.sh - cluster overview - %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  hr

  sec "NODES"
  kubectl get nodes -o wide --no-headers 2>/dev/null | awk '{print "   "$1" "$2" "$5}' || nope "kubectl get nodes"
  kubectl top node --no-headers 2>/dev/null | awk '{print "   cpu "$2" ("$3")  mem "$4" ("$5")"}' \
    || nope "kubectl top node (metrics-server)"

  sec "PODS NOT READY"
  local out
  # Columns with -A are: NAMESPACE NAME READY STATUS RESTARTS AGE. Status is
  # $4 and restarts $5 - one further right than without -A, which is exactly
  # the off-by-one this script shipped with for its first five minutes.
  out=$(kubectl get pods -A --no-headers 2>/dev/null \
        | awk '$4!="Running" && $4!="Completed" && $4!="Succeeded" {print "   "$1"/"$2" "$4" ready="$3" restarts="$5}')
  if [ -z "$out" ]; then echo "   (none)"; else echo "$out"; fi

  sec "PODS WITH RESTARTS"
  out=$(kubectl get pods -A --no-headers 2>/dev/null \
        | awk '$4=="Running" && $5+0 > 0 {print "   "$1"/"$2" restarts="$5}' | sort -t= -k2 -rn)
  if [ -z "$out" ]; then echo "   (none)"; else echo "$out" | head -12; fi

  # Completed/Error pods from Deployments are residue, not workload. 123 of
  # them were cleared by hand on 2026-09-03 after the eviction loops; they
  # accumulate again silently and make `get pods` unreadable long before they
  # cause any real harm.
  sec "FINISHED POD RECORDS STILL PRESENT"
  local n
  n=$(kubectl get pods -A --no-headers 2>/dev/null | awk '$4=="Completed" || $4=="Error" {c++} END {print c+0}')
  if [ "$n" -gt 20 ]; then
    echo "   $n Completed/Error pod records (clutter; clear when convenient)"
  else
    echo "   $n"
  fi

  sec "ARGOCD APPS NOT Synced/Healthy"
  out=$(kubectl -n argocd get applications --no-headers \
          -o custom-columns=N:.metadata.name,S:.status.sync.status,H:.status.health.status 2>/dev/null \
        | awk '$2!="Synced" || $3!="Healthy" {print "   "$1" "$2"/"$3}')
  if [ -z "$out" ]; then echo "   (all Synced/Healthy)"; else echo "$out"; fi

  sec "FIRING ALERTS"
  local json
  json=$(promq 'ALERTS{alertstate="firing"}')
  if [ -z "$json" ]; then
    nope "Prometheus query (is the monitoring stack up?)"
  else
    echo "$json" | python3 -c "
import json,sys,collections
try: d=json.load(sys.stdin)['data']['result']
except Exception: print('   !! COULD NOT COLLECT: unparseable Prometheus response'); sys.exit()
if not d: print('   (none)')
c=collections.Counter((a['metric'].get('alertname','?'), a['metric'].get('exported_namespace') or a['metric'].get('namespace','-')) for a in d)
for (n,ns),k in c.most_common(15): print(f'   {k:>3}x {n}  [{ns}]')
" 2>/dev/null || nope "parsing alerts"
  fi

  sec "EDGE PROBES"
  # Query ALL probe series, not just the failing ones. Asking only for
  # `== 0` cannot distinguish "everything is healthy" from "no probe series
  # exist" - both return an empty result - and the first version of this
  # script printed "all 22 answering as expected" at a moment when the probes
  # had not been scraped even once. That is the exact failure this script is
  # supposed to prevent, so it is worth the extra parsing.
  json=$(promq 'probe_success')
  if [ -z "$json" ]; then
    nope "Prometheus query for probe_success"
  else
    echo "$json" | python3 -c "
import json,sys
try: d=json.load(sys.stdin)['data']['result']
except Exception: print('   !! COULD NOT COLLECT: unparseable Prometheus response'); sys.exit()
if not d:
    print('   !! NO probe_success SERIES AT ALL - the probes are not being')
    print('      scraped. This is NOT the same as everything being healthy.')
    sys.exit()
bad=[a for a in d if a['value'][1]=='0']
print(f'   {len(d)} probe targets, {len(bad)} failing')
for a in bad: print('   FAILING', a['metric'].get('instance','?'))
" 2>/dev/null || nope "parsing probes"
  fi

  hr
  echo "For one application:  scripts/doctor.sh <app>"
}

# ================================================================== one app
app_report() {
  local app="$1" ns
  ns=$(resolve_ns "$app") || {
    printf 'doctor.sh: no namespace, workload or ingress matches %s\n' "$app"
    printf 'Known namespaces:\n'
    kubectl get ns --no-headers -o custom-columns=N:.metadata.name 2>/dev/null | paste -sd' ' | fold -sw 70 | sed 's/^/   /'
    return 1
  }

  printf 'doctor.sh - %s (namespace %s) - %s\n' "$app" "$ns" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  hr

  # ---------------------------------------------------------------- workload
  sec "WORKLOAD"
  local pods
  # custom-columns, not the default output: kubectl renders RESTARTS as
  # "1 (2d16h ago)" once a pod has restarted, which shifts every field to its
  # right and made AGE print as "(2d16h". Naming the columns removes the
  # guesswork entirely.
  pods=$(kubectl -n "$ns" get pods --no-headers -o custom-columns=\
'NAME:.metadata.name,PHASE:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,START:.status.startTime' 2>/dev/null)
  if [ -z "$pods" ]; then
    nope "no pods in $ns (or the namespace is unreadable)"
  else
    echo "$pods" | awk '{printf "   %-48s %-10s restarts=%-4s since=%s\n", $1, $2, $3, $4}'
  fi

  # Restart detail. Ghost's whole diagnosis - exit 0 every ~360s - was sitting
  # in lastState.terminated and nowhere else.
  sec "LAST TERMINATION (per container that has restarted)"
  local term
  term=$(kubectl -n "$ns" get pods -o json 2>/dev/null | python3 -c "
import json,sys
try: pods=json.load(sys.stdin)['items']
except Exception: sys.exit(3)
rows=[]
for p in pods:
    for cs in (p.get('status',{}).get('containerStatuses') or []):
        last=(cs.get('lastState') or {}).get('terminated')
        if not last: continue
        rows.append('   {}/{}  restarts={}  exit={}  reason={}  at={}'.format(
            p['metadata']['name'], cs['name'], cs.get('restartCount',0),
            last.get('exitCode','?'), last.get('reason','?'), last.get('finishedAt','?')))
print('\n'.join(rows) if rows else '   (no container has terminated)')
" 2>/dev/null)
  if [ $? -eq 3 ] || [ -z "$term" ]; then nope "pod status JSON"; else echo "$term"; fi

  # ----------------------------------------------------------------- argocd
  sec "ARGOCD"
  local argo
  argo=$(kubectl -n argocd get app "$app" -o json 2>/dev/null)
  if [ -z "$argo" ]; then
    echo "   (no ArgoCD Application named '$app' - it may be part of another app)"
  else
    echo "$argo" | python3 -c "
import json,sys
a=json.load(sys.stdin); s=a.get('status',{})
sync=s.get('sync',{}); op=s.get('operationState',{})
print('   sync   :', sync.get('status','?'), '  health:', (s.get('health') or {}).get('status','?'))
print('   revision:', (sync.get('revision') or '?')[:8])
print('   last op :', op.get('phase','?'), 'at', op.get('finishedAt','?'))
res=[r for r in (s.get('resources') or []) if r.get('status') not in (None,'Synced')]
if res:
    print('   OUT OF SYNC resources:')
    for r in res[:10]:
        print('     -', r.get('kind'), r.get('name'), '->', r.get('status'))
" 2>/dev/null || nope "parsing ArgoCD Application"
  fi

  # ------------------------------------------------------------------- edge
  sec "EDGE"
  local host
  host=$(kubectl -n "$ns" get ingress -o jsonpath='{range .items[*]}{.spec.rules[0].host}{"\n"}{end}' 2>/dev/null | sort -u | head -3)
  if [ -z "$host" ]; then
    echo "   (no Ingress in $ns - not published)"
  else
    for h in $host; do
      local j
      j=$(promq "probe_success{instance=\"https://$h/\"}")
      if [ -z "$j" ]; then
        nope "probe_success for $h"
        continue
      fi
      echo "$j" | python3 -c "
import json,sys
h='$h'
try: d=json.load(sys.stdin)['data']['result']
except Exception: print(f'   {h}: !! unparseable Prometheus response'); sys.exit()
if not d:
    print(f'   {h}: no probe series (not in apps/monitoring/edge-probes.yaml?)'); sys.exit()
v=d[0]['value'][1]
print(f\"   {h}: probe_success={v}\" + ('  (answering as asserted)' if v=='1' else '  <-- NOT the asserted status code'))
" 2>/dev/null
      # What it actually returns right now, and what it is asserted to return.
      local code
      code=$(promq "probe_http_status_code{instance=\"https://$h/\"}" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)['data']['result']; print(d[0]['value'][1] if d else '')
except Exception: print('')
" 2>/dev/null)
      [ -n "$code" ] && echo "      current status code: $code"
    done
  fi

  # ----------------------------------------------------------------- alerts
  sec "FIRING ALERTS FOR THIS NAMESPACE"
  # exported_namespace, NOT namespace: kube-state-metrics' own namespace lands
  # in `namespace`, the object's in `exported_namespace`. Matching the wrong
  # one silently returns nothing, which reads as "no alerts".
  # Fetch every firing alert and filter here, rather than sending a PromQL
  # `or` through wget - the spaces and braces in that expression were never
  # URL-encoded, so the request came back empty and the section reported
  # "COULD NOT COLLECT" every single time.
  local aj
  aj=$(promq 'ALERTS{alertstate="firing"}')
  if [ -z "$aj" ]; then
    nope "Prometheus alert query"
  else
    echo "$aj" | NS="$ns" python3 -c "
import json,sys,os
ns=os.environ['NS']
try: d=json.load(sys.stdin)['data']['result']
except Exception: print('   !! COULD NOT COLLECT: unparseable response'); sys.exit()
# exported_namespace, NOT namespace: kube-state-metrics' own namespace lands
# in \`namespace\`, the object's in \`exported_namespace\`. Checking only one
# silently misses half the alerts.
hits=[a for a in d if ns in (a['metric'].get('exported_namespace'), a['metric'].get('namespace'))]
if not hits: print('   (none)')
for a in hits[:12]:
    m=a['metric']
    print('  ', m.get('alertname','?'), m.get('severity',''), m.get('pod') or m.get('job_name') or '')
" 2>/dev/null || nope "parsing alerts"
  fi

  # ----------------------------------------------------------------- events
  sec "RECENT EVENTS (last $EVENT_LINES)"
  local ev
  ev=$(kubectl -n "$ns" get events --sort-by=.lastTimestamp --no-headers 2>/dev/null | tail -"$EVENT_LINES")
  if [ -z "$ev" ]; then
    echo "   (none in the API server - they expire after ~1h)"
    echo "   Older events are in Loki: {job=\"kubernetes-events\"} |= \"$ns\""
  else
    echo "$ev" | cut -c1-150 | sed 's/^/   /'
  fi

  # ------------------------------------------------------------------- logs
  sec "LOGS (last $LOG_LINES lines)"
  local pod
  pod=$(kubectl -n "$ns" get pods --no-headers -o custom-columns=N:.metadata.name 2>/dev/null | head -1)
  if [ -z "$pod" ]; then
    nope "no pod to read logs from"
  else
    kubectl -n "$ns" logs "$pod" --all-containers --tail="$LOG_LINES" 2>&1 | cut -c1-200 | sed 's/^/   /' \
      || nope "kubectl logs $pod"
    # The previous container's tail, which is where a crash loop's cause is.
    local rc
    rc=$(kubectl -n "$ns" get pod "$pod" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
    if [ -n "$rc" ] && [ "$rc" -gt 0 ] 2>/dev/null; then
      sec "PREVIOUS CONTAINER LOGS (restartCount=$rc)"
      kubectl -n "$ns" logs "$pod" --previous --tail="$LOG_LINES" 2>&1 | cut -c1-200 | sed 's/^/   /' \
        || nope "no previous container logs"
    fi
  fi

  # -------------------------------------------------------------- prior art
  sec "PRIOR ART IN docs/doctor-log.md"
  local repo log
  repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
  log="$repo/docs/doctor-log.md"
  if [ ! -f "$log" ]; then
    nope "$log not found"
  else
    local hits
    hits=$(grep -n -i -- "$app" "$log" | grep -E "^[0-9]+:## " | head -6)
    if [ -z "$hits" ]; then
      echo "   (no past incident mentions '$app' in a heading)"
      grep -n -i -- "$app" "$log" | head -4 | cut -c1-140 | sed 's/^/   ~ /'
    else
      echo "$hits" | cut -c1-140 | sed 's/^/   /'
      echo "   read with: sed -n '<line>,+30p' docs/doctor-log.md"
    fi
  fi

  hr
  printf 'Collected, not diagnosed. Nothing above is a conclusion.\n'
}

# ===================================================================== main
if ! have_kubectl; then
  echo "doctor.sh: kubectl not found on PATH" >&2
  exit 1
fi
if ! kubectl version >/dev/null 2>&1 && ! kubectl get --raw /healthz >/dev/null 2>&1; then
  echo "doctor.sh: cannot reach the cluster. Check KUBECONFIG." >&2
  exit 1
fi

if [ $# -eq 0 ]; then cluster_overview; else app_report "$1"; fi
