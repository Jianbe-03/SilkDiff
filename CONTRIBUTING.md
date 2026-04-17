# Contributing to SilkDiff

Thanks for contributing! This guide explains how to set up local development, test changes, and submit a pull request.

## 1. Fork and clone

1. Fork the repository on GitHub.
2. Clone your fork locally:

```bash
git clone https://github.com/<your-username>/SilkDiff.git
git checkout -b my-feature-branch
cd SilkDiff
```

## 2. Install the local dev launcher

Use the local installer so the plugin talks directly to the local `SilkDiffServer/` checkout:

```bash
./install-local.sh
```

This creates a `silk-local` command for development.

To uninstall the local launcher:

```bash
./install-local.sh --uninstall
```

## 3. Run the server

Start the local server from your checkout:

```bash
silk-local server --project /path/to/your/project
```

Or if it works just run:

```bash
silk-local server
```

## 4. Plugin development with Pesto

When working on the Roblox plugin, Pesto is recommended:

```bash
cd SilkDiffRBLX
pesto Server
```

Then open a published Roblox place, import the plugin source, and test changes inside Studio.

If you want AI-assisted workflow tools in your project run:

```bash
pesto Agent --Init
```

## 5. Test your changes

- Confirm the console and plugin load correctly in Roblox Studio.
- Verify `Push`, `Pull`, and `Export` behaviors if you modified sync logic.
- If you changed command-line behavior, test `silk-local --help` and the relevant commands.

## 6. Submit a pull request

1. Commit your changes with a clear message.
2. Push your branch to your fork.
3. Open a pull request against the main repository.
4. Request review once your changes are ready.

## Notes

- `install-local.sh` is the recommended path for development.
- Pesto is optional but useful for plugin iteration.
- Keep contributions focused and test end-to-end before submitting.