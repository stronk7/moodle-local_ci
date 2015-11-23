#!/bin/bash
# $gitcmd: Path to the git CLI executable
# $gitdir: Directory containing git repo
# $initialcommit: hash of the initial commit
# $finalcommit: hash of the final commit
# $componentspath: full path to a valid list of components.

# List the modified moodle components in a git repository between 2 commits.
# A two ways calculation is used:
#   1) For each modified file, its @package phpdoc tags are evaluated.
#   2) For each modified file, its path is evaluated against a valid list of
#      components (previously generated and stored with list_valid_components).

# Don't be strict. Script has own error control handle
set +e

# Verify everything is set
required="gitcmd gitdir initialcommit finalcommit componentspath"
for var in $required; do
    if [ -z "${!var}" ]; then
        echo "Error: ${var} environment variable is not defined. See the script comments."
        exit 1
    fi
done

# calculate some variables
mydir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd ${gitdir}

# verify initial commit exists
${gitcmd} rev-parse --quiet --verify ${initialcommit} > /dev/null
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    echo "Error: initial commit does not exist (${initialcommit})"
    exit 1
fi

# verify final commit exists
${gitcmd} rev-parse --quiet --verify ${finalcommit} > /dev/null
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    echo "Error: final commit does not exist (${finalcommit})"
    exit 1
fi

# verify initial commit is ancestor of final commit
${gitcmd} merge-base --is-ancestor ${initialcommit} ${finalcommit} > /dev/null 2>&1
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    echo "Error: unrelated commits are not comparable (${initialcommit} and ${finalcommit})"
    exit 1
fi

# get all the files changed between both commits (no matter the diffs are empty)
files=$(git log --name-only --pretty=oneline --full-index ${initialcommit}..${finalcommit} | \
            grep -vE '^[0-9a-f]{40} ' | sort | uniq)

# init list components
components=" "

# look for all the different @package tags used in the file
for file in ${files}; do
    comps=$(grep '@package ' ${file} | sed 's/^[^p]*@package *\([a-z][a-z1-9_]*\)/\1/' | uniq)
    # add the new packages found to the list of components
    for comp in ${comps}; do
        if [[ ! ${components} =~ " ${comp} " ]]; then
            # before adding it, verify it is a valid component
            valid=$(grep ",${comp}," ${componentspath} | wc -l)
            if [[  ${valid} -eq 1 ]]; then
                components="${components}${comp} "
            fi
        fi
    done
done

# now look for the path of the file
for file in ${files}; do
    directory=$(dirname "${gitdir}/${file}")
    comp=$(grep -m1 ",${directory}\$" ${componentspath} | sed 's/^.*,\([a-z][a-z1-9_]*\),.*/\1/')
    if [[ -n ${comp} ]]; then
        if [[ ! ${components} =~ " ${comp} " ]]; then
            components="${components}${comp} "
        fi
    fi
done

# print all the resulting components
for component in ${components}; do
    echo ${component}
done
