# Data handling and data at rest (policy §5.3, §6, §13; HS-DATA, HS-REST).
package data_handling

import data.lib
import rego.v1

classes := {"c1", "c2", "c3", "c4"}

tiers := {"tier-0", "tier-1", "tier-2", "tier-3"}

label(o, k) := object.get(object.get(o.metadata, "labels", {}), k, "")

ns_class(ns) := label(o, "homelab/data-class") if {
	some o in lib.objects
	o.kind == "Namespace"
	o.metadata.name == ns
}

# HS-DATA-01: each namespace says its data class and tier.
deny contains msg if {
	some o in lib.objects
	o.kind == "Namespace"
	not label(o, "homelab/data-class") in classes
	msg := sprintf("HS-DATA-01 Namespace/%s: label homelab/data-class must be one of %v", [o.metadata.name, sort(classes)])
}

deny contains msg if {
	some o in lib.objects
	o.kind == "Namespace"
	not label(o, "homelab/criticality") in tiers
	msg := sprintf("HS-DATA-01 Namespace/%s: label homelab/criticality must be one of %v", [o.metadata.name, sort(tiers)])
}

# The data-store register maps a storage class to its encryption at rest.
store_for(sc) := e if {
	some e in lib.approved("data-stores")
	sc in object.get(e, "storage_classes", [])
}

pvs := {pv.metadata.name: pv |
	some pv in lib.objects
	pv.kind == "PersistentVolume"
}

pvcs contains o if {
	some o in lib.objects
	o.kind == "PersistentVolumeClaim"
}

pvcs contains t if {
	some o in lib.objects
	o.kind == "StatefulSet"
	some t in object.get(o.spec, "volumeClaimTemplates", [])
}

# No class means the cluster default (local-path). An empty class binds a
# pre-created PersistentVolume; classify it by its backing.
storage_class(p) := sc if {
	sc := object.get(p.spec, "storageClassName", "local-path")
	sc != ""
}

storage_class(p) := "static-nfs" if {
	p.spec.storageClassName == ""
	pvs[p.spec.volumeName].spec.csi.driver == "nfs.csi.k8s.io"
}

storage_class(p) := "static-local" if {
	p.spec.storageClassName == ""
	pvs[p.spec.volumeName].spec["local"]
}

storage_class(p) := "static-pv-not-in-repo" if {
	p.spec.storageClassName == ""
	not pvs[object.get(p.spec, "volumeName", "")]
}

# HS-REST-01: every volume uses a storage class that the data-store register knows.
deny contains msg if {
	some p in pvcs
	not store_for(storage_class(p))
	msg := sprintf("HS-REST-01 PVC %s: storage class %q is not in security/registers/data-stores.yaml", [p.metadata.name, storage_class(p)])
}

# HS-REST-02: C3 and C4 data only on storage that is encrypted at rest.
deny contains msg if {
	some p in pvcs
	ns := object.get(p.metadata, "namespace", "")
	ns_class(ns) in {"c3", "c4"}
	store := store_for(storage_class(p))
	store.at_rest != "encrypted"
	msg := sprintf(
		"HS-REST-02 PVC %s/%s: namespace holds %s data, but storage class %q is %s at rest (data-stores %s)",
		[ns, p.metadata.name, upper(ns_class(ns)), storage_class(p), store.at_rest, store.id],
	)
}

# HS-DATA-02: a secret reaches a container as a file, not an environment
# variable. Environment variables appear in process listings, crash
# reports and `kubectl describe`, and agents are tempted to print them.
warn contains msg if {
	some o in lib.workloads
	some c in lib.containers(lib.pod_spec(o))
	some e in object.get(c, "env", [])
	e.valueFrom.secretKeyRef
	msg := sprintf("HS-DATA-02 %s/%s container %s: secret in environment variable %s", [o.kind, lib.ref(o), c.name, e.name])
}
