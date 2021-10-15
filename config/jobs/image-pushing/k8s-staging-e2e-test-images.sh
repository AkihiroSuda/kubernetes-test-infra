#!/usr/bin/env bash
# Copyright 2020 The Kubernetes Authors.
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

set -o errexit

readonly OUTPUT="$(dirname $0)/k8s-staging-e2e-test-images.yaml"
readonly IMAGES=(
    agnhost
    apparmor-loader
    busybox
    cuda-vector-add
    cuda-vector-add-old
    echoserver
    glusterdynamic-provisioner
    httpd
    httpd-new
    ipc-utils
    jessie-dnsutils
    kitten
    metadata-concealment
    nautilus
    nginx
    nginx-new
    node-perf/tf-wide-deep
    node-perf/npb-ep
    node-perf/npb-is
    nonewprivs
    nonroot
    perl
    pets/redis-installer
    pets/peer-finder
    pets/zookeeper-installer
    redis
    regression-issue-74839
    resource-consumer
    sample-apiserver
    sample-device-plugin
    volume/iscsi
    volume/rbd
    volume/nfs
    volume/gluster
    windows-servercore-cache
)

cat >"${OUTPUT}" <<EOF
# Automatically generated by k8s-staging-e2e-test-images.sh.

postsubmits:
  kubernetes/kubernetes:
EOF

for image in "${IMAGES[@]}"; do
    cat >>"${OUTPUT}" <<EOF
    - name: post-kubernetes-push-e2e-${image//\//-}-test-images
      rerun_auth_config:
        github_team_slugs:
          - org: kubernetes
            slug: release-managers
          - org: kubernetes
            slug: test-infra-admins
        github_users:
          - aojea
          - chewong
          - claudiubelu
      cluster: k8s-infra-prow-build-trusted
      annotations:
        testgrid-dashboards: sig-testing-images, sig-k8s-infra-gcb
      decorate: true
      # we only need to run if the test images have been changed.
      run_if_changed: '^test\/images\/${image//\//\\/}\/'
      branches:
        - ^master$
      spec:
        serviceAccountName: gcb-builder
        containers:
          - image: gcr.io/k8s-staging-test-infra/image-builder:v20211014-7ca1952a94
            command:
              - /run.sh
            args:
              # this is the project GCB will run in, which is the same as the GCR
              # images are pushed to.
              - --project=k8s-staging-e2e-test-images
              # This is the same as above, but with -gcb appended.
              - --scratch-bucket=gs://k8s-staging-e2e-test-images-gcb
              - --env-passthrough=PULL_BASE_REF,PULL_BASE_SHA,WHAT
              - --build-dir=.
              - test/images
            env:
              # By default, the E2E test image's WHAT is all-conformance.
              # We override that with the ${image} image.
              - name: WHAT
                value: "${image}"
EOF
done

cat >>"${OUTPUT}" <<EOF

periodics:
  # NOTE(claudiub): The base image for the Windows E2E test images is nanoserver.
  # In most cases, that is sufficient. But in some cases, we are missing some DLLs.
  # We can fetch those DLLs from Windows servercore images, but they are very large
  # (2GB compressed), while the DLLs are only a few megabytes in size. We can build
  # a monthly DLL cache image and use the cache instead.
  # For more info: https://github.com/kubernetes/kubernetes/pull/93889
  - name: kubernetes-e2e-windows-servercore-cache
    rerun_auth_config:
      github_team_slugs:
        - org: kubernetes
          slug: test-infra-admins
        - org: kubernetes
          slug: release-managers
      github_users:
        - aojea
        - chewong
        - claudiubelu
    # Since the servercore image is updated once per month, we only need to build this
    # cache once per month.
    interval: 744h
    cluster: k8s-infra-prow-build-trusted
    annotations:
      testgrid-dashboards: sig-testing-images, sig-k8s-infra-gcb
    decorate: true
    extra_refs:
      # This also becomes the current directory for run.sh and thus
      # the cloud image build.
      - org: kubernetes
        repo: kubernetes
        base_ref: master
    spec:
      serviceAccountName: gcb-builder
      containers:
        - image: gcr.io/k8s-staging-test-infra/image-builder:v20211014-7ca1952a94
          command:
            - /run.sh
          args:
            - --project=k8s-staging-e2e-test-images
            - --scratch-bucket=gs://k8s-staging-e2e-test-images-gcb
            - --env-passthrough=PULL_BASE_REF,PULL_BASE_SHA,WHAT
            - --build-dir=.
            - test/images
          env:
            # We need to emulate a pull job for the cloud build to work the same
            # way as it usually does.
            - name: PULL_BASE_REF
              value: master
            # By default, the E2E test image's WHAT is all-conformance. We override that with
            # the windows-servercore-cache image.
            - name: WHAT
              value: "windows-servercore-cache"
EOF
