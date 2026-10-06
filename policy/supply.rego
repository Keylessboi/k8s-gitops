# Supply chain (policy §15; HS-WL-01).
package supply

import data.lib
import rego.v1

unpinned(o) := {c.image |
	some c in lib.containers(lib.pod_spec(o))
	not contains(c.image, "@sha256:")
}

# HS-WL-01: report each workload with images that have no digest pin. A
# warning until the pinning work (POA&M item 25) is done; then a deny.
warn contains msg if {
	some o in lib.workloads
	count(unpinned(o)) > 0
	msg := sprintf("HS-WL-01 %s/%s: images without a digest: %v", [o.kind, lib.ref(o), sort(unpinned(o))])
}

# A floating tag is never acceptable.
deny contains msg if {
	some o in lib.workloads
	some img in unpinned(o)
	floating(img)
	msg := sprintf("HS-WL-01 %s/%s: image %s uses a floating tag", [o.kind, lib.ref(o), img])
}

floating(img) if endswith(img, ":latest")

floating(img) if {
	not contains(img, "@")
	parts := split(img, "/")
	not contains(parts[count(parts) - 1], ":")
}
