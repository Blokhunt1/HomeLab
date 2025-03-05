FROM debian:bookworm-slim AS builder
# Create a bootable ISO for Proxmox unattended install using Docker

# Set noninteractive mode for APT
ENV DEBIAN_FRONTEND=noninteractive

# Install necessary packages (including unzip and xorriso for ISO manipulation)
RUN apt-get update && apt-get install -y \
    wget \
    gnupg \
    apt-transport-https \
    curl 

# Add the Proxmox repository to APT sources
RUN echo "deb [arch=amd64] http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list

# Import the Proxmox repository GPG key
RUN wget -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg

# Update and install the proxmox-auto-install-assistant
RUN apt-get update && apt-get install -y proxmox-auto-install-assistant

# Download the Proxmox VE installation ISO (update URL as needed)
RUN wget -O /tmp/source.iso "http://download.proxmox.com/iso/proxmox-ve_8.3-1.iso"

# Copy initial_automation files from the build context into the image
COPY Automation_Config/answer.toml /tmp/answer.toml
COPY Automation_Config/firstboot.sh /tmp/firstboot.sh
COPY SetupTerraform/install-ansible.yml /tmp/install-ansible.yml

# Run the Proxmox auto-install assistant using the provided answer file
RUN proxmox-auto-install-assistant prepare-iso /tmp/source.iso --fetch-from iso --answer-file /tmp/answer.toml --on-first-boot /tmp/firstboot.sh

# Generate MD5 hash for the source ISO (optional)
RUN md5sum /tmp/source-auto-from-iso.iso | awk '{print $1}' > /tmp/hash.md5

# Second stage: Copy the final ISO to a minimal image for easy extraction
FROM debian:bookworm-slim
COPY --from=builder /tmp/hash.md5 /export/hash.md5
COPY --from=builder /tmp/source-auto-from-iso.iso /export/source-auto-from-iso.iso
