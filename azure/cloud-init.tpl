#cloud-config

package_update: true
package_upgrade: true

packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg
  - git

write_files:
  - path: /opt/setup/docker.sh
    permissions: '0755'
    content: |
      ${indent(6, docker_sh)}
  - path: /opt/setup/tailscale.sh
    permissions: '0755'
    content: |
      ${indent(6, tailscale_sh)}
  - path: /opt/setup/portainer.sh
    permissions: '0755'
    content: |
      ${indent(6, portainer_sh)}
  - path: /opt/setup/shared-volumes.sh
    permissions: '0755'
    content: |
      ${indent(6, shared_volumes_sh)}

runcmd:
  - /opt/setup/docker.sh ${admin_username}
  - /opt/setup/tailscale.sh ${tailscale_auth_key} ${vm_name}
  - /opt/setup/portainer.sh
  - /opt/setup/shared-volumes.sh ${admin_username}
  # Portal: install manually after provisioning (requires multi-file build)
  # scp -r scripts/portal/ <host>:/opt/setup/portal/
  # scp scripts/portal.sh <host>:/opt/setup/
  # ssh <host> /opt/setup/portal.sh
