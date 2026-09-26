import { rtlSources } from './rtlGenerator';

const encoder = new TextEncoder();

function crc32(data: Uint8Array): number {
  let crc = 0xffffffff;
  for (const byte of data) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) {
      crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function write16(view: DataView, offset: number, value: number) {
  view.setUint16(offset, value, true);
}

function write32(view: DataView, offset: number, value: number) {
  view.setUint32(offset, value, true);
}

function join(parts: Uint8Array[]): Uint8Array {
  const result = new Uint8Array(parts.reduce((length, part) => length + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

// The source files are small, so ZIP's store method keeps the bundle dependency-free.
export function createZip(files: Record<string, string>): Uint8Array {
  const localParts: Uint8Array[] = [];
  const centralParts: Uint8Array[] = [];
  let localOffset = 0;
  let fileCount = 0;

  for (const [path, source] of Object.entries(files)) {
    const name = encoder.encode(path);
    const data = encoder.encode(source);
    const checksum = crc32(data);
    const local = new Uint8Array(30 + name.length);
    const localView = new DataView(local.buffer);
    write32(localView, 0, 0x04034b50);
    write16(localView, 4, 20);
    write16(localView, 6, 0x0800);
    write16(localView, 12, 0x0021);
    write32(localView, 14, checksum);
    write32(localView, 18, data.length);
    write32(localView, 22, data.length);
    write16(localView, 26, name.length);
    local.set(name, 30);
    localParts.push(local, data);

    const central = new Uint8Array(46 + name.length);
    const centralView = new DataView(central.buffer);
    write32(centralView, 0, 0x02014b50);
    write16(centralView, 4, 20);
    write16(centralView, 6, 20);
    write16(centralView, 8, 0x0800);
    write16(centralView, 14, 0x0021);
    write32(centralView, 16, checksum);
    write32(centralView, 20, data.length);
    write32(centralView, 24, data.length);
    write16(centralView, 28, name.length);
    write32(centralView, 42, localOffset);
    central.set(name, 46);
    centralParts.push(central);

    localOffset += local.length + data.length;
    fileCount++;
  }

  const centralDirectory = join(centralParts);
  const end = new Uint8Array(22);
  const endView = new DataView(end.buffer);
  write32(endView, 0, 0x06054b50);
  write16(endView, 8, fileCount);
  write16(endView, 10, fileCount);
  write32(endView, 12, centralDirectory.length);
  write32(endView, 16, localOffset);
  return join([...localParts, centralDirectory, end]);
}

function safeProjectName(projectName: string): string {
  return projectName.trim().normalize('NFC')
    .replace(/[^\p{L}\p{N}._-]+/gu, '_')
    .replace(/^[._-]+|[._-]+$/g, '') || 'project';
}

export function projectTopFileName(projectName: string): string {
  return `${safeProjectName(projectName)}_eulsukdo_top.sv`;
}

export function buildSourceBundle(topSource: string, decoderSource: string, isaName: string, projectName: string, settingsJson: string): Uint8Array {
  const projectDir = safeProjectName(projectName);
  return createZip({
    [`${projectDir}/eulsukdo_cad_config.json`]: settingsJson,
    [`${projectDir}/RTL/${projectTopFileName(projectName)}`]: topSource,
    [`${projectDir}/RTL/${isaName}_decoder.sv`]: decoderSource,
    ...Object.fromEntries(Object.entries(rtlSources).map(([name, source]) => [`${projectDir}/RTL/eulsukdo_rtl/${name}`, source])),
    [`${projectDir}/RTL/ex_rtl/`]: '',
  });
}

export function projectArchiveName(projectName: string): string {
  return `${safeProjectName(projectName)}_eulsukdo_rtl.zip`;
}

export function downloadSourceBundle(topSource: string, decoderSource: string, isaName: string, projectName: string, settingsJson: string) {
  const archive = buildSourceBundle(topSource, decoderSource, isaName, projectName, settingsJson);
  const blob = new Blob([new Uint8Array(archive).buffer as ArrayBuffer], { type: 'application/zip' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = projectArchiveName(projectName);
  document.body.appendChild(link);
  link.click();
  link.remove();
  // Give the browser time to start saving the blob before releasing its URL.
  window.setTimeout(() => URL.revokeObjectURL(url), 30_000);
}
