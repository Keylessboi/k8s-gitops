# Secret rotation (policy §12.3; HS-ROT-01, HS-ROT-02).
package rotation

import data.lib
import rego.v1

managed contains key if {
	some o in lib.objects
	o.kind == "DopplerSecret"
	key := sprintf("%s/%s", [o.spec.managedSecret.namespace, o.spec.managedSecret.name])
}

registered(key) if {
	some e in data.registers.secrets
	e.secret == key
}

entry(key) := e if {
	some e in data.registers.secrets
	e.secret == key
}

# HS-ROT-01: every Doppler-managed Secret is in the secrets register, with its
# rotation class. A new secret is not rotatable by accident: someone decides.
deny contains msg if {
	some key in managed
	not registered(key)
	msg := sprintf("HS-ROT-01 DopplerSecret %s is not in security/registers/secrets.yaml (policy §12.3). Add an entry with its origin, rotatable class and reload mode.", [key])
}

consumed(spec) := ({r |
	some c in lib.containers(spec)
	some e in object.get(c, "env", [])
	r := e.valueFrom.secretKeyRef.name
} | {r |
	some c in lib.containers(spec)
	some e in object.get(c, "envFrom", [])
	r := e.secretRef.name
}) | {r |
	some v in object.get(spec, "volumes", [])
	r := v.secret.secretName
}

# HS-ROT-02: a Deployment that uses a secret whose register entry says
# "reload: auto" MUST carry secrets.doppler.com/reload, or a rotation does not
# reach its pods.
deny contains msg if {
	some o in lib.objects
	o.kind == "Deployment"
	spec := o.spec.template.spec
	some name in consumed(spec)
	key := sprintf("%s/%s", [o.metadata.namespace, name])
	e := entry(key)
	e.reload == "auto"
	object.get(object.get(o.metadata, "annotations", {}), "secrets.doppler.com/reload", "") != "true"
	msg := sprintf("HS-ROT-02 Deployment %s uses secret %s (reload: auto) but has no secrets.doppler.com/reload: 'true' annotation", [lib.ref(o), key])
}
