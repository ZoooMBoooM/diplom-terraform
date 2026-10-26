resource "yandex_vpc_network" "net" {
  name = "diplom-net"
}

resource "yandex_vpc_subnet" "subnet" {
  name           = "diplom-subnet"
  zone           = var.zone
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

resource "yandex_vpc_security_group" "app_sg" {
  name        = "diplom-app-sg"
  description = "SSH and application access"
  network_id  = yandex_vpc_network.net.id

  ingress {
    protocol       = "TCP"
    description    = "SSH"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  ingress {
    protocol       = "TCP"
    description    = "Application"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 8080
  }

  egress {
    protocol       = "ANY"
    description    = "All outbound traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
