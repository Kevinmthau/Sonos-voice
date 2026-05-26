import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import test from 'node:test';

const catalogURL = new URL(
  '../SonosVoiceRemote/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json',
  import.meta.url,
);
const catalogDirURL = new URL('./', catalogURL);
const pngSignature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function expectedPixels({ size, scale }) {
  const [width, height] = size.split('x').map(Number);
  const multiplier = Number(scale.replace('x', ''));
  return {
    width: width * multiplier,
    height: height * multiplier,
  };
}

function readPngInfo(iconURL) {
  const data = readFileSync(iconURL);

  assert.equal(data.subarray(0, pngSignature.length).equals(pngSignature), true, 'icon must be a PNG');

  return {
    width: data.readUInt32BE(16),
    height: data.readUInt32BE(20),
    hasAlpha: data[25] === 4 || data[25] === 6 || data.includes(Buffer.from('tRNS')),
  };
}

test('app icon catalog references a complete opaque PNG set', () => {
  const catalog = JSON.parse(readFileSync(catalogURL, 'utf8'));

  for (const image of catalog.images) {
    const label = `${image.idiom} ${image.size} ${image.scale}`;

    assert.ok(image.filename, `${label} must reference a file`);

    const iconURL = new URL(image.filename, catalogDirURL);
    assert.equal(existsSync(iconURL), true, `${image.filename} must exist`);

    const expected = expectedPixels(image);
    const actual = readPngInfo(iconURL);

    assert.equal(actual.width, expected.width, `${image.filename} width`);
    assert.equal(actual.height, expected.height, `${image.filename} height`);
    assert.equal(actual.hasAlpha, false, `${image.filename} must not have alpha`);
  }
});
