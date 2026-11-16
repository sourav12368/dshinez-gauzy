# D’Shinez Holdings Gauzy

The `dshinez` branch applies the company’s brand to Gauzy’s Angular web app, including the same UI bundled by Gauzy Desktop and Gauzy Server. Native installers and the separate Desktop Timer use their own branding and release configuration.

The theme uses the existing Nebular light and dark modes. The browser icon is a D monogram and the full wordmark comes from page 3 of the brand kit. Replace `wordmark.png` with a digital export of the approved master when it is available. The kit’s #ED1C24 is used for accents. A deeper red keeps white button labels readable. The bundled Zain ExtraLight font is covered by its accompanying SIL Open Font License, and the app already bundles Roboto.

## Run the branded app

Use the Node.js version in `.nvmrc` and Yarn 1.22. From the checkout, follow the [Gauzy quick start](../README.md#quick-start-to-manually-build--run) with `yarn bootstrap` and `yarn start`. The web UI opens on port 4200 and the API runs on port 3000. Build your own web image from this branch for Docker deployments. Upstream prebuilt images contain the upstream UI.

The application stylesheet and artwork are in [assets/branding/dshinez](../apps/gauzy/src/assets/branding/dshinez). The app supplies the platform wordmark to Gauzy’s existing logo component. The workspace switcher displays the selected workspace’s name and logo. The upstream license and attribution are available in [LICENSES.md](../LICENSES.md).

## Keep the fork current

1. Push the `dshinez` branch to the fork and set it as the fork’s default branch.
2. In the fork’s **Actions** tab, enable **Sync D’Shinez with Gauzy**. Run it once with **Run workflow** and use `dshinez` as the ref.

The workflow checks [Gauzy’s `develop` branch](https://github.com/ever-co/ever-gauzy/tree/develop) twice an hour, at minutes 17 and 47. Each merge preserves upstream commit history. The fork owns its GitHub Actions configuration. GitHub may queue scheduled runs and disables them after 60 days of inactivity in public repositories.

If an update conflicts with the branch or drops a brand hook, the run reports the file and leaves the remote branch at its prior commit. Resolve the update on `dshinez`, commit, push, and run the workflow again. To prepare a manual merge using the same workflow-file boundary, run the following from a clean `dshinez` checkout.

```sh
git fetch https://github.com/ever-co/ever-gauzy.git refs/heads/develop
git merge --no-commit --no-ff FETCH_HEAD
git restore --source=HEAD --staged --worktree -- .github/workflows
```

Resolve any remaining conflicts and confirm the sign-in wordmark, sidebar wordmark, and primary buttons in light and dark mode before committing the merge. The workflow updates Git history. Your hosting and desktop release pipelines can build the merged branch using your own deployment configuration.
