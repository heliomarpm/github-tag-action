#!/bin/bash

echo tag_generated=0 >> $GITHUB_OUTPUT

# config
with_v=${WITH_V:-false}
release_branches=${RELEASE_BRANCHES:-master}
custom_tag=${CUSTOM_TAG}
source=${SOURCE:-.}

cd ${GITHUB_WORKSPACE}/${source}

pre_release="true"
IFS=',' read -ra branch <<< "$release_branches"
for b in "${branch[@]}"; do
    echo "Is $b a match for ${GITHUB_REF#'refs/heads/'}"
    if [[ "${GITHUB_REF#'refs/heads/'}" =~ $b ]]
    then
        pre_release="false"
    fi
done
echo "pre_release = $pre_release"

# fetch tags
git fetch --tags

# get latest tag that looks like a semver (with or without v)
tag=$(git for-each-ref --sort=-v:refname --count=1 --format '%(refname)' refs/tags/[0-9]*.[0-9]*.[0-9]* refs/tags/v[0-9]*.[0-9]*.[0-9]* | cut -d / -f 3-)
tag_commit=$(git rev-list -n 1 $tag)

echo $tag
last_major=$(semver get major $tag)
last_minor=$(semver get minor $tag)
last_patch=$(semver get patch $tag)
echo last_major=$last_major >> $GITHUB_OUTPUT
echo last_minor=$last_minor >> $GITHUB_OUTPUT
echo last_patch=$last_patch >> $GITHUB_OUTPUT

# get current commit hash for tag
commit=$(git rev-parse HEAD)

if [ "$tag_commit" == "$commit" ]; then
    echo "No new commits since previous tag. Skipping the tag creation..."
    echo last_tag=$tag >> $GITHUB_OUTPUT
    exit 0
fi

# if there are none, start tags at 0.0.0
if [ -z "$tag" ]
then
    log=$(git log --pretty=oneline)
    tag=0.0.0
else
    log=$(git log $tag..HEAD --pretty=oneline)
fi

echo $log

# get commit logs and determine home to bump the version
# supports #major, #minor, #patch
case "$log" in
    *#major* ) 
        new=$(semver bump major $tag)
        bump_ver="major"
        ;;
    *#minor* ) 
        new=$(semver bump minor $tag)
        bump_ver="minor"
        ;;
    *#patch* ) 
        new=$(semver bump patch $tag)
        bump_ver="patch"
        ;;
    * )
        echo "This commit message doesn't include #major, #minor or #patch. Skipping the tag creation..."
        echo last_tag=$tag >> $GITHUB_OUTPUT
        exit 0
        ;;
esac

# did we get a new tag?
if [ ! -z "$new" ]
then
	# prefix with 'v'
	if $with_v
	then
		new="v$new"
	fi

	if $pre_release
	then
		new="$new-${commit:0:7}"
	fi
fi

if [ ! -z $custom_tag ]
then
    new="$custom_tag"
fi

echo $new
major=$(semver get major $new)
minor=$(semver get minor $new)
patch=$(semver get patch $new)

# set outputs
echo last_tag=$tag >> $GITHUB_OUTPUT
echo new_tag=$new >> $GITHUB_OUTPUT
echo major=$major >> $GITHUB_OUTPUT
echo minor=$minor >> $GITHUB_OUTPUT
echo patch=$patch >> $GITHUB_OUTPUT
echo bump_ver=$bump_ver >> $GITHUB_OUTPUT

if $pre_release
then
    echo "This branch is not a release branch. Skipping the tag creation..."
    exit 0
fi

# push new tag ref to github
dt=$(date '+%Y-%m-%dT%H:%M:%SZ')
full_name=$GITHUB_REPOSITORY
git_refs_url=$(jq .repository.git_refs_url $GITHUB_EVENT_PATH | tr -d '"' | sed 's/{\/sha}//g')

echo "$dt: **pushing tag $new to repo $full_name"

curl -s -X POST $git_refs_url \
-H "Authorization: token $GITHUB_TOKEN" \
-d @- << EOF

{
  "ref": "refs/tags/$new",
  "sha": "$commit"
}
EOF
echo tag_generated=1 >> $GITHUB_OUTPUT
