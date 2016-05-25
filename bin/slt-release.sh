#!/bin/sh

exec << "___"
usage: slt-release [-hup] [VERSION]

Options:
  h   print this helpful message
  u   update the origin with a git push
  p   publish the package to npmjs.org

If VERSION is specified it must be a valid SemVer version (`x.y.z`)
or a valid version increment:
  major, minor, patch, premajor, preminor, or prepatch

If VERSION is NOT specified, then the version field in package.json is
used.

slt-release will abort if:
 - the tag matching the version already exists
 - the version has already been published
 - the version is not a valid SemVer string

Typical usage, if you want to examine the results before updating github
and npmjs.org:

  slt-release 1.2.3

If at this point you want to publish, follow the instructions slt-release
gave in the output, which will be something along the lines of:

  git checkout v1.2.3
  npm publish
  git checkout master
  git push origin master:master v1.2.3:v1.2.3

If you wish to abort or abandon the release, you will need to revert the
changes and delete the tag:

  git checkout master
  git reset --hard origin/master
  git tag -d v1.2.3

If you are comfortable with having slt-release perform the `git push` and
`npm publish` steps for you, you can use the -u and -p flags and slt-release
will do them for you.

  slt-release -up 1.2.3
___

while getopts hnup f
do
  case $f in
    h)  cat; exit 0;;
    u)  export SLT_RELEASE_UPDATE=y;;
    n)  export SLT_RELEASE_PUBLISH=y;; # For backwards compatibility
    p)  export SLT_RELEASE_PUBLISH=y;;
  esac
done
shift `expr $OPTIND - 1`

case $1 in
  "")
    V=$(slt info version)
    ;;
  major|minor|patch|premajor|preminor|prepatch)
    INC=$1
    CURRENT=$(slt info version)
    V=$(slt semver -i $INC $CURRENT)
    ;;
  *)
    V=$1
    ;;
esac

# Ensure V is never prefixed with v, but TAG always is
V=${V#v}
TAG="v$V"
MAJOR_V=${V%%.*}
NAME=$(slt info name)

if [ -z "$V" ]; then
  echo "Missing version, try \`slt-release -h\` for help."
  exit 1
elif ! slt semver $V; then
  echo "Invalid version given: $V"
  exit 1
elif git show-ref --tags --quiet $TAG; then
  echo "Tag already exists: $TAG"
  exit 1
elif [ "$(npm info $NAME@$V .version)" = "$V" ]; then
  echo "$NAME@$V already published (but not tagged in git)"
  exit 1
fi

set -e

# Our starting point, so we can return to that branch when we are done
# If HEAD is also what we are releasing, we merge it back in.
if BASE=$(git symbolic-ref --short -q HEAD)
then
  echo "Releasing $BASE as $V (tagged as $TAG)..."
else
  echo "Detached HEAD detected. You must be on a branch to cut a release"
  exit 1
fi

echo "Creating temporary local release branch 'release/$V' from $BASE"
git fetch origin
git checkout -b release/"$V" "$BASE"

echo "Updating CHANGES.md"
slt-changelog --version "$V"

echo "Updating package version to $V"
slt version set "$V"

echo "Committing package and CHANGES for v$V"
if [ -e .sl-blip.js ]; then
  git add .sl-blip.js
fi
git add $(git ls-files bower.json) package.json CHANGES.md
slt-changelog --summary --version $V | git commit -F-
slt-changelog --summary --version $V | git tag -a "$TAG" -F-

echo "Checking out starting branch"
git checkout "$BASE"

echo "Updating $BASE.."
# --ff: Prefer fast-forward merge, but fallback to real merge if necessary.
# NOTE: Use release/X here instead of the tag because you can't actually do a
# fast-forward merge to an annotated tag because it is actually a discrete
# object and not merely a ref to a commit!
git merge --ff --no-edit release/"$V"

# Need -D because master has not been pushed to origin/master. If we auto-push,
# we can change it to --delete, but I think it does no harm to use -D.
git branch -D release/"$V"

if [ "$SLT_RELEASE_UPDATE" = "y" ]
then
  echo "Pushing tag $TAG and branch $BASE to origin"
  git push origin $TAG:$TAG $BASE:$BASE
else
  echo "Push tag $TAG and branche $BASE to origin"
  echo "  git push origin $TAG:$TAG $BASE:$BASE"
fi

if [ "$SLT_RELEASE_PUBLISH" = "y" ]
then
  echo "Publishing to $(npm config get registry)"
  git checkout "$TAG"
  # npm uses .gitignore if there is no .npmignore, so we'll use that as
  # our starting point if there isn't already a .npmigore file
  if test -f ".gitignore" -a ! -f ".npmignore"; then
    cp .gitignore .npmignore
  fi
  if test "$(slt info get . publishConfig.export-tests)" != "true"; then
    # ignore the entire test tree
    echo "test" >> .npmignore
  fi
  echo ".travis.yml" >> .npmignore
  npm publish
  git checkout "$BASE"
else
  echo "Publish to npmjs.com when ready:"
  echo "  git checkout $TAG && npm publish"
fi
