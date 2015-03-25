#!/bin/bash
# $WORKSPACE: Path to the directory where output and temporal stuff will be created
# $phpcmd: Path to the PHP CLI executable
# $psqlcmd: Path to the psql CLI executable
# $mysqlcmd: Path to the mysql CLI executable
# $gitcmd: Path to the git CLI executable
# $phantomjscmd: Path to the phantomjs executable
# $seleniumcmd: Path to the selenium executable
# $gitdir: Directory containing git repo
# $gitremote: Remote we want to run the tests against (moodle, integration)
# $gitbranch: Branch we are going to install the DB
# $dblibrary: Type of library (native, pdo...)
# $dbtype: Name of the driver (mysqli...)
# $dbhost: DB host
# $dbuser: DB user
# $dbpass: DB password
# $wwwrootbehat: Base moodle URL where the behat site is served
# $extraconfig: Extra settings that will be injected ti config.php
# $parallelruns: Number of parallel runs to perform (1-8)
# $webdriverinstances: Number of webdriver instances to use (1-8)
# $webdrivertype: Webdriver implementation to use (selenium of phantomjs)
# $behatprofile: Behat profile to use

# Don't be strict. Script has own error control handle
set +e

# Apply some defaults
dblibrary=${dblibrary:-native}
extraconfig=${extraconfig:-// No extra config.}
parallelruns=${parallelruns:-1}
webdriverinstances=${webdriverinstances:-1}
webdrivertype=${webdrivertype:-phantomjs}
behatprofile=${behatprofile:-phantomjswd}

# Verify everything is set
required="WORKSPACE phpcmd psqlcmd mysqlcmd gitcmd phantomjscmd seleniumcmd gitdir gitremote gitbranch dbtype dbhost dbuser dbpass wwwrootbehat"
for var in $required; do
    if [ -z "${!var}" ]; then
        echo "Error: ${var} environment variable is not defined. See the script comments."
        exit 1
    fi
done

# file to capture execution output
outputfile=${WORKSPACE}/run_behattests.out
# file where results will be sent
resultfile=${WORKSPACE}/run_behattests.xml

# calculate some variables
mydir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
installdb=ci_behat_${BUILD_NUMBER}_${EXECUTOR_NUMBER}
datadir=${WORKSPACE}/ci_dataroot_${BUILD_NUMBER}_${EXECUTOR_NUMBER}
datadirbehat=${WORKSPACE}/ci_dataroot_behat_${BUILD_NUMBER}_${EXECUTOR_NUMBER}
dumperrorsbehat=${WORKSPACE}/run_dumperrors

# Also, we need phantomjs in the path, so add them.
export PATH=${PATH}:$(dirname ${phantomjscmd})

# Decide the type of webdriver to launch
webdrivertemplatecmd=
if [[ "${webdrivertype}" == "phantomjs" ]]; then
    webdrivertemplatecmd="${phantomjscmd} --webdriver=%%WDPORT%% --disk-cache=yes"
elif [[ "${webdrivertype}" == "selenium" ]]; then
    webdrivertemplatecmd="${seleniumcmd} -Djava.net.preferIPv4Stack=true -browserTimeout 360 -timeout 360 -port %%WDPORT%%"
else
    echo "Error: unsupported webdriver (${webdrivertype})."
    exit 1
fi

# Verify that webdrivertype && behatprofile are compatible
echo "TODO: Verify that webdrivertype && behatprofile are compatible"

# First of all, we need a clean clone of moodle.git in the repository,
# verify if it's there or no.
cd "${gitdir}"
if [[ ! -d ".git" ]]; then
    echo "Warn: git not found, proceeding to clone git://git.moodle.org/moodle.git"
    rm -fr "${gitdir}"/*
    ${gitcmd} clone git://git.moodle.org/moodle.git "${gitdir}" -o moodle
fi

# Define the integration.git if does not exist.
cd "${gitdir}"
if ! $(git remote -v | grep -q '^integration[[:space:]]]*git:.*integration.git'); then
    echo "Warn: integration remote not found, adding git://git.moodle.org/integration.git"
    ${gitcmd} remote add integration git://git.moodle.org/integration.git
fi

# Now, ensure the repository in completely clean.
echo "Cleaning git directory"
cd "${gitdir}"
${gitcmd} clean -dfx -e composer.phar -e behat_parallel_timing.json
${gitcmd} reset --hard

# Checkout pristine copy of the configured remote and branch.
cd "${gitdir}"
${gitcmd} fetch --all --prune
if [[ ! $(${gitcmd} checkout ${gitbranch}) ]]; then
    ${gitcmd} branch ${gitbranch} moodle/${gitbranch}
    ${gitcmd} checkout ${gitbranch}
fi
${gitcmd} reset --hard ${gitremote}/${gitbranch}

# prepare the composer stuff needed to run this job
echo "Updating composer stuff"
. ${mydir}/../prepare_composer_stuff/prepare_composer_stuff.sh

# install the default behat timing file if it's not there
if [[ ! -f "${gitdir}/behat_parallel_timing.json" ]]; then
    echo "Copying default behat timing file"
    cp "${mydir}/behat_parallel_timing.json.default" "${gitdir}/behat_parallel_timing.json"
fi

# Going to install the $gitbranch database
# Create the database
# Based on $dbtype, execute different DB creation commands (mysqli, pgsql)
echo "Creating ${dbtype} database: ${installdb}"
if [[ "${dbtype}" == "pgsql" ]]; then
    export PGPASSWORD=${dbpass}
    ${psqlcmd} -h ${dbhost} -U ${dbuser} -d template1 \
        -c "CREATE DATABASE ${installdb} ENCODING 'utf8'"
elif [[ "${dbtype}" == "mysqli" ]]; then
    ${mysqlcmd} --user=${dbuser} --password=${dbpass} --host=${dbhost} \
        --execute="CREATE DATABASE ${installdb} CHARACTER SET utf8 COLLATE utf8_bin"
else
    echo "Error: Incorrect dbtype=${dbtype}"
    exit 1
fi
# Error creating DB, we cannot continue. Exit
exitstatus=${PIPESTATUS[0]}
if [ $exitstatus -ne 0 ]; then
    echo "Error creating database $installdb to run phpunit tests"
    exit $exitstatus
fi

# About to start the installation of the testing site(s)
cd "${gitdir}"
rm -fr "${gitdir}"/config.php
rm -fr "${resultfile}"
rm -fr "${outputfile}"
rm -fr "${dumperrorsbehat}"
rm -fr "${WORKSPACE}"/rerun*

# To execute the behat tests we don't need a real site installed, just the behat-prefixed one.
# For now we are using a template config.php containing all the required vars and settings.
replacements="%%DBLIBRARY%%#${dblibrary}
%%DBTYPE%%#${dbtype}
%%DBHOST%%#${dbhost}
%%DBUSER%%#${dbuser}
%%DBPASS%%#${dbpass}
%%DBNAME%%#${installdb}
%%DATADIR%%#${datadir}
%%WWWROOTBEHAT%%#${wwwrootbehat}
%%DATADIRBEHAT%%#${datadirbehat}
%%DUMPERRORSBEHAT%%#${dumperrorsbehat}"

# Apply template transformations
text="$( cat ${mydir}/config.php.template )"
for i in ${replacements}; do
    text=$( echo "${text}" | sed "s#${i}#g" )
done

# Apply extra configuration separatedly (multiline...)
text=$( echo "${text}" | perl -0pe "s!%%EXTRACONFIG%%!${extraconfig}!g" )

# Calculate the $CFG->behat_parallel_run information
runsinformation=
runtemplate=$(cat <<EOF
    array(
        'wd_host' => 'http://127.0.0.1:%%WDPORT%%',
    ),
EOF
)
for (( i=0; i < ${parallelruns}; i++ )); do
    # Calculate the wd port to use (4444 and next)
    wdport=$((4444 + ( ${i} % ${webdriverinstances} )))
    # Apply the wd port to use
    runinformation="$( echo "${runtemplate}" | perl -0pe "s!%%WDPORT%%!${wdport}!g" )"
    # Acummulate elements
    runsinformation+="${runinformation}\n"
done

# Apply the runsinformation
text="$( echo "${text}" | perl -0pe "s!%%PARALLELBEHAT%%!${runsinformation}!g" )"

# Save the config.php into destination
echo "${text}" > ${gitdir}/config.php
# Copy the behat_profiles.php file
cp -pr "${mydir}/behat_profiles.php" "${gitdir}/"

# Create the moodledata & dumperrors dirs
mkdir -p "${datadir}" && chmod 777 "${datadir}"
mkdir -p "${datadirbehat}" && chmod 777 "${datadirbehat}"
mkdir -p "${dumperrorsbehat}" && chmod 777 "${dumperrorsbehat}"

# Install all the required sites
cd "${gitdir}"
${phpcmd} admin/tool/behat/cli/init.php --parallel=${parallelruns}

# Launch the required webdrivers
pidstokill=
for (( i=0; i < ${webdriverinstances}; i++ )); do
    # Calculate the wd port to use (4444 and next)
    wdport=$((4444 + ( ${i} % ${webdriverinstances} )))
    # Apply the wd port to use
    webdrivercmd="$( echo "${webdrivertemplatecmd}" | perl -0pe "s!%%WDPORT%%!${wdport}!g" )"
    echo "TODO: Verify if the ports are already in use"
    # Launch the webdriver in the background and save its pid
    nohup ${webdrivercmd} > /tmp/workspace/selenium$wdport.log 2>&1 &
    pidstokill+="$! "
    sleep 3
done

# Print execution information
echo "TODO: Print all the information being used (db, remote, branch, parallels, webdrivers, profile..."

# Launch the execution of behat runs
${phpcmd} ${gitdir}/admin/tool/behat/cli/run.php \
    --profile=${behatprofile} \
    --rerun="${WORKSPACE}/rerunNUMBER.txt" \
    --replace="NUMBER" \
    --lang="en" 2>&1 | tee "${outputfile}"

# Something failed, need to rerun it once to lower errors
echo "TODO: Support reruns"

echo "TODO: Control exitstatus everywhere"

# Kill webdriver instances
for pid in ${pidstokill}; do
    kill -9 ${pid} > /dev/null 2>&1
done

# Drop the databases and delete files
# Based on $dbtype, execute different DB deletion commands (pgsql, mysqli)
echo "Dropping ${dbtype} database: ${installdb}"
if [[ "${dbtype}" == "pgsql" ]]; then
    export PGPASSWORD=${dbpass}
    ${psqlcmd} -h ${dbhost} -U ${dbuser} -d template1 \
        -c "DROP DATABASE ${installdb}"
elif [[ "${dbtype}" == "mysqli" ]]; then
    ${mysqlcmd} --user=${dbuser} --password=${dbpass} --host=${dbhost} \
        --execute="DROP DATABASE ${installdb}"
else
    echo "Error: Incorrect dbtype=${dbtype}"
    exit 1
fi

echo "Removing dataroot files"
rm -fr "${datadir}"
rm -fr "${datadirbehat}"*

# If arrived here, return the exitstatus of the php execution
exit $exitstatus
