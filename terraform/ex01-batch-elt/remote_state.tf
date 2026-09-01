# Reads foundation's declared outputs. This also enforces the order: if
# foundation has not been applied, this fails immediately with a clear message.
data "terraform_remote_state" "foundation" {
  backend = "local"
  config = {
    path = "../foundation/terraform.tfstate"
  }
}

locals {
  fnd = data.terraform_remote_state.foundation.outputs
}
