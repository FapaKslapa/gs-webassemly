# gs-wasm-builder

A reproducible pipeline to compile **Ghostscript to WebAssembly**, producing `gs.js` and `gs.wasm` artifacts.

This project is based on [ps-wasm](https://github.com/ochachacha/ps-wasm).

## Quick Start with Docker

```bash
mkdir -p output work
docker build -t gs-wasm-builder .
docker run --rm \
  -v "$(pwd)/output:/output" \
  -v "$(pwd)/work:/build/work" \
  gs-wasm-builder
```

The build produces:
- `output/gs.js`
- `output/gs.wasm`
- `output/SHA256SUMS`

Using the `work` volume enables **build caching**, making subsequent runs much faster.

## Configuration

You can customize the build by passing environment variables:

- `GS_VERSION`: Ghostscript version or commit (default: `dedddcb`).
- `BUILD_ID`: Subdirectory name for output (e.g., `v1`, `run-42`).
- `CLEAN_OUTPUT`: Set to `1` to empty the output directory before copying artifacts.

Example with custom ID and cleanup:

```bash
docker run --rm \
  -v "$(pwd)/output:/output" \
  -v "$(pwd)/work:/build/work" \
  -e GS_VERSION=10.05.0 \
  -e BUILD_ID=v10.05 \
  -e CLEAN_OUTPUT=1 \
  gs-wasm-builder
```

Default version is commit `dedddcb` (known stable for WASM).

## License

Ghostscript is AGPLv3. Scripts and patches are based on `ps-wasm` (AGPLv3).
