# Caches (ADR-0015; HS-CACHE). A cache is a disposable copy of data whose
# source of truth is somewhere else. It has one owner, and only the owner
# writes to it or clears it.
package cache

import data.lib
import rego.v1

label(o, k) := object.get(object.get(o.metadata, "labels", {}), k, "")

annotation(o, k) := object.get(object.get(o.metadata, "annotations", {}), k, "")

ns_of(o) := object.get(o.metadata, "namespace", "")

caches contains o if {
	some o in lib.objects
	o.kind == "PersistentVolumeClaim"
	label(o, "homelab/role") == "cache"
}

claims(w) := {v.persistentVolumeClaim.claimName |
	some v in object.get(lib.pod_spec(w), "volumes", [])
	v.persistentVolumeClaim
}

# HS-CACHE-01: a cache volume names its owner and where the real data lives.
deny contains msg if {
	some c in caches
	label(c, "homelab/cache-owner") == ""
	msg := sprintf("HS-CACHE-01 PVC %s: a cache needs the label homelab/cache-owner (the one workload that may mount it)", [lib.ref(c)])
}

deny contains msg if {
	some c in caches
	annotation(c, "homelab/cache-source") == ""
	msg := sprintf("HS-CACHE-01 PVC %s: a cache needs the annotation homelab/cache-source (where the source of truth is)", [lib.ref(c)])
}

# HS-CACHE-02: no workload except the owner mounts a cache volume.
deny contains msg if {
	some w in lib.workloads
	some c in caches
	ns_of(c) == ns_of(w)
	c.metadata.name in claims(w)
	w.metadata.name != label(c, "homelab/cache-owner")
	msg := sprintf("HS-CACHE-02 %s/%s mounts cache PVC %s, but its owner is %q", [w.kind, lib.ref(w), lib.ref(c), label(c, "homelab/cache-owner")])
}
