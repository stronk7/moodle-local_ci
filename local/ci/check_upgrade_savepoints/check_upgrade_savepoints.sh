#!/bin/bash
# $gitdir: Directory containing git repo
# $gitbranch: Branch we are going to check

# file where results will be sent
resultfile=$WORKSPACE/check_upgrade_savepoints_${gitbranch}.txt
echo -n > "$resultfile"

# calculate some variables
mydir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# checkout pristine copy of the configure branch
cd $gitdir && git checkout $gitbranch && git reset --hard origin/$gitbranch

# copy the checker to the gitdir
cp $mydir/check_upgrade_savepoints.php $gitdir/

# Run the savpoints checker utility, saving results to file
/opt/local/bin/php $gitdir/check_upgrade_savepoints.php > "$resultfile"

# remove the checker from gitdir
rm -fr $gitdir/check_upgrade_savepoints.php

# Look for ERROR or WARN in the resultsfile
count=`grep -P "ERROR|WARN" "$resultfile" | wc -l`
# Number of incorrect whitespace has grown
if (($count > 0))
then
    exit 1
fi
exit 0
