#!/bin/bash

set -e
set -o pipefail

OPTS_SHORT=h,C:,c:
OPTS_LONG=help,directory:,command:
POD_MOUNT_PATH=/mnt/models
SCRIPT_NAME="$(basename $0)"

help() {
    echo "
Upload files to the models file share in Azure.

Usage: $SCRIPT_NAME [OPTION...] <model path> [DIR|FILES...]

  -C, --directory=DIR  Change to directory before copying files. Use to remove path prefixes.
  -c, --command=CMD    Execute command after upload for post processing. Multiple commands
                       supported by ; and &&.

  <model path>         The path to upload files to. Will be /mnt/models/<model path> in the
                       pod file system.

Example:
    $0 -c \"mv meta-data/* .\" -C ../OasisPiWind/ OasisLMF/PiWind/1 \\
        meta-data/model_settings.json oasislmf.json model_data/ keys_data/
                       Upload files from ../OasisPiWind/ to OasisLMF/PiWind/1 in the Azure
                       model file share. Once uploaded move all files in meta-data to the root.
"
    exit 2
}

opts=$(getopt -a -n "$SCRIPT_NAME" --options $OPTS_SHORT --longoptions $OPTS_LONG -- "$@")

eval set -- "$opts"

while :
do
  case "$1" in
    -C | --directory )
      pushd "$2" > /dev/null
      shift 2
      ;;
    -c | --command )
      command="$2"
      shift 2
      ;;
    -h | --help)
      help
      exit 2
      ;;
    --)
      shift;
      break
      ;;
    *)
      echo "Unexpected option: $1"
      exit 1
      ;;
  esac
done


if [ "${#@}" -lt 2 ]; then
  echo oh no
  exit
fi

export MODEL_PATH="${POD_MOUNT_PATH}/$1/"
shift

pod_name="model-copy-${RANDOM}"

if kubectl get pod $pod_name &> /dev/null; then
  echo "Pod exists"
  exit 1
else
  echo "Creating pod..."

  kubectl apply -f - << EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${pod_name}
spec:
  containers:
    - name: alpine
      image: alpine:3.15
      volumeMounts:
        - name: oasis-models-azure-file
          mountPath: $POD_MOUNT_PATH
      command: ["sh", "-c", "mkdir -p ${MODEL_PATH} && while [ ! -f /tmp/shutdown ]; do sleep 0.5; done"]
  volumes:
    - name: oasis-models-azure-file
      csi:
        driver: file.csi.azure.com
        volumeAttributes:
          secretName: oasis-storage-account
          shareName: models
  restartPolicy: Never
EOF
fi

kubectl wait pods $pod_name --for condition=Ready --timeout=30s
tar cvf - ${@} | kubectl exec -i $pod_name -- tar xf - -C "${MODEL_PATH}/"

if [ -n "$command" ]; then
  kubectl exec $pod_name -- sh -c "cd ${MODEL_PATH} && $command"
fi

kubectl exec $pod_name -- touch /tmp/shutdown
kubectl delete pod $pod_name --grace-period=5
