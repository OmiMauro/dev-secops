# Organization rule: nothing is opened to the whole internet except HTTPS.
# Checkov flags some open ports (22, 3389...); this rule is stricter and
# covers every port.
package main

open_cidrs := {"0.0.0.0/0", "::/0"}

# Standalone ingress rules (the recommended style).
deny contains msg if {
	some name, rules in input.resource.aws_vpc_security_group_ingress_rule
	some rule in rules
	object.get(rule, "cidr_ipv4", object.get(rule, "cidr_ipv6", "")) in open_cidrs
	not is_https_only(rule)
	msg := sprintf("aws_vpc_security_group_ingress_rule.%s: only port 443 may be open to the internet", [name])
}

# Inline ingress blocks inside aws_security_group.
deny contains msg if {
	some name, groups in input.resource.aws_security_group
	some group in groups
	some rule in object.get(group, "ingress", [])
	some cidr in array.concat(object.get(rule, "cidr_blocks", []), object.get(rule, "ipv6_cidr_blocks", []))
	cidr in open_cidrs
	not is_https_only(rule)
	msg := sprintf("aws_security_group.%s: only port 443 may be open to the internet", [name])
}

is_https_only(rule) if {
	rule.from_port == 443
	rule.to_port == 443
}
