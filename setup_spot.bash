# Run this script by source setup_movo.bash
if [[ ! $PWD = *robotdev ]]; then
    echo "You must be in the root directory of the robotdev repository."
    return 1
else
    . "./tools.sh"
fi
repo_root=$PWD

# Path to Spot workspace, relative to repository root;
# No begin or trailing slash.
SPOT_PATH="spot"

# Set the ID of the Spot you are working on. Either
# 12 (stands for 12070012) or 2 (stands for 12210002)
SPOT_ID="12"
if [ $SPOT_ID != "12" ] && [ $SPOT_ID != "2" ]; then
    echo "Invalid SPOT ID. Either 12 (stands for 12070012) or 2 (stands for 12210002)."
    return 1
fi

# Configure the IP addresses for different network connections
SPOT_ETH_IP="10.0.0.3"
SPOT_WIFI_IP="192.168.80.3"
SPOT_RLAB_IP="138.16.161.${SPOT_ID}"

#------------- FUNCTIONS  ----------------
# Always assume at the start of a function,
# or any if clause, the working directory is
# the root directory of the repository.
# Detect your Spot connection.
function detect_spot_connection
{
    # Detects the spot connection by pinging.
    # Sets two variables, 'spot_conn' and 'spot_ip'
    echo -e "Pinging Spot WiFi IP $SPOT_WIFI_IP..."
    if ping_success $SPOT_WIFI_IP; then
        echo -e "OK"
        spot_conn="spot wifi"
        spot_ip=$SPOT_WIFI_IP
        true && return
    fi

    echo -e "Pinging Spot Ethernet IP $SPOT_ETH_IP..."
    if ping_success $SPOT_ETH_IP; then
        echo -e "OK"
        spot_conn="ethernet"
        spot_ip=$SPOT_ETH_IP
        true && return
    fi

    echo -e "Pinging Spot RLAB IP $SPOT_RLAB_IP..."
    if ping_success $SPOT_RLAB_IP; then
        echo -e "OK"
        spot_conn="rlab"
        spot_ip=$SPOT_RLAB_IP
        true && return
    fi

    echo "Cannot connect to Spot"
    spot_conn=""
    spot_ip=""
    false
}

function build_spot
{
    cd $repo_root/${SPOT_PATH}

    if catkin_make\
        --cmake-args\
        -DCMAKE_BUILD_TYPE=Release\
        -DPYTHON_EXECUTABLE=/usr/bin/python3\
        -DPYTHON_INCLUDE_DIR=/usr/include/python3.8\
        -DPYTHON_LIBRARY=/usr/lib/x86_64-linux-gnu/libpython3.8.so\
        $1; then
        echo "SPOT SETUP DONE." >> src/.DONE_SETUP
    else
        rm src/.DONE_SETUP
    fi
}

function ping_spot
{
    if [ -z $SPOT_IP ]; then
        echo -e "It appears that Spot is not connected"
    else
        ping $SPOT_IP
    fi
}

# Add a few alias for pinging spot.
#------------- Main Logic  ----------------

# We have only tested Spot stack with Ubuntu 20.04.
if ! ubuntu_version_equal 20.04; then
    echo "SPOT development requires Ubuntu 16.04 and ROS kinetic. Abort."
    return 1
fi

# need to use ros for the following commands
if ! useros; then
    echo "Cannot use ROS. Abort."
    exit 1
fi  # so that catkin_make is available for build_ros_ws

# Creates spot workspace.
# create the spot workspace directory
if [ ! -d "${SPOT_PATH}/src" ]; then
    mkdir -p ${SPOT_PATH}/src
fi

# create a dedicated virtualenv for spot workspace
if [ ! -d "${SPOT_PATH}/venv/spot" ]; then
    cd ${SPOT_PATH}/
    virtualenv -p python3 venv/spot
    cd ..
fi

# activate virtualenv; Note that this is the only
# functionality of this script if spot has been setup
# before.
source ${SPOT_PATH}/venv/spot/bin/activate

if first_time_build spot; then
    pip uninstall em
    pip install empy catkin-pkg rospkg defusedxml
    pip install pyqt5
    pip install PySide2
    pip install bosdyn-client bosdyn-mission bosdyn-api bosdyn-core
    pip install rosdep
    # other necessary packages
    pip install numpy
    pip install pydot
    pip install graphviz
    pip install opencv-python

    # rosdep install dependencies
    rosdep update
    rosdep install --from-paths src --ignore-src -y

    # install pykdl, needed by tf2_geometry_msgs
    sudo apt-get install python3-pykdl

    # other ROS utlities/packages
    sudo apt-get install ros-noetic-rqt-graph
    sudo apt-get install ros-noetic-rqt-tf-tree
    sudo apt-get install ros-noetic-navigation
    sudo apt-get install ros-noetic-gmapping
    sudo apt-get install ros-noetic-kdl-parser-py

    # Mapping library
    sudo apt install ros-noetic-rtabmap-ros
    sudo apt-get install ros-noetic-octomap-rviz-plugins
fi

# catkin make and end.
if first_time_build spot; then
    build_spot
else
    echo -e "If you want to build the spot project, run 'build_spot'"
fi

export ROS_PACKAGE_PATH=$repo_root/${SPOT_PATH}/src/:${ROS_PACKAGE_PATH}
export PYTHONPATH=""
source $repo_root/${SPOT_PATH}/devel/setup.bash
# We'd like to use packages in the virtualenv, what's already on /usr/lib,
# and in the workspace (done by above step). NOTE: Using /usr/lib is
# necessary so that PyKDL can be imported (it could only be installed
# via sudo apt-get install python3-pykdl, for some unknown reason).
export PYTHONPATH="$repo_root/${SPOT_PATH}/venv/spot/lib/python3.8/site-packages:${PYTHONPATH}:/usr/lib/python3/dist-packages"
if confirm "Are you working on the real robot ?"; then
    # Check if the environment variable SPOT_IP is set.
    # If not, then try to detect spot connection and set it.
    if [ -z $SPOT_IP ]; then
       if detect_spot_connection; then
           export SPOT_IP=${spot_ip}
           export SPOT_CONN=${spot_conn}
       fi
    fi

    # If Spot is connected, then SPOT_IP should be set.
    if [ -z $SPOT_IP ]; then
        echo -e "Unable to connect to spot."
    else
        if ping_success $SPOT_IP; then
            echo -e "Spot connected! IP: ${SPOT_IP}; Method: ${SPOT_CONN}"
        else
            echo -e "Spot connection lost."
            export SPOT_IP=""
            export SPOT_CONN=""
        fi
    fi

    # Load the spot passwords
    source $repo_root/.spot_passwd
fi
cd $repo_root