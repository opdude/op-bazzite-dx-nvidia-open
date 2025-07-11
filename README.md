# op-bazzite-dx-nvidia-open &nbsp; [![bluebuild build badge](https://github.com/opdude/op-bazzite-dx-nvidia-open/actions/workflows/build.yml/badge.svg)](https://github.com/opdude/op-bazzite-dx-nvidia-open/actions/workflows/build.yml)

See the [BlueBuild docs](https://blue-build.org/how-to/setup/) for quick setup instructions for setting up your own repository based on this template.

After setup, it is recommended you update this README to describe your custom image.

## Installation

> [!WARNING]  
> [This is an experimental feature](https://www.fedoraproject.org/wiki/Changes/OstreeNativeContainerStable), try at your own discretion.

To rebase an existing atomic Fedora installation to the latest build:

- First rebase to the unsigned image, to get the proper signing keys and policies installed:
  ```
  rpm-ostree rebase ostree-unverified-registry:ghcr.io/opdude/op-bazzite-dx-nvidia-open:latest
  ```
- Reboot to complete the rebase:
  ```
  systemctl reboot
  ```
- Then rebase to the signed image, like so:
  ```
  rpm-ostree rebase ostree-image-signed:docker://ghcr.io/opdude/op-bazzite-dx-nvidia-open:latest
  ```
- Reboot again to complete the installation
  ```
  systemctl reboot
  ```

### Secureboot

After the first boot, if you have secureboot enabled, you will need to enroll the DisplayLink EVDI module signing key. This is necessary for the evdi module to load correctly.

To do this, run the following command:

```bash
sudo mokutil --import /etc/pki/DisplayLink/evdi-signing-key.der
```

You will be prompted to set a password for MOK enrollment. After setting the password, reboot the system. During boot, you will see the MOK Manager screen. Select "Enroll MOK" and follow the prompts. Enter the password you set earlier to enroll the key. After this, the evdi module should load correctly.


The `latest` tag will automatically point to the latest build. That build will still always use the Fedora version specified in `recipe.yml`, so you won't get accidentally updated to the next major version.

## ISO

If build on Fedora Atomic, you can generate an offline ISO with the instructions available [here](https://blue-build.org/learn/universal-blue/#fresh-install-from-an-iso). These ISOs cannot unfortunately be distributed on GitHub for free due to large sizes, so for public projects something else has to be used for hosting.

## Verification

These images are signed with [Sigstore](https://www.sigstore.dev/)'s [cosign](https://github.com/sigstore/cosign). You can verify the signature by downloading the `cosign.pub` file from this repo and running the following command:

```bash
cosign verify --key cosign.pub ghcr.io/opdude/op-bazzite-dx-nvidia-open
```
