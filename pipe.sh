#!/usr/bin/env bash

set -e

# add atlassian ssh key
mkdir /root/.ssh
cp /opt/atlassian/pipelines/agent/ssh/..data/id_rsa_tmp /root/.ssh/id_rsa
chmod 400 /root/.ssh/id_rsa
cp /opt/atlassian/pipelines/agent/ssh/..data/known_hosts /root/.ssh/known_hosts

# unsafe repository fix
git config --global --add safe.directory /opt/atlassian/pipelines/agent/build

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
if [ -f ".php_cs.cache" ]; then
    mv .php_cs.cache .composer/cache/
fi

# move php_cs ctp cache
if [ -f ".php_cs.ctp.cache" ]; then
    mv .php_cs.ctp.cache .composer/cache/
fi