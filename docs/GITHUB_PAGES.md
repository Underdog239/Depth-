# Host the ROM helper on GitHub Pages

The `Publish ROM helper to GitHub Pages` workflow publishes the same gold ROM
helper at the website root. No web server, accounts or database are needed.
The build uploads only `index.html`, `rom-tool.html` and `.nojekyll`; it never
publishes repository files, downloaded launchers or ROMs.

## One-time repository setup

1. Open https://github.com/Underdog239/Depth-/settings/pages .
2. Under **Build and deployment → Source**, choose **GitHub Actions**.
3. In **Settings → Environments → github-pages**, if deployment branches are
   restricted, allow `coderabbit/explain-code-limit/230c69a5`.
4. Open **Actions → Publish ROM helper to GitHub Pages**. Re-run the latest run
   if it ran before Pages was enabled. Once this workflow is on the default
   branch, GitHub also exposes its **Run workflow** button.
5. Wait for a successful deployment, then open the URL in the run's environment.
   For this repository the expected URL is https://underdog239.github.io/Depth-/ .

The workflow currently publishes from the assigned task branch. Future pushes to
its web/helper/build/workflow files update the site automatically. When moving
maintenance to another branch, update `on.push.branches` in pages.yml and the
Pages environment's deployment branch policy together. The generated game
launcher still downloads the runtime from the task branch, as before.

The expected URL is not confirmation of a live deployment. Pages must be enabled
by a repository administrator and the deployment must complete successfully.

## How visitors' ROMs stay separate

GitHub serves the same HTML and JavaScript to everyone. The file picker reads
only the file that each visitor explicitly selects, into that browser tab's
memory. The generated download is built locally from those bytes. No ROM data
is uploaded, stored in a shared database, or assigned to a Roblox username.
Two people can select different games simultaneously without affecting each
other. Reloading clears the selection; the downloaded launcher stays on the
device. Playing on another device requires transferring that file yourself.
The launcher contains the ROM, so keep it private.

GitHub may log normal website visits. The helper has no analytics, remote asset
requests or ROM-upload endpoint. When executed later in Roblox, the generated
launcher downloads the common runtime code; it does not upload the ROM.

## Local check

```bash
python3 tools/build_pages.py /tmp/depth-pages-site
python3 -m http.server 8001 --bind 0.0.0.0 --directory /tmp/depth-pages-site
```

Choose a new empty output directory for each build. Visit `/`, choose a synthetic
ROM, Generate, and download the client launcher. `/rom-tool.html` is an alias.
