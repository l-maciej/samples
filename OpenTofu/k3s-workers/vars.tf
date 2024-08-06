variable "node_name" {
    type        = string
    default     = "[REDACTED]"
}

variable "local_storage_name"{
    type = string
    default = "[REDACTED]"
}

variable "local_nonlvm_storage_name"{
    type = string
    default = "[REDACTED]"
}
variable "node_count" {
    type = number
    default = 1
}

variable "private_key_path" {
    type = string
    default=""
}

variable "jointoken" {
    type = string
    default=""
}

variable "k3s_control_node" {
    type = string
    default=""
}


variable "vCPU" {
    type = number
    default = 2
}

variable "RAM" {
    type = number
    default = 1024
}
