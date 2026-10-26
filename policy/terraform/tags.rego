# Organization rule: every AWS resource must say which project it belongs
# to and who owns it. Enforced through the provider's default_tags, which
# Terraform copies to every resource.
package main

required_tags := {"Project", "Owner"}

deny contains msg if {
	some provider in input.provider.aws
	tags := object.get(provider, ["default_tags", 0, "tags"], {})
	missing := required_tags - {key | some key, _ in tags}
	count(missing) > 0
	msg := sprintf("aws provider: default_tags is missing required tags %v", [missing])
}
