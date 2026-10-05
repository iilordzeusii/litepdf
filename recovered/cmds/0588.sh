tools github list-repos --limit 100 --json | jq -r '.repos[]|[.full_name,.private,.language,.description]|@tsv' | head -60; tools help github.get-file-content | head -25
