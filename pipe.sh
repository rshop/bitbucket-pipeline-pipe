#!/usr/bin/env bash

set -e

# add atlassian ssh key
mkdir /root/.ssh
cp /opt/atlassian/pipelines/agent/ssh/..data/id_rsa_tmp /root/.ssh/id_rsa
chmod 400 /root/.ssh/id_rsa
cp /opt/atlassian/pipelines/agent/ssh/..data/known_hosts /root/.ssh/known_hosts

# unsafe repository fix
git config --global --add safe.directory '*'

# move cache folder if present
if [ -d ".composer/cache" ]; then
    # move php_cs cache
    if [ -f ".composer/cache/.php_cs.cache" ]; then
        mv .composer/cache/.php_cs.cache ./
    fi

    # move php_cs ctp cache
    if [ -f ".composer/cache/.php_cs.ctp.cache" ]; then
        mv .composer/cache/.php_cs.ctp.cache ./
    fi

    mv .composer/cache /root/.composer/
fi

# lint
find . -type f -name '*.php' -exec php -l {} \; | (! grep -v "No syntax errors detected" )

# build
composer install --no-interaction --optimize-autoloader

# run fixer and update if modified
php-cs-fixer fix --config=.php_cs.dist
php-cs-fixer fix --config=.php_cs.ctp.dist

# repository
git remote set-url origin $BITBUCKET_GIT_SSH_ORIGIN
git config --add remote.origin.fetch +refs/heads/*:refs/remotes/origin/*
git config --global user.email "git@bitbucket.org"
git config --global user.name "Bitbucket Pipelines"

if [[ ! -z $(git diff) ]]; then
    git commit -a -m "php cs fixer [skip ci]"
    git push
fi

# phpstan
PHPSTAN_LEVEL=${PHPSTAN_LEVEL:="-1"}

if [[ PHPSTAN_LEVEL -ne "-1" ]]; then
    phpstan analyse src -c phpstan.neon --level $PHPSTAN_LEVEL --memory-limit=1G
fi

# phpunit
PHPUNIT=${PHPUNIT:="false"}

if [[ "$PHPUNIT" == "true" ]]; then
    DB_HOST=${DB_HOST:-127.0.0.1}
    DB_USER=${DB_USER:-root}
    DB_PASS=${DB_PASS:-root}
    DB_NAME=${DB_NAME:-app}
    DB_TEST_NAME=${DB_TEST_NAME:-${DB_NAME}_test}

    echo "==> phpunit: waiting for DB at $DB_HOST (up to 30s)"
    for i in $(seq 1 30); do
        if mysql -h "$DB_HOST" -u"$DB_USER" -p"$DB_PASS" -e "SELECT 1" >/dev/null 2>&1; then
            break
        fi
        if [[ $i -eq 30 ]]; then
            echo "DB at $DB_HOST not reachable after 30s" >&2
            mysql -h "$DB_HOST" -u"$DB_USER" -p"$DB_PASS" -e "SELECT 1" >&2 || true
            exit 1
        fi
        sleep 1
    done
    echo "==> phpunit: DB reachable"

    # both connections need the full schema: `default` is what fixtures read table definitions from
    echo "==> phpunit: creating databases and loading tests/schema.sql"
    mysql -h "$DB_HOST" -u"$DB_USER" -p"$DB_PASS" -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`; CREATE DATABASE IF NOT EXISTS \`$DB_TEST_NAME\`"
    mysql -h "$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" < tests/schema.sql
    mysql -h "$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_TEST_NAME" < tests/schema.sql

    echo "==> phpunit: running migrations on both databases"
    DB_HOST="$DB_HOST" DB_USER="$DB_USER" DB_PASS="$DB_PASS" DB_NAME="$DB_NAME" bin/cake migrations migrate
    DB_HOST="$DB_HOST" DB_USER="$DB_USER" DB_PASS="$DB_PASS" DB_NAME="$DB_TEST_NAME" bin/cake migrations migrate

    echo "==> phpunit: running phpunit"
    DB_HOST="$DB_HOST" DB_USER="$DB_USER" DB_PASS="$DB_PASS" DB_NAME="$DB_NAME" DB_TEST_NAME="$DB_TEST_NAME" vendor/bin/phpunit
fi

# merge to devel branch
MERGE_BRANCH=${MERGE_BRANCH:="devel"}

if [[ MERGE_BRANCH -ne "-1" ]]; then
    git fetch origin
    git checkout $MERGE_BRANCH
    git merge --ff-only $BITBUCKET_BRANCH || git merge -m "Merge $BITBUCKET_BRANCH to $MERGE_BRANCH [skip ci]" $BITBUCKET_BRANCH
    git push origin $MERGE_BRANCH

    # check if branches are the same but commits are not
    if [[ -z $(git diff origin/$MERGE_BRANCH origin/$BITBUCKET_BRANCH) ]] && [[ -n $(git log --left-right --graph --cherry-pick --oneline origin/$MERGE_BRANCH...origin/$BITBUCKET_BRANCH) ]]; then
        git checkout $BITBUCKET_BRANCH
        git rebase $MERGE_BRANCH
        git push origin $BITBUCKET_BRANCH
    fi
fi

# full merge to branch
FULL_MERGE_BRANCH=${FULL_MERGE_BRANCH:="-1"}

if [[ FULL_MERGE_BRANCH -ne "-1" ]]; then
    git fetch origin
    git checkout $FULL_MERGE_BRANCH
    git merge -m "Merge $BITBUCKET_BRANCH to $FULL_MERGE_BRANCH" $BITBUCKET_BRANCH
    git push origin $FULL_MERGE_BRANCH
fi

git checkout $BITBUCKET_BRANCH

# move composer for caching purposes
mv /root/.composer/cache .composer/

# move php_cs cache
if [ -f ".php_cs.cache" ] && [ -d ".composer/cache" ]; then
    mv .php_cs.cache .composer/cache/
fi

# move php_cs ctp cache
if [ -f ".php_cs.ctp.cache" ] && [ -d ".composer/cache" ]; then
    mv .php_cs.ctp.cache .composer/cache/
fi