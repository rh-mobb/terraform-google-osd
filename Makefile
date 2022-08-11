# Terraform parameters
ENVIRONMENT       := lab
TERRAFORM         := terraform
OCM               := ocm
JQ                := jq
# TF_FILES_PATH     := src
TF_BACKEND_CONF   := configuration/backend
TF_VARIABLES      := configuration/tfvars

all: init changes deploy ocm_install

init: 
	$(info Initializing Terraform...)
	$(TERRAFORM) init \
		-backend-config="$(TF_BACKEND_CONF)/$(ENVIRONMENT).conf" $(TF_FILES_PATH)

changes: 
	$(info Get changes in infrastructure resources...)
	$(TERRAFORM) plan \
		-var-file="$(TF_VARIABLES)/terraform.tfvars" \
		-out "output/tf.$(ENVIRONMENT).plan" \

deploy: changes
	$(info Deploying infrastructure...)
	$(TERRAFORM) apply \
		output/tf.$(ENVIRONMENT).plan

ocm_test:
	$(info Testing ocm connectivity)
	$(OCM) get /api/clusters_mgmt/v1/clusters --parameter search="name like '$(TF_VAR_clustername)%'" | $(JQ) -r '.items[].name' || (echo 'Cluster not found')

ocm_install:
	$(OCM) create cluster $(TF_VAR_clustername) --provider gcp \
		--vpc-name $$($(TERRAFORM) output -raw vpc_name) \
		--region $$($(TERRAFORM) output -raw gcp_region) \
		--control-plane-subnet $$($(TERRAFORM) output -raw control_plane_subnet) \
		--compute-subnet $$($(TERRAFORM) output -raw compute_subnet) \
		--service-account-file $(GCP_SA_FILE) \
		--ccs

destroy: init ocm_destroy terraform_destroy

ocm_destroy: ocm_test
	$(OCM) delete cluster $$($(OCM) get /api/clusters_mgmt/v1/clusters --parameter search="name like '$(TF_VAR_clustername)%'" | $(JQ) -r '.items[].id')

terraform_destroy:
	$(info Destroying infrastructure...)
	$(TERRAFORM) destroy \
		-auto-approve \
		-var-file="$(TF_VARIABLES)/terraform.tfvars"
	$(RM) -r .terraform
	$(RM) -r output/tf.$(ENVIRONMENT).plan
	$(RM) -r state/terraform*
	$(RM) -r .terraform.lock.hcl

clean:
	$(info Cleaning unused files...)
	$(RM) -r .terraform
	$(RM) -r output/tf.$(ENVIRONMENT).plan
	$(RM) -r state/terraform*
	$(RM) -r .terraform.lock.hcl
