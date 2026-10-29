data "yandex_compute_image" "debian" {
  family = "ubuntu-2404-lts-oslogin"
}

resource "yandex_compute_instance" "vm" {
  name        = "diplom-vm"
  platform_id = "standard-v3"
  zone        = var.zone

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }

  scheduling_policy {
    preemptible = false
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.debian.id
      size     = 20
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.app_sg.id]
  }

  metadata = {
    serial-port-enable = "1"
    ssh-keys           = "ubuntu:${file("/root/.ssh/github_actions_diplom.pub")}"

    user-data = templatefile("${path.module}/cloud-init.yaml", {
      ssh_public_key = trimspace(file("/root/.ssh/github_actions_diplom.pub"))
    })
  }
}
