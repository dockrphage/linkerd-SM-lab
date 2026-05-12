Vagrant.configure("2") do |config|
  # Disable vbguest auto-install
  config.vbguest.auto_update = false
  config.vbguest.no_install = true

  nodes = {
    "cp1"     => { host: "192.168.56.10", bridge: "192.168.1.50" },
    "worker1" => { host: "192.168.56.21", bridge: "192.168.1.61" },
    "worker2" => { host: "192.168.56.22", bridge: "192.168.1.62" },
    "minio"   => { host: "192.168.56.30", bridge: "192.168.1.70" }
  }

  BRIDGE_IFACE = "wlp0s20f3"
  config.vm.box = "ubuntu/jammy64"

  nodes.each do |name, nets|
    config.vm.define name do |node|
      node.vm.hostname = name

      # Host-only network
      node.vm.network "private_network",
        ip: nets[:host],
        virtualbox__promiscuous_mode: "allow-all"

      # Bridged network (static IP)
      node.vm.network "public_network",
        ip: nets[:bridge],
        bridge: BRIDGE_IFACE

      # MinIO extra network
      if name == "minio"
        node.vm.network "private_network",
          ip: "10.10.10.12",
          virtualbox__promiscuous_mode: "allow-all"
      end

      node.vm.provider "virtualbox" do |vb|
        vb.memory = (name == "cp1" || name == "minio") ? 2048 : 1536
        vb.cpus   = (name == "cp1" || name == "minio") ? 2 : 1
      end

      node.vm.synced_folder ".", "/vagrant"
    end
  end
end
