package main

test_https_from_internet_is_allowed if {
	count(deny) == 0 with input as {"resource": {"aws_vpc_security_group_ingress_rule": {"web": [{"cidr_ipv4": "0.0.0.0/0", "from_port": 443, "to_port": 443}]}}}
}

test_postgres_from_internet_is_denied if {
	count(deny) == 1 with input as {"resource": {"aws_vpc_security_group_ingress_rule": {"db": [{"cidr_ipv4": "0.0.0.0/0", "from_port": 5432, "to_port": 5432}]}}}
}

test_private_cidr_is_allowed if {
	count(deny) == 0 with input as {"resource": {"aws_vpc_security_group_ingress_rule": {"db": [{"cidr_ipv4": "10.0.0.0/16", "from_port": 5432, "to_port": 5432}]}}}
}

test_inline_ssh_from_internet_is_denied if {
	count(deny) == 1 with input as {"resource": {"aws_security_group": {"legacy": [{"ingress": [{"cidr_blocks": ["0.0.0.0/0"], "from_port": 22, "to_port": 22}]}]}}}
}
