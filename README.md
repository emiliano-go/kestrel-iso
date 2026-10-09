# Kestrel ISO

The Kestrel ISO installs Arch Linux from upstream and AUR packages, then deploys
the Kestrel payload (window manager, shell, themes, and system configuration)
from the checkout bundled in the image. It includes the Kestrel Configurator as a
front-end to archinstall and runs Kestrel's own setup once the base system is in
place.

## Creating the ISO

Run `./bin/kestrel-iso-make` and the output goes into `./release`.

The normal build bundles everything offline: the Arch and AUR package lists from
the payload are downloaded and built into a local repository inside the ISO. Use
`--local-source` to build from the sibling `../kestrel` checkout (the default
when that directory exists) rather than a git clone.

### Environment Variables

You can customize the source used during the build process by passing in
variables:

- `KESTREL_INSTALLER_REPO` - GitHub repository for the payload (default: `emiliano-go/kestrel`)
- `KESTREL_INSTALLER_REF` - Git ref (branch/tag) for the payload (default: `helios`)

Example usage:
```bash
KESTREL_INSTALLER_REPO="myuser/kestrel-fork" KESTREL_INSTALLER_REF="some-feature" ./bin/kestrel-iso-make
```

## Testing the ISO

Run `./bin/kestrel-iso-boot [release/kestrel.iso]`.

## Signing the ISO

Run `./bin/kestrel-iso-sign [gpg-user] [release/kestrel.iso]`.

## Uploading the ISO

Run `./bin/kestrel-iso-upload [release/kestrel.iso]`. This requires you've configured rclone (use `rclone config`).

## Full release of the ISO

Run `./bin/kestrel-iso-release` to create, test, sign, and upload the ISO in one flow.
