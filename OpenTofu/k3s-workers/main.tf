
terraform {
  required_providers {
    proxmox = {
      source = "registry.opentofu.org/bpg/proxmox"
      version = "0.59.1"
    }
  }
}

provider "proxmox" {
  endpoint = "[REDACTED]"
  username = "[REDACTED]"

  ssh {
    agent    = true
    username = "[REDACTED]"
    # uses SSH agent to be switched to pkey somewhere in the time
  }
}

resource "proxmox_virtual_environment_pool" "workerpool" {
  comment = "Agentpool Managed by Terraform"
  pool_id = "agentpool"
}

data "local_sensitive_file" "ssh_public_key" {
  filename = "[REDACTED]"
}

data "local_sensitive_file" "homecert"{
  filename = "[REDACTED]"
}

resource "proxmox_virtual_environment_file" "debian_init" {
  content_type = "snippets"
  datastore_id = "[REDACTED]"
  node_name    =  var.node_name

  source_raw {
    data = <<EOF
#cloud-config
manage_etc_hosts: true
packages:
  - qemu-guest-agent
users:
    - name: maciek
      sudo: ALL=(ALL) NOPASSWD:ALL
      lock_passwd: true
      ssh-authorized-keys:
      - ${trimspace(data.local_sensitive_file.ssh_public_key.content)}
      shell: /bin/bash
package_upgrade: false
ca_certs:
  remove_defaults: true
  trusted:
    -|
      ${indent(6,data.local_sensitive_file.homecert.content)}
power_state:
    delay: 1
    mode: reboot
    message: Rebooting after cloud-init completion
    condition: true
EOF
    file_name = "ubuntu.cloud-config.yaml"
  }
}



resource "proxmox_virtual_environment_vm" "k3s-worker-node" {

  count       = var.node_count
  pool_id     =  proxmox_virtual_environment_pool.workerpool.pool_id
  name        = "tvm-k8s-${count.index + 1}-tfnode"
  description = "Managed by Terraform"
  tags        = ["terraform", "k8s", "k8s-disposable"]

  node_name = var.node_name
  vm_id     = "600${count.index + 5}"


  cpu {
    cores = var.vCPU
    type = "host"
  }

  memory {
    dedicated = var.RAM

  }


  agent {
    enabled = true
  }

  startup {
    order      = "3"
    up_delay   = "60"
    down_delay = "60"
  }

  #Boot drive
  disk { 
    datastore_id = var.local_storage_name
    file_id      = "local:iso/Rocky-9-GenericCloud-LVM-9.4-20240523.0.x86_64.img"
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = 60
    file_format  = "raw"
  }



#Additional storage

  disk { 
    datastore_id = var.local_storage_name
    interface    = "virtio1"
    iothread     = true
    discard      = "on"
    size         = 20
    file_format  = "raw"
  }

  initialization {
    dns {
      servers = ["[REDACTED]"]
      domain = "[REDACTED]"
    }
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
    datastore_id = var.local_storage_name
    user_data_file_id = proxmox_virtual_environment_file.debian_init.id
  }

  network_device {
    bridge = "vmbr0"
  }

  operating_system {
    type = "l26"
  }

    serial_device {
    
  }

  vga {
    type = "serial0"
  }

  keyboard_layout = "no"

  lifecycle {
    ignore_changes = [
      network_device,
    ]
  }

}

resource "null_resource" "hostname_setter" {
  count = var.node_count

  provisioner "remote-exec" {
    inline = ["sudo hostnamectl set-hostname tvm-k3s-${count.index + 1}-tf"]
    connection {
      type        = "ssh"
      user        = "[REDACTED]"  
      private_key = file(var.private_key_path)
      host        = element([for ip in flatten(proxmox_virtual_environment_vm.k3s-worker-node[count.index].ipv4_addresses) : ip if ip != "127.0.0.1"], 0)
    }
  }
  depends_on = [proxmox_virtual_environment_vm.k3s-worker-node]
}

resource "null_resource" "k3s_installer" {
  count = var.node_count

  provisioner "remote-exec" {
    inline = ["sudo curl -sfL https://get.k3s.io | K3S_URL=${var.k3s_control_node}:6443 K3S_TOKEN=${var.jointoken} sh -"]
    connection {
      type        = "ssh"
      user        = "[REDACTED]"  
      private_key = file(var.private_key_path)
      host        = element([for ip in flatten(proxmox_virtual_environment_vm.k3s-worker-node[count.index].ipv4_addresses) : ip if ip != "127.0.0.1"], 0)
    }
  }
  depends_on = [proxmox_virtual_environment_vm.k3s-worker-node]
}
