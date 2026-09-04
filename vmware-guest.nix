{ config, pkgs, lib, ... }:

{
  # ---------------------------------------------------------------------------
  # 1. VMware Guest Integration & Tools (open-vm-tools)
  # ---------------------------------------------------------------------------
  virtualisation.vmware.guest = {
    enable = true;

    # Explicitly disable headless mode so full open-vm-tools (with clipboard
    # sharing, drag-and-drop, and resolution auto-resizing) is installed
    # even before a desktop environment / display manager is active.
    headless = false;
  };

  # X11 / Xorg video driver (provides vmware display driver and vmmouse)
  services.xserver.videoDrivers = [ "vmware" ];

  # ---------------------------------------------------------------------------
  # 2. Kernel Modules & Early Boot (KMS / Paravirtualized I/O)
  # ---------------------------------------------------------------------------
  # Early Kernel Mode Setting (KMS) for VMware SVGA II to avoid display blinks / black screens
  boot.initrd.kernelModules = [ "vmwgfx" ];

  # Ensure paravirtualized SCSI (PVSCSI), VMXNET3 10GbE network, and VSOCK communication
  # are available during stage 1 initrd
  boot.initrd.availableKernelModules = [ "vmw_pvscsi" "vmxnet3" "vsock" ];

  # ---------------------------------------------------------------------------
  # 3. Graphics & 3D Acceleration (SVGA3D / Gallium3D)
  # ---------------------------------------------------------------------------
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # ---------------------------------------------------------------------------
  # 4. Storage & Memory Optimization (Eliminate VM Stutter)
  # ---------------------------------------------------------------------------
  # Weekly TRIM/UNMAP on virtual disks to reclaim deleted blocks on host SSD (prevents .vmdk bloat)
  services.fstrim.enable = true;

  # In-RAM compressed swap (zram) to prevent sluggish disk paging thrashing host disk I/O
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  # Sysctl tuning to eliminate large write-burst pauses ("I/O stalls") inside the VM
  boot.kernel.sysctl = {
    # Start flushing dirty pages to virtual disk sooner and continuously
    "vm.dirty_background_ratio" = 5;
    "vm.dirty_ratio" = 10;

    # Favor keeping application memory in RAM over swapping
    "vm.swappiness" = 10;

    # Cache directory / inode lookups aggressively for snappy filesystem operations
    "vm.vfs_cache_pressure" = 50;
  };

  # ---------------------------------------------------------------------------
  # 5. Power Management (Prevent VM Sleep / Freeze)
  # ---------------------------------------------------------------------------
  # VMs should never sleep or suspend internally; guest sleep causes virtual display and NIC freezes.
  # Suspending should only ever be done from the VMware host UI.
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  # Keep guest vCPUs responsive; host physical CPU handles power savings
  powerManagement.cpuFreqGovernor = lib.mkDefault "performance";

  # ---------------------------------------------------------------------------
  # 6. VMware Shared Folders (HGFS)
  # ---------------------------------------------------------------------------
  # Ensure FUSE allows non-root user access
  programs.fuse.userAllowOther = true;

  # Create mount directory with proper permissions
  systemd.tmpfiles.rules = [
    "d /mnt/hgfs 0775 root users -"
  ];

  # Mount VMware Shared Folders (.host:/) to /mnt/hgfs for seamless host-guest file editing.
  # Includes `nofail` so boot is never blocked if host sharing is disabled.
  fileSystems."/mnt/hgfs" = {
    device = ".host:/";
    fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
    options = [
      "umask=22"
      "uid=1000"
      "gid=100"       # 'users' group in NixOS
      "allow_other"
      "auto_unmount"
      "defaults"
      "nofail"
    ];
  };

  # ---------------------------------------------------------------------------
  # 7. Host Network Sharing (Samba SMB + WS-Discovery + Avahi mDNS)
  # ---------------------------------------------------------------------------
  # Makes NixOS guest files appear directly under "Network" in Windows Explorer,
  # accessible as \\nixos-btw.local\home or \\<vm-ip>\home with full read/write access.

  # mDNS responder: allows Windows host to resolve `nixos-btw.local` without a static IP
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  # Samba file sharing
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "nixos-btw";
        "netbios name" = "nixos-btw";
        "security" = "user";
        # Map unknown users to guest so Windows can connect seamlessly
        "map to guest" = "Bad User";
      };
      "home" = {
        "path" = "/home/bashgrl";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "bashgrl";
      };
    };
  };

  # Web Services Dynamic Discovery (WSDD): makes NixOS automatically appear in Windows Explorer Network tab
  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  # Ensure WSD multicast/discovery ports are open
  networking.firewall.allowedTCPPorts = [ 5357 ];
  networking.firewall.allowedUDPPorts = [ 3702 ];
}
