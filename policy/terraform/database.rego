# Organization rules for databases:
#   - PostgreSQL is the only supported engine (one engine to patch,
#     monitor and back up).
#   - Only approved instance sizes, so a typo cannot create a 5,000 $/month
#     database. Cost is also a security concern: it is how crypto miners
#     on stolen accounts get noticed.
package main

allowed_engines := {"postgres"}

allowed_instance_classes := {"db.t4g.micro", "db.t4g.small", "db.t4g.medium"}

deny contains msg if {
	some name, instances in input.resource.aws_db_instance
	some db in instances
	not db.engine in allowed_engines
	msg := sprintf("aws_db_instance.%s: engine %q is not allowed, use one of %v", [name, db.engine, allowed_engines])
}

deny contains msg if {
	some name, instances in input.resource.aws_db_instance
	some db in instances
	not db.instance_class in allowed_instance_classes
	msg := sprintf("aws_db_instance.%s: instance_class %q is not approved, use one of %v", [name, db.instance_class, allowed_instance_classes])
}
