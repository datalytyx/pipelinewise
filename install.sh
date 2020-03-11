#!/bin/bash

# Exit script on first error
set -e

# Capture start_time
start_time=`date +%s`

# Source directory defined as location of install.sh
SRC_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Install pipelinewise venvs in the present working directory
PIPELINEWISE_HOME=$(pwd)
VENV_DIR=${PIPELINEWISE_HOME}/.virtualenvs

check_license() {
    python3 -m pip install pip-licenses

    echo
    echo "Checking license..."
    PKG_NAME=`pip-licenses | grep $1 | awk '{print $1}'`
    PKG_VERSION=`pip-licenses | grep $1 | awk '{print $2}'`
    PKG_LICENSE=`pip-licenses --from mixed | grep $1 | awk '{for (i=1; i<=NF-2; i++) $i = $(i+2); NF-=2; print}'`

    # Any License Agreement that is not Apache Software License (2.0) has to be accepted
    MAIN_LICENSE="Apache Software License"
    if [[ $PKG_LICENSE != $MAIN_LICENSE && $PKG_LICENSE != 'UNKNOWN' ]]; then
        echo
        echo "  | $PKG_NAME ($PKG_VERSION) is licensed under $PKG_LICENSE"
        echo "  |"
        echo "  | WARNING. The license of this connector is different than the default PipelineWise license ($MAIN_LICENSE)."

        if [[ $ACCEPT_LICENSES != "YES" ]]; then
            echo "  | You need to accept the connector's license agreement to proceed."
            echo "  |"
            read -r -p "  | Do you accept the [$PKG_LICENSE] license agreement of $PKG_NAME connector? [y/N] " response
            case "$response" in
                [yY][eE][sS]|[yY])
                    ;;
                *)
                    echo
                    echo "EXIT. License agreement not accepted"
                    exit 1
                    ;;
            esac
        else
            echo "  | You automatically accepted this license agreement by running this script with --acceptlicenses option."
        fi

    fi
}

clean_virtualenvs() {
    echo "Cleaning previous installations in $VENV_DIR"
    rm -rf $VENV_DIR
}

make_virtualenv() {
    echo "Making Virtual Environment for [$1] in $VENV_DIR"
    python3 -m venv $VENV_DIR/$1
    source $VENV_DIR/$1/bin/activate
    python3 -m pip install --upgrade pip
    rm -rf ~/.cache/pip
    if [ -f "requirements.txt" ]; then
        python3 -m pip install -r requirements.txt
    fi
    if [ -f "setup.py" ]; then
        PIP_ARGS=
        if [[ ! $NO_TEST_EXTRAS == "YES" ]]; then
            PIP_ARGS=$PIP_ARGS"[test]"
        fi

        python3 -m pip install -e .$PIP_ARGS
    fi

    check_license $1
    deactivate
}

install_connector() {
    echo
    echo "--------------------------------------------------------------------------"
    echo "Installing $1 connector..."
    echo "--------------------------------------------------------------------------"

    CONNECTOR_DIR=$SRC_DIR/singer-connectors/$1
    if [[ ! -d $CONNECTOR_DIR ]]; then
        echo "ERROR: Directory not exists and does not look like a valid singer connector: $CONNECTOR_DIR"
        exit 1
    fi

    cd $CONNECTOR_DIR
    make_virtualenv $1
    if [ $1 == "tap-s3-csv" ]; then
        apply_fix $1
    fi
}

clone_connector() {
    echo
    echo "--------------------------------------------------------------------------"
    echo "Cloning $1 connector..."
    echo "--------------------------------------------------------------------------"
    cd $SRC_DIR/singer-connectors/$1
    URL=$(head -n 1 git-clone.txt)
    cd $VENV_DIR
    if [ ! -d $VENV_DIR/$1 ]; then
        git clone $URL
        rm -rf $VENV_DIR/.git
    fi
    apply_fix tap-mssql
}

apply_fix() {
  if [ $1 == "tap-mssql" ]; then
    cp $SRC_DIR/singer-connectors/$1/catalog.clj $VENV_DIR/$1/src/tap_mssql/
    cp $SRC_DIR/singer-connectors/$1/messages.clj $VENV_DIR/$1/src/tap_mssql/singer
  elif [ $1 == "tap-s3-csv" ]; then
    cd $VENV_DIR/$1/lib
    PYTHON_VERSION=`ls -d *|head -n 1`
    PACKAGE_NAME=${1//-/_}
    cp -a $SRC_DIR/singer-connectors/$1/files/. $VENV_DIR/$1/lib/$PYTHON_VERSION/site-packages/$PACKAGE_NAME/
  fi
}

print_installed_connectors() {
    cd $SRC_DIR

    echo
    echo "--------------------------------------------------------------------------"
    echo "Installed components:"
    echo "--------------------------------------------------------------------------"
    echo
    echo "Component            Version"
    echo "-------------------- -------"

    for i in `ls $VENV_DIR`; do
      if [ $i != "tap-mssql" ]; then
          source $VENV_DIR/$i/bin/activate
          VERSION=`python3 -m pip list | grep $i | awk '{print $2}'`
      else
          VERSION=`sed -n 3p $VENV_DIR/$i/CHANGELOG.md | cut -c4-`
      fi
      printf "%-20s %s\n" $i "$VERSION"

    done

    if [[ $CONNECTORS != "all" ]]; then
        echo
        echo "WARNING: Not every singer connector installed. If you are missing something use the --connectors=...,... argument"
        echo "         with an explicit list of required connectors or use the --connectors=all to install every available"
        echo "         connector"
    fi
}

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        # Auto accept license agreemnets. Useful if PipelineWise installed by an automated script
        --acceptlicenses)
            ACCEPT_LICENSES="YES"
            ;;
        # Do not print usage information at the end of the install
        --nousage)
            NO_USAGE="YES"
            ;;
        # Install with test requirements that allows running tests
        --notestextras)
            NO_TEST_EXTRAS="YES"
            ;;
        # Install extra connectors
        --connectors=*)
            CONNECTORS="${arg#*=}"
            shift
            ;;
        # Clean previous installation
        --clean)
            clean_virtualenvs
            exit 0
            ;;
        *)
            echo "Invalid argument: $arg"
            exit 1
            ;;
    esac
done

# Welcome message
cat $SRC_DIR/motd

# Install PipelineWise core components
cd $SRC_DIR
make_virtualenv pipelinewise

# Set default and extra singer connectors
DEFAULT_CONNECTORS=(
    tap-jira
    tap-kafka
    tap-mssql
    tap-mysql
    tap-postgres
    tap-s3-csv
    tap-salesforce
    tap-snowflake
    tap-zendesk
    target-s3-csv
    target-snowflake
    target-redshift
    transform-field
)
EXTRA_CONNECTORS=(
    tap-adwords
    tap-oracle
    target-postgres
)

# Install only the default connectors if --connectors argument not passed
if [[ -z $CONNECTORS ]]; then
    for i in ${DEFAULT_CONNECTORS[@]}; do
        if [ $i == "tap-mssql" ]; then
            clone_connector tap-mssql
        else
            install_connector $i
        fi

    done


# Install every avaliable connectors if --connectors=all passed
elif [[ $CONNECTORS == "all" ]]; then
    for i in ${DEFAULT_CONNECTORS[@]}; do
        if [ $i == "tap-mssql"]; then
            clone_connector tap-mssql
        else
            install_connector $i
        fi
    done
    for i in ${EXTRA_CONNECTORS[@]}; do
        install_connector $i
    done

# Install the selected connectors if --connectors argument passed
elif [[ ! -z $CONNECTORS ]]; then
    OLDIFS=$IFS
    IFS=,
    for connector in $CONNECTORS; do
      if [ $connector == "tap-mssql"]; then
          clone_connector tap-mssql
      else
          install_connector $connector
      fi
    done
    IFS=$OLDIFS
fi

# Capture end_time
end_time=`date +%s`
echo
echo "--------------------------------------------------------------------------"
echo "PipelineWise installed successfully in $((end_time-start_time)) seconds"
echo "--------------------------------------------------------------------------"

print_installed_connectors
if [[ $NO_USAGE != "YES" ]]; then
    echo
    echo "To start CLI:"
    echo " $ source $VENV_DIR/pipelinewise/bin/activate"
    echo " $ export PIPELINEWISE_HOME=$PIPELINEWISE_HOME"

    echo " $ pipelinewise status"
    echo
    echo "--------------------------------------------------------------------------"
fi
