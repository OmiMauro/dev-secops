package main

test_provider_with_all_tags_passes if {
	count(deny) == 0 with input as {"provider": {"aws": [{"default_tags": [{"tags": {"Project": "x", "Owner": "y"}}]}]}}
}

test_provider_missing_owner_is_denied if {
	count(deny) == 1 with input as {"provider": {"aws": [{"default_tags": [{"tags": {"Project": "x"}}]}]}}
}

test_provider_without_default_tags_is_denied if {
	count(deny) == 1 with input as {"provider": {"aws": [{"region": "eu-west-1"}]}}
}
