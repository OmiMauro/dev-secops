package main

test_small_postgres_is_allowed if {
	count(deny) == 0 with input as {"resource": {"aws_db_instance": {"main": [{"engine": "postgres", "instance_class": "db.t4g.micro"}]}}}
}

test_mysql_is_denied if {
	count(deny) == 1 with input as {"resource": {"aws_db_instance": {"main": [{"engine": "mysql", "instance_class": "db.t4g.micro"}]}}}
}

test_huge_instance_is_denied if {
	count(deny) == 1 with input as {"resource": {"aws_db_instance": {"main": [{"engine": "postgres", "instance_class": "db.r6g.16xlarge"}]}}}
}
