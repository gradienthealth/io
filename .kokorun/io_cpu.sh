#!/usr/bin/env bash
# Copyright 2019 The TensorFlow Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# ==============================================================================
# Make sure we're in the project root path.
SCRIPT_DIR=$( cd ${0%/*} && pwd -P )
ROOT_DIR=$( cd "$SCRIPT_DIR/.." && pwd -P )
if [[ ! -d "tensorflow_io" ]]; then
    echo "ERROR: PWD: $PWD is not project root"
    exit 1
fi

set -x -e

PLATFORM="$(uname -s | tr 'A-Z' 'a-z')"

if [[ ${PLATFORM} == "darwin" ]]; then
    N_JOBS=$(sysctl -n hw.ncpu)
else
    N_JOBS=$(grep -c ^processor /proc/cpuinfo)
fi

echo ""
echo "Bazel will use ${N_JOBS} concurrent job(s)."
echo ""

export CC_OPT_FLAGS='-mavx'
export TF_NEED_CUDA=0 # TODO: Verify this is used in GPU custom-op

export PYTHON_BIN_PATH=`which python`

python --version
python -m pip --version
docker  --version

## Set test services
bash -x -e tests/test_ignite/start_ignite.sh
bash -x -e tests/test_kafka/kafka_test.sh start kafka
bash -x -e tests/test_kinesis/kinesis_test.sh start kinesis
bash -x -e tests/test_pubsub/pubsub_test.sh start pubsub
bash -x -e tests/test_prometheus/prometheus_test.sh start
bash -x -e tests/test_azure/start_azure.sh
bash -x -e tests/test_dicom/dicom_samples.sh download
bash -x -e tests/test_dicom/dicom_samples.sh extract

export TENSORFLOW_INSTALL="$(python setup.py --package-version)"
PYTHON_VERSION=$(python -c 'import sys; print(str(sys.version_info[0]))')
if [[ $PYTHON_VERSION == "2" ]]; then
    ## Python 2
    docker run -i --rm -v $PWD:/v -w /v --net=host buildpack-deps:14.04 bash -x -e .travis/python.release.sh "${TENSORFLOW_INSTALL}" python

    docker run -i --rm -v $PWD:/v -w /v --net=host buildpack-deps:16.04 bash -x -e .travis/wheel.test.sh python

    ## Stop then restart prometheus
    bash -x -e tests/test_prometheus/prometheus_test.sh stop
    bash -x -e tests/test_prometheus/prometheus_test.sh start

    docker run -i --rm -v $PWD:/v -w /v --net=host buildpack-deps:18.04 bash -x -e .travis/wheel.test.sh python

    ## R
    docker run -i --rm -v $PWD:/v -w /v --net=host -e GITHUB_PAT=9eecea9200150af1ec29f70bb067575eb2e56fc7 buildpack-deps:18.04 bash -x -e .travis/wheel.r.test.sh

    sudo rm -rf dist wheelhouse

    ## TF 2.0
    docker run -i --rm -v $PWD:/v -w /v --net=host buildpack-deps:14.04 bash -x -e .travis/python.release.sh "tensorflow==2.0.0b1" --preview ${KOKORO_BUILD_NUMBER} python

    ## Stop then restart prometheus
    bash -x -e tests/test_prometheus/prometheus_test.sh stop
    bash -x -e tests/test_prometheus/prometheus_test.sh start

    docker run -i --rm -v $PWD:/v -w /v --net=host buildpack-deps:16.04 bash -x -e .travis/wheel.test.sh python

    ## Stop then restart prometheus
    bash -x -e tests/test_prometheus/prometheus_test.sh stop
    bash -x -e tests/test_prometheus/prometheus_test.sh start

    docker run -i --rm -v $PWD:/v -w /v --net=host buildpack-deps:18.04 bash -x -e .travis/wheel.test.sh python
else
    ## Python 2
    docker run -i --rm -v $PWD:/v -w /v --net=host buildpack-deps:14.04 bash -x -e .travis/python.release.sh "${TENSORFLOW_INSTALL}" python3.5 python3.6

    ## Stop then restart prometheus
    bash -x -e tests/test_prometheus/prometheus_test.sh stop
    bash -x -e tests/test_prometheus/prometheus_test.sh start

    docker run -i --rm -v $PWD:/v -w /v --net=host buildpack-deps:16.04 bash -x -e .travis/wheel.test.sh python3.5

    ## Stop then restart prometheus
    bash -x -e tests/test_prometheus/prometheus_test.sh stop
    bash -x -e tests/test_prometheus/prometheus_test.sh start

    docker run -i --rm -v $PWD:/v -w /v --net=host buildpack-deps:18.04 bash -x -e .travis/wheel.test.sh python3.6

    sudo rm -rf dist wheelhouse

    ## TF 2.0
    docker run -i --rm -v $PWD:/v -w /v --net=host buildpack-deps:14.04 bash -x -e .travis/python.release.sh "tensorflow==2.0.0b1" --preview ${KOKORO_BUILD_NUMBER} python3.5 python3.6

    ## Stop then restart prometheus
    bash -x -e tests/test_prometheus/prometheus_test.sh stop
    bash -x -e tests/test_prometheus/prometheus_test.sh start

    docker run -i --rm -v $PWD:/v -w /v --net=host buildpack-deps:16.04 bash -x -e .travis/wheel.test.sh python3.5

    ## Stop then restart prometheus
    bash -x -e tests/test_prometheus/prometheus_test.sh stop
    bash -x -e tests/test_prometheus/prometheus_test.sh start

    docker run -i --rm -v $PWD:/v -w /v --net=host buildpack-deps:18.04 bash -x -e .travis/wheel.test.sh python3.6
fi

## In case there are any files generated by docker with root user
sudo chown -R $(id -nu):$(id -ng) .

exit $?
