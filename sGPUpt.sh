#!/bin/bash
PURPLE='\033[0;35m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
WHITE='\033[0;37m'
BLACK='\033[0;30m'
DEFAULT='\033[0m'

WHITEBG='\033[0;30;47m'
RESETBG='\033[0m'

BLINKYELLOW='\033[1;33m\033[5;33m'
BLINKRED='\033[0;31m\033[5;31m'
UNDERLINE='\033[0m\033[4;37m'

# Main Vars
VMName=$1
GPUType=${2^^}

# Network Vars
netName="default"
netPath="/tmp/$netName.xml"

# Storage Vars
DefaultDiskSize="128"
DiskPath="/etc/sGPUpt/qemu-images"
ISOPath="/etc/sGPUpt/iso/"
#DiskPath=/home/$SUDO_USER/Documents/qemu-images
#ISOPath=/home/$SUDO_USER/Documents/iso/

# Hooks Vars
pHookVM="/etc/libvirt/hooks/qemu.d/$VMName"
fHook="/etc/libvirt/hooks/qemu"
fHookStart="/etc/libvirt/hooks/qemu.d/$VMName/prepare/begin/start.sh"
fHookEnd="/etc/libvirt/hooks/qemu.d/$VMName/release/end/stop.sh"

# Compile Vars
qemuBranch="v7.2.0"
qemuDir="/etc/sGPUpt/qemu-emulator"
edkBranch="edk2-stable202211"
edkDir="/etc/sGPUpt/edk-compile"

logFile="/home/$SUDO_USER/Desktop/sGPUpt.log"

function main()
{
  if [[ ! $(whoami) = "root" ]]; then
    echo -e "${BLINKYELLOW}! ${RED}This script requires root privileges!${DEFAULT}"
    exit 0
  elif [[ -z $VMName ]] || [[ -z $GPUType ]] || [[ $GPUType != @("NVIDIA"|"AMD") ]]; then
    echo -e "${CYAN}usage:${YELLOW} >> ${GREEN}sudo ./sGPUpt.sh \"{VM-Name}\" {NVIDIA|AMD}${DEFAULT}\n"
    exit 0
  elif [[ $VMName = *" "* ]]; then
    echo -e "${BLINKYELLOW}! ${DEFAULT}${YELLOW}Your machines name cannot contain ${DEFAULT}'${RED} ${DEFAULT}'"
    exit 0
  elif [[ $VMName = *"/"* ]]; then
    echo -e "${BLINKYELLOW}! ${DEFAULT}${YELLOW}Your machines name cannot contain ${DEFAULT}'${RED}/${DEFAULT}'"
    exit 0
  elif [[ -z $(grep -E -m 1 "svm|vmx" /proc/cpuinfo) ]]; then
    echo -e "${BLINKYELLOW}! ${DEFAULT}${RED}This system doesn't support virtualization, please enable it then run this script again!${DEFAULT}"
    exit 0
  elif [[ ! -d /sys/firmware/efi ]]; then
    echo -e "${BLINKYELLOW}! ${DEFAULT}${RED}This system isn't installed in UEFI mode!${DEFAULT}"
  elif [[ -z $(ls -A /sys/class/iommu/) ]]; then
    echo -e "${BLINKYELLOW}! ${DEFAULT}${RED}This system doesn't support IOMMU, please enable it then run this script again!${DEFAULT}"
    exit 0
  fi

  echo -e "  ${CYAN}#############################################################${DEFAULT}"
  echo -e "  ${CYAN}#${DEFAULT} \t\t\t\t\t\t\t      ${CYAN}#${DEFAULT}"
  echo -e "  ${CYAN}#${DEFAULT} \t\t    ${RED}${BLINKRED}♥${DEFAULT}${PURPLE} sGPUpt${DEFAULT} made by ${PURPLE}lexi-src${DEFAULT} ${BLUE}${BLINKRED}♥${DEFAULT}\t\t      ${CYAN}#${DEFAULT}"
  echo -e "  ${CYAN}#${DEFAULT} Report issues @ ${UNDERLINE}https://github.com/lexi-src/sGPUpt/issues${CYAN} #${DEFAULT}"
  echo -e "  ${CYAN}#${DEFAULT} \t\t\t\t\t\t\t      ${CYAN}#${DEFAULT}"
  echo -e "  ${CYAN}#############################################################${DEFAULT}\n"

  # Start logging
  > $logFile

  # Call Funcs
  QuerySysInfo
  InstallPackages
  SecurityChecks
  CompileChecks
  SetupLibvirt
  SetupHooks
  CreateVM

  # End Information
  echo -e "\n${BLINKRED}*${DEFAULT} Add your desired OS then start your VM with ${BLUE}Virt Manager${DEFAULT} or ${BLUE}sudo virsh start $VMName${DEFAULT}"
  
  # NEEDED TO FIX DEBIAN-BASED DISTROS USING VIRT-MANAGER
  if [[ $firstInstall == "true" ]]; then
    read -p "A reboot is required for this distro, reboot now? [Y/n]: " CHOICE
    if [[ $CHOICE == @("y"|"Y") ]]; then
      reboot
    fi
  fi
}

function InstallPackages()
{
  source /etc/os-release

  # Which Distro
  if [[ -e /etc/arch-release ]]; then
    yes | pacman -S --needed "qemu-base" "virt-manager" "virt-viewer" "dnsmasq" "vde2" "bridge-utils" "openbsd-netcat" "libguestfs" "swtpm" "git" "make" "ninja" "nasm" "iasl" "pkg-config" "spice-protocol" >> $logFile 2>&1
  elif [[ -e /etc/debian_version ]]; then
    if [[ $NAME == "Ubuntu" ]] && [[ $VERSION_ID != @("22.04"|"22.10") ]]; then
      echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] This script is only verified to work on Ubuntu Versions ${YELLOW}22.04 & 22.10${DEFAULT}"
      exit 0
    elif [[ $NAME == "Linux Mint" ]] && [[ $VERSION_ID != "21.1" ]]; then
      echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] This script is only verified to work on Linux Mint Version ${YELLOW}21.1${DEFAULT}"
      exit 0
    elif [[ $NAME == "Pop!_OS" ]] && [[ $VERSION_ID != "22.04" ]]; then
      echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] This script is only verified to work on Pop!_OS Version ${YELLOW}22.04${DEFAULT}"
      exit 0
    fi

    apt install -y "qemu-kvm" "virt-manager" "virt-viewer" "libvirt-daemon-system" "libvirt-clients" "bridge-utils" "swtpm" "mesa-utils" "git" "ninja-build" "nasm" "iasl" "pkg-config" "libglib2.0-dev" "libpixman-1-dev" "meson" "build-essential" "uuid-dev" "python-is-python3" "libspice-protocol-dev" >> $logFile 2>&1
  elif [[ -e /etc/system-release ]]; then
    if [[ $NAME == "AlmaLinux" ]] && [[ $VERSION_ID != "9.1" ]]; then
      echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] This script is only verified to work on AlmaLinux Version ${YELLOW}9.1${DEFAULT}"
      exit 0
    elif [[ $NAME =~ "Fedora" ]] && [[ $VERSION_ID != @("36"|"37") ]]; then
      echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] This script is only verified to work on Fedora Versions ${YELLOW}36 & 37${DEFAULT}"
      exit 0
    fi

    if [[ $NAME == "AlmaLinux" ]]; then
      dnf --enablerepo=crb install -y "qemu-kvm" "virt-manager" "virt-viewer" "virt-install" "libvirt-daemon-config-network" "libvirt-daemon-kvm" "swtpm" "git" "make" "gcc" "g++" "ninja-build" "nasm" "iasl" "libuuid-devel" "glib2-devel" "pixman-devel" "spice-protocol" >> $logFile 2>&1
    elif [[ $NAME =~ "Fedora" ]]; then
      dnf install -y "qemu-kvm" "virt-manager" "virt-viewer" "virt-install" "libvirt-daemon-config-network" "libvirt-daemon-kvm" "swtpm" "g++" "ninja-build" "nasm" "iasl" "libuuid-devel" "glib2-devel" "pixman-devel" "spice-protocol" >> $logFile 2>&1
    fi
  else
    echo -e "${BLINKYELLOW}! ${DEFAULT}${RED}Cannot find distro!${DEFAULT}"
    exit 0
  fi

  # Fedora and Alma don't have libvirt-qemu for some reason?
  if [[ $NAME =~ "Fedora" ]] || [[ $NAME == "AlmaLinux" ]]; then
    groupName=$SUDO_USER
  else
    groupName="libvirt-qemu"
  fi

  # If dir doesn't exist then create it
  if [[ ! -e $ISOPath ]]; then
    mkdir -p $ISOPath >> $logFile 2>&1
  fi

  # Download VirtIO Drivers
  if [[ ! -e $ISOPath/virtio-win.iso ]]; then
    echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] Downloading VirtIO Drivers ISO..."
    wget -P $ISOPath https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso 2>&1 | grep -i "error" >> $logFile 2>&1
  fi
}

function SecurityChecks()
{
  ############################################################################################
  #                                                                                          #
  # Disabling security for virtualization generally isn't a smart idea but since this script #
  # targets home systems it's well worth the trade-off to disable security for ease of use.  #
  #                                                                                          #
  ############################################################################################

  # Disable AppArmor
  if [[ $NAME == @("Ubuntu"|"Pop!_OS"|"Linux Mint") ]] && [[ ! -f /etc/apparmor.d/disable/usr.sbin.libvirtd ]]; then
    firstInstall="true" # NEEDED TO FIX DEBIAN-BASED DISTROS USING VIRT-MANAGER
    echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] Disabling AppArmor permanently for this distro"
    ln -s /etc/apparmor.d/usr.sbin.libvirtd /etc/apparmor.d/disable/ >> $logFile 2>&1
    apparmor_parser -R /etc/apparmor.d/usr.sbin.libvirtd >> $logFile 2>&1
  fi

  # Disable SELinux
  if [[ $NAME =~ "Fedora" ]] || [[ $NAME == "AlmaLinux" ]]; then
    source /etc/selinux/config
    if [[ $SELINUX == "enforcing" ]]; then
      echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] Disabling SELinux permanently for this distro"
      setenforce 0 >> $logFile 2>&1
      sed -i "s/SELINUX=enforcing/SELINUX=disabled/" /etc/selinux/config >> $logFile 2>&1
    fi
  fi
}

function CompileChecks()
{
  # Create a file for checking if the compiled qemu was previously installed.
  if [[ ! -e /etc/sGPUpt/install-status.txt ]]; then
    touch /etc/sGPUpt/install-status.txt
  fi

  # Compile Spoofed QEMU & EDK2 OVMF
  if [[ ! -e $qemuDir/build/qemu-system-x86_64 ]]; then
    echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] Starting QEMU compile... please wait."
    echo 0 > /etc/sGPUpt/install-status.txt
    QemuCompile
  fi

  if [[ ! -e $edkDir/Build/OvmfX64/RELEASE_GCC5/FV/OVMF_CODE.fd ]]; then
    echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] Starting EDK2 compile... please wait."
    EDK2Compile
  fi

  # symlink for OVMF
  if [[ ! -f /etc/sGPUpt/OVMF_CODE.fd ]]; then
    ln -s $edkDir/Build/OvmfX64/RELEASE_GCC5/FV/OVMF_CODE.fd /etc/sGPUpt/OVMF_CODE.fd >> $logFile 2>&1
  fi

  # symlink for QEMU
  if [[ ! -f /etc/sGPUpt/qemu-system-x86_64 ]]; then
    ln -s $qemuDir/build/qemu-system-x86_64 /etc/sGPUpt/qemu-system-x86_64 >> $logFile 2>&1
  fi

  # If both builds didn't succeed then don't exit
  if [[ ! -e $qemuDir/build/qemu-system-x86_64 ]] && [[ ! -e $edkDir/Build/OvmfX64/RELEASE_GCC5/FV/OVMF_CODE.fd ]]; then
    echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] ${RED}Failed to compile? Check the log file.${DEFAULT}"
    exit 0
  fi

  if (( $(cat /etc/sGPUpt/install-status.txt) == 0 )); then
    echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] Finished compiling, installing compiled output..."
    cd $qemuDir >> $logFile 2>&1
    make install >> $logFile 2>&1 # may cause an issue ~ host compains about "Host does not support virtualization"
    echo 1 > /etc/sGPUpt/install-status.txt
  fi

  vQEMU=$(/etc/sGPUpt/qemu-system-x86_64 --version | head -n 1 | awk '{print $4}')
}

function QemuCompile()
{
  if [[ -e $qemuDir ]]; then
    rm -rf $qemuDir >> $logFile 2>&1
  fi

  mkdir -p $qemuDir >> $logFile 2>&1
  git clone --branch $qemuBranch https://github.com/qemu/qemu.git $qemuDir >> $logFile 2>&1
  cd $qemuDir >> $logFile 2>&1

  # Spoofing edits ~ We should probably add a bit more here...
  sed -i "s/\"BOCHS \"/\"ALASKA\"/"                                                         $qemuDir/include/hw/acpi/aml-build.h
  sed -i "s/\"BXPC    \"/\"ASPC    \"/"                                                     $qemuDir/include/hw/acpi/aml-build.h
  sed -i "s/\"QEMU HARDDISK\"/\"WDC WD10JPVX-22JC3T0\"/"                                    $qemuDir/hw/scsi/scsi-disk.c
  sed -i "s/\"QEMU HARDDISK\"/\"WDC WD10JPVX-22JC3T0\"/"                                    $qemuDir/hw/ide/core.c
  sed -i "s/\"QEMU DVD-ROM\"/\"ASUS DRW 24F1ST\"/"                                          $qemuDir/hw/ide/core.c
  sed -i "s/\"QEMU\"/\"ASUS\"/"                                                             $qemuDir/hw/ide/atapi.c
  sed -i "s/\"QEMU DVD-ROM\"/\"ASUS DRW 24F1ST\"/"                                          $qemuDir/hw/ide/atapi.c
  sed -i "s/\"QEMU PenPartner Tablet\"/\"Wacom Tablet\"/"                                   $qemuDir/hw/usb/dev-wacom.c
  sed -i "s/\"QEMU PenPartner Tablet\"/\"Wacom Tablet\"/"                                   $qemuDir/hw/scsi/scsi-disk.c
  sed -i "s/\"#define DEFAULT_CPU_SPEED 2000\"/\"#define DEFAULT_CPU_SPEED 3400\"/"         $qemuDir/hw/scsi/scsi-disk.c
  sed -i "s/\"KVMKVMKVM\\\\0\\\\0\\\\0\"/\"$CPUBrand\"/"                                    $qemuDir/include/standard-headers/asm-x86/kvm_para.h
  sed -i "s/\"KVMKVMKVM\\\\0\\\\0\\\\0\"/\"$CPUBrand\"/"                                    $qemuDir/target/i386/kvm/kvm.c
  sed -i "s/\"bochs\"/\"AMI\"/"                                                             $qemuDir/block/bochs.c

  ./configure --enable-spice --disable-werror >> $logFile 2>&1
  make -j$(nproc) >> $logFile 2>&1

  chown -R $SUDO_USER:$SUDO_USER $qemuDir >> $logFile 2>&1
}

function EDK2Compile()
{
  if [[ -e $edkDir ]]; then
    rm -rf $edkDir >> $logFile 2>&1
  fi

  mkdir -p $edkDir >> $logFile 2>&1
  cd $edkDir >> $logFile 2>&1

  git clone --branch $edkBranch https://github.com/tianocore/edk2.git $edkDir >> $logFile 2>&1
  git submodule update --init >> $logFile 2>&1

  # Spoofing edits
  sed -i "s/\"EDK II\"/\"American Megatrends\"/"                                            $edkDir/MdeModulePkg/MdeModulePkg.dec
  sed -i "s/\"EDK II\"/\"American Megatrends\"/"                                            $edkDir/ShellPkg/ShellPkg.dec

  make -j$(nproc) -C BaseTools >> $logFile 2>&1
  . edksetup.sh >> $logFile 2>&1
  OvmfPkg/build.sh -p OvmfPkg/OvmfPkgX64.dsc -a X64 -b RELEASE -t GCC5 >> $logFile 2>&1

  chown -R $SUDO_USER:$SUDO_USER $edkDir >> $logFile 2>&1
}

function QuerySysInfo()
{
  # Base CPU Information
  CPUBrand=$(grep -m 1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
  CPUName=$(grep -m 1 'model name' /proc/cpuinfo | cut -d':' -f2 | cut -c2- | awk '{printf $0}')

  if [[ $CPUBrand == "AuthenticAMD" ]]; then
    SysType="AMD"
  elif [[ $CPUBrand == "GenuineIntel" ]]; then
    SysType="Intel"
  else
    echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] ${RED}Failed to find CPU brand.${DEFAULT}"
    exit 0
  fi

  # Core + Thread Pairs
  for (( i=0, u=0; i<$(nproc) / 2; i++ )); do
    PT=$(lscpu -p | tail -n +5 | grep "$i,*[0-9]*,*[0-9]*,,$i,$i,$i" | cut -d',' -f1 | awk '{printf $0 " "}')

    aCPU[$u]=$(echo $PT | cut -d" " -f1)
    ((u++))
    aCPU[$u]=$(echo $PT | cut -d" " -f2)
    ((u++))
  done

  # Used for isolation in start.sh & end.sh
  ReservedCPUs="$(echo $PT | cut -d" " -f1),$(echo $PT | cut -d" " -f2)"
  AllCPUs="0-$(echo $PT | cut -d" " -f2)"

  # Stop the script if we have more than one GPU in the system
  if (( $(lspci | grep "VGA" | wc -l) > 1 )); then
    echo -e "${BLINKYELLOW}! ${RED}ERROR: There are too many GPUs in the system!${DEFAULT}"
    exit 0
  fi

  # Determine which GPU type
  if [[ $GPUType == "NVIDIA" ]]; then
    GPUVideo=$(lspci | grep "NVIDIA" | grep "VGA" | cut -d" " -f1)
    GPUAudio=$(lspci | grep "NVIDIA" | grep "Audio" | cut -d" " -f1)
    GPUName=${GREEN}$(glxinfo -B | grep "renderer string" | cut -d":" -f2 | cut -c2- | cut -d"/" -f1)${DEFAULT}
  elif [[ $GPUType == "AMD" ]]; then
    GPUVideo=$(lspci | grep "AMD/ATI" | grep "VGA" | cut -d" " -f1)
    GPUAudio=$(lspci | grep "AMD/ATI" | grep "Audio" | cut -d" " -f1)
    GPUName=${RED}$(glxinfo -B | grep "renderer string" | cut -d":" -f2 | cut -c2- | cut -d"(" -f1 | head -c -2)${DEFAULT}
  fi

  # Stop the script if we don't have any GPU on the system
  if [[ -z $GPUVideo ]] || [[ -z $GPUAudio ]]; then
    echo -e "${BLINKYELLOW}! ${RED}ERROR: Couldn't find any GPU on the system...${DEFAULT}"
    exit 0
  fi

  # If we fail to fill $GPUName
  if [[ -z $GPUName ]]; then
    echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] ${RED}Failed to find GPU name, do you have drivers installed?.${DEFAULT}"
  fi

  read -p "$(echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] Is this the correct GPU? [ $GPUName ]") [y/N]: " CHOICE
  if [[ $CHOICE != @("y"|"Y") ]]; then
    echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] ${RED}Please report this if your GPU wasn't detected correctly!'${DEFAULT}"
    exit 0
  fi

  # Find all USB Controllers
  aUSB=$(lspci | grep "USB controller" | awk '{printf $1 " "}')

  # Stop the script if we don't have any USB on the system
  if [[ -z $aUSB ]]; then
    echo -e "${BLINKYELLOW}! ${RED}ERROR: Couldn't find any USB controllers on the system...${DEFAULT}"
    exit 0
  fi

  # CPU topology
  vThread=$(lscpu | grep "Thread(s) per core:" | awk '{print $4}')
  vCPU=$(($(nproc) - $vThread))
  vCore=$(($vCPU / $vThread))

  # Get the hosts total memory to split for the VM
  SysMem=$(free -g | grep -oP '\d+' | head -n 1)
  if (( $SysMem > 120 )); then
    vMem="65536"
  elif (( $SysMem > 90 )); then
    vMem="49152"
  elif (( $SysMem > 60 )); then
    vMem="32768"
  elif (( $SysMem > 30 )); then
    vMem="16384"
  elif (( $SysMem > 20 )); then
    vMem="12288"
  elif (( $SysMem > 14 )); then
    vMem="8192"
  elif (( $SysMem > 10 )); then
    vMem="6144"
  else
    vMem="4096"
  fi

  # Convert ID
  cGPUVideo=$(echo $GPUVideo | tr :. _)
  cGPUAudio=$(echo $GPUAudio | tr :. _)

# LOG THE RESULTS TO THE $logFile
  for (( i=0; i<${#aUSB[@]}; i++ )); do
    if (( $i == 0 )); then
      debugUSB="\"$(echo ${aUSB[$i]} | tr -d ' ')\""
      debugUSBc="\"$(echo ${aUSB[$i]} | tr :. _ | tr -d ' ')\""
    else
      debugUSB="$debugUSB,\"$(echo ${aUSB[$i]} | tr -d ' ')\""
      debugUSBc="$debugUSBc,\"$(echo ${aUSB[$i]} | tr :. _ | tr -d ' ')\""
    fi
  done

echo -e "[\"Query Result\"]
{
  \"System Conf\":[
  {
    \"CPU\":[
    {
      \"ID\":\"$CPUBrand\",
      \"Name\":\"$CPUName\",
      \"CPU Pinning\": [ \"${aCPU[@]}\" ]
    }],

    \"Sys.Memory\":\"$SysMem\",

    \"Isolation\":[
    {
      \"ReservedCPUs\":\"$ReservedCPUs\",
      \"AllCPUs\":\"$AllCPUs\"
    }],

    \"PCI\":[
    {
      \"GPU Name\":\"$(echo -e $GPUName | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2};?)?)?[mGK]//g")\",
      \"GPU Video\":\"$GPUVideo\",
      \"GPU Audio\":\"$GPUAudio\",
      \"USB IDs\": [ $debugUSB ]
    }],
  }],

  \"Virt Conf\":[
  {
    \"vCPUs\":\"$vCPU\",
    \"vCores\":\"$vCore\",
    \"vThreads\":\"$vThread\",
    \"vMem\":\"$vMem\",
    \"Converted GPU Video\":\"$cGPUVideo\",
    \"Converted GPU Audio\":\"$cGPUAudio\",
    \"USB IDs\": [ $debugUSBc ]
  }]
}\n" >> $logFile
}

function SetupHooks()
{
  # If hooks aren't installed
  if [[ ! -d /etc/libvirt/hooks/ ]]; then
    CreateHooks
  fi

  # Is this the first time we're creating hooks for this VM?
  if [[ ! -d $pHookVM ]]; then
    echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] Creating passthrough hooks..."
  else
    echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] Recreating passthrough hooks..."
  fi

  # Create start.sh & end.sh
  StartScript
  EndScript

  # Allow hooks to be execute
  chmod +x -R $pHookVM >> $logFile 2>&1
}

CreateHooks()
{
  mkdir -p /etc/libvirt/hooks/qemu.d/ >> $logFile 2>&1
  touch    $fHook >> $logFile 2>&1
  chmod +x $fHook >> $logFile 2>&1

  # https://github.com/PassthroughPOST/VFIO-Tools/blob/master/libvirt_hooks/qemu
  echo -e "#!/bin/bash"                                                                       >> $fHook
  echo -e "GUEST_NAME=\"\$1\""                                                                >> $fHook
  echo -e "HOOK_NAME=\"\$2\""                                                                 >> $fHook
  echo -e "STATE_NAME=\"\$3\""                                                                >> $fHook
  echo -e "MISC=\"\${@:4}\"\n"                                                                >> $fHook
  echo -e "BASEDIR=\"\$(dirname \$0)\""                                                       >> $fHook
  echo -e "HOOKPATH=\"\$BASEDIR/qemu.d/\$GUEST_NAME/\$HOOK_NAME/\$STATE_NAME\"\n"             >> $fHook
  echo -e "set -e\n"                                                                          >> $fHook
  echo -e "if [ -f \"\$HOOKPATH\" ] && [ -s \"\$HOOKPATH\" ] && [ -x \"\$HOOKPATH\" ]; then"  >> $fHook
  echo -e "  eval \\\"\$HOOKPATH\\\" \"\$@\""                                                 >> $fHook
  echo -e "elif [ -d \"\$HOOKPATH\" ]; then"                                                  >> $fHook
  echo -e "  while read file; do"                                                             >> $fHook
  echo -e "    if [ ! -z \"\$file\" ]; then"                                                  >> $fHook
  echo -e "      eval \\\"\$file\\\" \"\$@\""                                                 >> $fHook
  echo -e "    fi"                                                                            >> $fHook
  echo -e "  done <<< \"\$(find -L \"\$HOOKPATH\" -maxdepth 1 -type f -executable -print;)\"" >> $fHook
  echo -e "fi"                                                                                >> $fHook
}

function StartScript()
{
  # Create begin hook for VM if it doesn't exist
  if [[ ! -d $pHookVM/prepare/begin/ ]]; then
    mkdir -p $pHookVM/prepare/begin/ >> $logFile 2>&1
    touch    $pHookVM/prepare/begin/start.sh >> $logFile 2>&1
  fi

  > $fHookStart
  echo -e "#!/bin/bash"                                                                       >> $fHookStart
  echo -e "set -x\n"                                                                          >> $fHookStart
  echo -e "systemctl stop display-manager\n"                                                  >> $fHookStart
  echo -e "for file in /sys/class/vtconsole/*; do"                                            >> $fHookStart
  echo -e "  if (( \$(grep -c \"frame buffer\" \$file/name) == 1 )); then"                    >> $fHookStart
  echo -e "    echo 0 > \$file/bind"                                                          >> $fHookStart
  echo -e "  fi"                                                                              >> $fHookStart
  echo -e "done\n"                                                                            >> $fHookStart
  echo -e "echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind"         >> $fHookStart
  echo -e "virsh nodedev-detach pci_0000_$cGPUVideo"                                          >> $fHookStart
  echo -e "virsh nodedev-detach pci_0000_$cGPUAudio"                                          >> $fHookStart
  for usb in ${aUSB[@]}; do
    echo -e "virsh nodedev-detach pci_0000_$(echo $usb | tr :. _)"                            >> $fHookStart
  done
  echo -e "\nmodprobe vfio-pci\n"                                                             >> $fHookStart
  echo -e "systemctl set-property --runtime -- user.slice AllowedCPUs=$ReservedCPUs"          >> $fHookStart
  echo -e "systemctl set-property --runtime -- system.slice AllowedCPUs=$ReservedCPUs"        >> $fHookStart
  echo -e "systemctl set-property --runtime -- init.scope AllowedCPUs=$ReservedCPUs"          >> $fHookStart
}

function EndScript()
{
  # Create release hook for VM if it doesn't exist
  if [[ ! -d $pHookVM/release ]]; then
    mkdir -p $pHookVM/release/end/ >> $logFile 2>&1
    touch    $pHookVM/release/end/stop.sh >> $logFile 2>&1
  fi

  > $fHookEnd
  echo -e "#!/bin/bash"                                                                       >> $fHookEnd
  echo -e "set -x\n"                                                                          >> $fHookEnd
  echo -e "virsh nodedev-reattach pci_0000_$cGPUVideo"                                        >> $fHookEnd
  echo -e "virsh nodedev-reattach pci_0000_$cGPUAudio"                                        >> $fHookEnd
  for usb in ${aUSB[@]}; do
    echo -e "virsh nodedev-reattach pci_0000_$(echo $usb | tr :. _)"                          >> $fHookEnd
  done
  echo -e "\nsystemctl start display-manager\n"                                               >> $fHookEnd
  echo -e "for file in /sys/class/vtconsole/*; do"                                            >> $fHookEnd
  echo -e "  if (( \$(grep -c \"frame buffer\" \$file/name) == 1 )); then"                    >> $fHookEnd
  echo -e "    echo 1 > \$file/bind"                                                          >> $fHookEnd
  echo -e "  fi"                                                                              >> $fHookEnd
  echo -e "done\n"                                                                            >> $fHookEnd
  echo -e "systemctl set-property --runtime -- user.slice AllowedCPUs=$AllCPUs"               >> $fHookEnd
  echo -e "systemctl set-property --runtime -- system.slice AllowedCPUs=$AllCPUs"             >> $fHookEnd
  echo -e "systemctl set-property --runtime -- init.scope AllowedCPUs=$AllCPUs"               >> $fHookEnd
}

function vNetworkCheck()
{
  # If '$netName' doesn't exist then create it!
  if [[ $(virsh net-autostart $netName 2>&1) = *"Network not found"* ]]; then
    > $netPath
    echo -e "<network>"                                                                       >> $netPath
    echo -e "  <name>$netName</name>"                                                         >> $netPath
    echo -e "  <forward mode=\"nat\">"                                                        >> $netPath
    echo -e "    <nat>"                                                                       >> $netPath
    echo -e "      <port start=\"1024\" end=\"65535\"/>"                                      >> $netPath
    echo -e "    </nat>"                                                                      >> $netPath
    echo -e "  </forward>"                                                                    >> $netPath
    echo -e "  <ip address=\"192.168.122.1\" netmask=\"255.255.255.0\">"                      >> $netPath
    echo -e "    <dhcp>"                                                                      >> $netPath
    echo -e "      <range start=\"192.168.122.2\" end=\"192.168.122.254\"/>"                  >> $netPath
    echo -e "    </dhcp>"                                                                     >> $netPath
    echo -e "  </ip>"                                                                         >> $netPath
    echo -e "</network>"                                                                      >> $netPath

    virsh net-define $netPath >> $logFile 2>&1
    rm $netPath >> $logFile 2>&1

    echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] Network Manually Created"
  fi

  # set autostart on network '$netName' in case it wasn't already on for some reason
  if [[ $(virsh net-info $netName | grep "Autostart" | awk '{print $2}') == "no" ]]; then
    virsh net-autostart $netName >> $logFile 2>&1
  fi

  # start network if it isn't active
  if [[ $(virsh net-info $netName | grep "Active" | awk '{print $2}') == "no" ]]; then
    virsh net-start $netName >> $logFile 2>&1
  fi
}

function SetupLibvirt()
{
  # If group doesn't exist then create it
  if [[ -z $(getent group libvirt) ]]; then
    groupadd libvirt >> $logFile 2>&1
    echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] Created libvirt group"
  fi

  # If either user isn't in the group then add all of them again
  if [[ -z $(groups $SUDO_USER | grep libvirt | grep kvm | grep input) ]]; then
    usermod -aG libvirt,kvm,input $SUDO_USER >> $logFile 2>&1
    echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] Added user ${YELLOW}$SUDO_USER${DEFAULT} to groups ${YELLOW}libvirt,kvm,input${DEFAULT}"
  fi

  # Allow users in group libvirt to use virt-manager /etc/libvirt/libvirtd.conf
  if [[ $(grep "unix_sock_group = \"libvirt\"" /etc/libvirt/libvirtd.conf) != "unix_sock_group = \"libvirt\"" ]]; then
    sed -i "s/#unix_sock_group = \"libvirt\"/unix_sock_group = \"libvirt\"/" /etc/libvirt/libvirtd.conf
  fi

  if [[ $(grep "unix_sock_rw_perms = \"0770\"" /etc/libvirt/libvirtd.conf) != "unix_sock_rw_perms = \"0770\"" ]]; then
    sed -i "s/#unix_sock_rw_perms = \"0770\"/unix_sock_rw_perms = \"0770\"/" /etc/libvirt/libvirtd.conf
  fi

  # Kill virt-manager because it shouldn't opened during the install
  if [[ -n $(pgrep -x "virt-manager") ]]; then
    killall virt-manager
    #echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] ${RED}Killed virt-manager${DEFAULT}"
  fi

  # Restart or enable libvirtd
  if [[ -n $(pgrep -x "libvirtd") ]]; then
    if [[ -e /run/systemd/system ]]; then
      systemctl restart libvirtd.service >> $logFile 2>&1
    else
      rc-service libvirtd.service restart >> $logFile 2>&1
    fi
  else
    if [[ -e /run/systemd/system ]]; then
      systemctl enable --now libvirtd.service >> $logFile 2>&1
    else
      rc-update add libvirtd.service default >> $logFile 2>&1
      rc-service libvirtd.service start >> $logFile 2>&1
    fi
  fi

  vNetworkCheck
}

function CreateVM()
{
  # Overwrite protection for existing VM configurations
  if [[ -e /etc/libvirt/qemu/$VMName.xml ]]; then
    echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] Will not overwrite an existing VM Config!"
    return
  fi

  # If dir doesn't exist then create it
  if [[ ! -e $DiskPath ]]; then
    mkdir -p $DiskPath >> $logFile 2>&1
  fi

  # Disk img doesn't exist then create it
  if [[ ! -e $DiskPath/$VMName.qcow2 ]]; then
    read -p "$(echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] Do you want to create a drive named ${YELLOW}${VMName}${DEFAULT}")? [y/N]: " CHOICE
    if [[ $CHOICE == @("y"|"Y") ]]; then
      read -p "$(echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] Size of disk?") [GB]: " DiskSize
      if [[ ! $DiskSize =~ ^[0-9]+$ ]] || (( $DiskSize < 1 )); then
        echo -e "Default"
        DiskSize=$DefaultDiskSize
      fi

      qemu-img create -f qcow2 $DiskPath/$VMName.qcow2 ${DiskSize}G >> $logFile 2>&1
      chown $SUDO_USER:$groupName $DiskPath/$VMName.qcow2 >> $logFile 2>&1
      includeDrive="1"
    fi
  else
    read -p "$(echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] Do you want to ${RED}overwrite${DEFAULT} a drive named ${YELLOW}${VMName}${DEFAULT}")? [y/N]: " CHOICE
    if [[ $CHOICE == @("y"|"Y") ]]; then
      qemu-img create -f qcow2 $DiskPath/$VMName.qcow2 $DiskSize >> $logFile 2>&1
      chown $SUDO_USER:$groupName $DiskPath/$VMName.qcow2 >> $logFile 2>&1
      includeDrive="1"
    fi
  fi

  case $SysType in
    AMD)    CPUFeatures="hv_vendor_id=AuthenticAMD,-x2apic,+svm,+invtsc,+topoext" ;;
    Intel)  CPUFeatures="hv_vendor_id=GenuineIntel,-x2apic,+vmx" ;;
  esac

  OVMF_CODE="/etc/sGPUpt/OVMF_CODE.fd"
  OVMF_VARS="/var/lib/libvirt/qemu/nvram/${VMName}_VARS.fd"
  Emulator="/etc/sGPUpt/qemu-system-x86_64"
  cp $edkDir/Build/OvmfX64/RELEASE_GCC5/FV/OVMF_VARS.fd $OVMF_VARS

  echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] Creating VM [ Type:${YELLOW}\"$SysType${YELLOW}\"${DEFAULT}, Name:${YELLOW}\"$VMName\"${DEFAULT}, vCPU:${YELLOW}\"$vCPU\"${DEFAULT}, Mem:${YELLOW}\"$vMem"\M"\"${DEFAULT}, Disk:${YELLOW}\"$DiskSize\"${DEFAULT}, QEMU-V:${YELLOW}\"$vQEMU\"${DEFAULT} ]"

  virt-install \
  --connect qemu:///system \
  --noreboot \
  --noautoconsole \
  --name $VMName \
  --memory $vMem \
  --vcpus $vCPU \
  --osinfo win10 \
  --cpu host-model,topology.dies=1,topology.sockets=1,topology.cores=$vCore,topology.threads=$vThread,check=none \
  --clock rtc_present=no,pit_present=no,hpet_present=no,kvmclock_present=no,hypervclock_present=yes,timer5.name=tsc,timer5.present=yes,timer5.mode=native \
  --boot loader.readonly=yes,loader.type=pflash,loader=$OVMF_CODE \
  --boot nvram=$OVMF_VARS \
  --boot emulator=$Emulator \
  --boot cdrom,hd,menu=on \
  --feature vmport.state=off \
  --disk device=cdrom,path=$ISOPath/virtio-win.iso \
  --import \
  --network type=network,source=$netName,model=virtio \
  --sound none \
  --console none \
  --graphics none \
  --controller type=usb,model=none \
  --memballoon model=none \
  --tpm model=tpm-crb,type=emulator,version=2.0 \
  --host-device="pci_0000_$cGPUVideo" \
  --host-device="pci_0000_$cGPUAudio" \
  --qemu-commandline="-cpu" \
  --qemu-commandline="host,hv_time,hv_relaxed,hv_vapic,hv_spinlocks=8191,hv_vpindex,hv_reset,hv_synic,hv_stimer,hv_frequencies,hv_reenlightenment,hv_tlbflush,hv_ipi,kvm=off,kvm-hint-dedicated=on,-hypervisor,$CPUFeatures" \
  >> $logFile 2>&1

  if [[ $includeDrive == "1" ]]; then
    virt-xml $VMName --add-device --disk path=$DiskPath/$VMName.qcow2,bus=virtio,cache=none,discard=ignore,format=qcow2,bus=sata >> $logFile 2>&1
  fi

  # VM edits
  InsertSpoofedBoard
  InsertCPUPinning
  InsertUSB

  echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] Finished creating ${YELLOW}$VMName${DEFAULT}!"
}

function InsertSpoofedBoard()
{
  ASUSMotherboards

  echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] ${YELLOW}$VMName${DEFAULT}: Spoofing Motherboard [ ${CYAN}$BaseBoardProduct${DEFAULT} ]"

  virt-xml $VMName --add-device --sysinfo bios.vendor="$BIOSVendor",bios.version="$BIOSRandVersion",bios.date="$BIOSDate",bios.release="$BIOSRandRelease" >> $logFile 2>&1
  virt-xml $VMName --add-device --sysinfo system.manufacturer="$SystemManufacturer",system.product="$SystemProduct",system.version="$SystemVersion",system.serial="$SystemRandSerial",system.uuid="$SystemUUID",system.sku="$SystemSku",system.family="$SystemFamily" >> $logFile 2>&1
  virt-xml $VMName --add-device --sysinfo baseBoard.manufacturer="$BaseBoardManufacturer",baseBoard.product="$BaseBoardProduct",baseBoard.version="$BaseBoardVersion",baseBoard.serial="$BaseBoardRandSerial",baseBoard.asset="$BaseBoardAsset",baseBoard.location="$BaseBoardLocation" >> $logFile 2>&1
  virt-xml $VMName --add-device --sysinfo chassis.manufacturer="$ChassisManufacturer",chassis.version="$ChassisVersion",chassis.serial="$ChassisSerial",chassis.asset="$ChassisAsset",chassis.sku="$ChassisSku" >> $logFile 2>&1
  virt-xml $VMName --add-device --sysinfo oemStrings.entry0="$oemStrings0",oemStrings.entry1="$oemStrings1" >> $logFile 2>&1
}

function InsertCPUPinning()
{
  echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] ${YELLOW}$VMName${DEFAULT}: Adding CPU Pinning for [ ${RED}$CPUName${DEFAULT} ]..."
  for (( i=0; i<$vCPU; i++ )); do
    virt-xml $VMName --edit --cputune="vcpupin$i.vcpu=$i,vcpupin$i.cpuset=${aCPU[$i]}" >> $logFile 2>&1
  done
}

function InsertUSB()
{
  echo -e "~ [${PURPLE}sGPUpt${DEFAULT}] ${YELLOW}$VMName${DEFAULT}: Adding all USB Controllers..."
  for usb in ${aUSB[@]}; do
    virt-xml $VMName --add-device --host-device="pci_0000_$(echo $usb | tr :. _)" >> $logFile 2>&1
  done
}

function ASUSMotherboards()
{
  ASUSBoards=(
  "TUF GAMING X570-PRO WIFI II" \
  "TUF GAMING X570-PLUS (WI-FI)" \
  "TUF GAMING X570-PLUS" \
  "PRIME X570-PRO" \
  "PRIME X570-PRO/CSM" \
  "PRIME X570-P" \
  "PRIME X570-P/CSM" \
  "ROG CROSSHAIR VIII EXTREME" \
  "ROG CROSSHAIR VIII DARK HERO" \
  "ROG CROSSHAIR VIII FORMULA" \
  "ROG CROSSHAIR VIII HERO (WI-FI)" \
  "ROG CROSSHAIR VIII HERO" \
  "ROG CROSSHAIR VIII IMPACT" \
  "ROG STRIX X570-E GAMING WIFI II" \
  "ROG STRIX X570-E GAMING" \
  "ROG STRIX X570-F GAMING" \
  "ROG STRIX X570-I GAMING" \
  "PROART X570-CREATOR WIFI" \
  "PRO WS X570-ACE" )

  BIOSVendor="American Megatrends Inc."
  BIOSDate=$(shuf -i 1-12 -n 1)/$(shuf -i 1-31 -n 1)/$(shuf -i 2015-2023 -n 1)
  BIOSRandVersion=$(shuf -i 3200-4600 -n 1)
  BIOSRandRelease=$(shuf -i 1-6 -n 1).$((15 * $(shuf -i 1-6 -n 1)))

  SystemUUID=$(virsh domuuid $VMName)
  SystemManufacturer="System manufacturer"
  SystemProduct="System Product Name"
  SystemVersion="System Version"
  SystemRandSerial=$(shuf -i 2000000000000-3000000000000 -n 1)
  SystemSku="SKU"
  SystemFamily="To be filled by O.E.M."

  BaseBoardManufacturer="ASUSTeK COMPUTER INC."
  BaseBoardProduct=${ASUSBoards[$(shuf -i 0-$((${#ASUSBoards[@]} - 1)) -n 1)]}
  BaseBoardVersion="Rev X.0x"
  BaseBoardRandSerial=$(shuf -i 200000000000000-300000000000000 -n 1)
  BaseBoardAsset="Default string"
  BaseBoardLocation="Default string"

  ChassisManufacturer="Default string"
  ChassisVersion="Default string"
  ChassisSerial="Default string"
  ChassisAsset="Default string"
  ChassisSku="Default string"

  oemStrings0="Default string"
  oemStrings1="TEQUILA"
}

main