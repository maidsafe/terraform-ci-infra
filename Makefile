SHELL := /bin/bash
REGISTRY_URI := dkr.ecr.eu-west-2.amazonaws.com
REPO_NAME := gha_runner_create_instance
TAG_NAME := python3.9-v1

infrastructure:
	terraform init
	terraform apply -auto-approve -var-file=secrets.tfvars

.ONESHELL:
build-image:
	security_group_id=$$(terraform output -raw gha_runner_security_group_name | xargs)
	subnet_id=$$(terraform output subnet_name | xargs | awk '{ print $$2 }' | sed s/,//)
	packer init .
	packer build -var="security_group_id=$$security_group_id" \
		-var="subnet_id=$$subnet_id" gha-runner.pkr.hcl

deploy-create-instance-function:
	(
		cd lambda/gha-runner-create-instance/create_instance
		docker build \
			--tag $$AWS_ACCOUNT_NUMBER.${REGISTRY_URI}/${REPO_NAME}:${TAG_NAME} \
			.
	)
	docker push $$AWS_ACCOUNT_NUMBER.${REGISTRY_URI}/${REPO_NAME}:${TAG_NAME}
	(
		security_group_id=$$(terraform output -raw gha_runner_security_group_name | xargs)
		subnet_id=$$(terraform output subnet_name | xargs | awk '{ print $$2 }' | sed s/,//)
		cd lambda/gha-runner-create-instance
		sam deploy \
			--stack-name gha-runner-create-instance \
			--template template.yaml \
			--resolve-image-repos \
			--s3-bucket maidsafe-ci-infra \
			--s3-prefix gha_runner_create_instance_lambda \
			--parameter-overrides Ec2SecurityGroupId=$$security_group_id Ec2VpcSubnetId=$$subnet_id
	)

clean-create-instance-function:
	(
		cd lambda/gha-runner-create-instance
		sam delete --stack-name gha-runner-create-instance --no-prompts --region eu-west-2
	)
