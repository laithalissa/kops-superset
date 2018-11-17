EDITOR=vim
KOPS_IAM_GROUP=kops
KOPS_IAM_USER=kops
KOPS_BUCKET_NAME=some-bucket-name
KOPS_STATE_STORE=s3://${KOPS_BUCKET_NAME}
CLUSTER_NAME=cluster.k8s.local

# create iam group and user for kops
aws iam create-group --group-name ${KOPS_IAM_GROUP}
aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess --group-name ${KOPS_IAM_GROUP}
aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonRoute53FullAccess --group-name ${KOPS_IAM_GROUP}
aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess --group-name ${KOPS_IAM_GROUP}
aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/IAMFullAccess --group-name ${KOPS_IAM_GROUP}
aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess --group-name ${KOPS_IAM_GROUP}
aws iam create-user --user-name ${KOPS_IAM_USER}
aws iam add-user-to-group --user-name ${KOPS_IAM_USER} --group-name ${KOPS_IAM_GROUP}
aws iam create-access-key --user-name ${KOPS_IAM_USER}
# grab the output of the last command and set it using aws config

# once that is in place, then set the env vars since kops needs them:
export AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)
export AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)

# create a bucket with versioning enabled
aws s3 mb s3://${KOPS_BUCKET_NAME} --region eu-west-2
aws s3api put-bucket-versioning --bucket ${KOPS_BUCKET_NAME} --versioning-configuration Status=Enabled

# create a pair of ssh keys if you dont have them using ssh-keygen
# create a simple non-HA cluster configuration
kops create cluster --zones eu-west-2b \
                    --node-count 20 \
                    --node-size m4.xlarge \
                     --ssh-public-key ./keys/k8s.pub  ${CLUSTER_NAME}

# get the cluster and instancegroups configuration
mkdir -p ./specs
kops get cluster --name $NAME -o yaml > ./specs/cluster.yaml
kops get ig --name $NAME -o yaml > ./specs/nodes.yaml

# check the specs and change whatever is needed
# to check spot prices use:
# aws --region=eu-west-2 ec2 describe-spot-price-history \
#     --instance-types m4.xlarge \
#     --start-time=$(date +%s) \
#     --product-descriptions="Linux/UNIX" \ 
#     --query 'SpotPriceHistory[*].{az:AvailabilityZone, price:SpotPrice}' 
#
# for example add maxPrice:"0.08" to request spot instances for the nodes
# and then set the specs on the cluster
kops replace -f ./specs/nodes.yaml --name ${CLUSTER_NAME}
kops replace -f ./specs/cluster.yaml --name ${CLUSTER_NAME}

# create the cluster and wait for a while
kops update cluster --name ${CLUSTER_NAME} --yes

# check the state of the nodes with
kubectl get nodes

# once the cluster is up, optionally install tiller
helm init
helm version

# if the above fails, this might fix it:
kubectl create serviceaccount --namespace kube-system tiller
kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
kubectl patch deploy --namespace kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'

# optional: install helm
helm init

