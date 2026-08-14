'use strict';

const mainModule = Process.enumerateModules()[0];
const retainedCallbacks = [];

console.log(`[KeychainDump] Process id: ${Process.id}`);
console.log(`[KeychainDump] Main module: ${mainModule.name}`);
console.log(`[KeychainDump] Main module path: ${mainModule.path}`);

if (mainModule.name !== 'KeychainTestApp') {
  throw new Error('This PoC dumper is scoped to KeychainTestApp only.');
}

function findExport(name) {
  if (typeof Module.findGlobalExportByName === 'function') {
    const address = Module.findGlobalExportByName(name);
    if (address !== null) {
      return address;
    }
  }

  if (typeof Module.getGlobalExportByName === 'function') {
    try {
      return Module.getGlobalExportByName(name);
    } catch (_) {
      // Keep searching below.
    }
  }

  const moduleNames = ['Security', 'CoreFoundation'];
  for (const moduleName of moduleNames) {
    try {
      const moduleObject = Process.getModuleByName(moduleName);
      if (typeof moduleObject.getExportByName === 'function') {
        return moduleObject.getExportByName(name);
      }
    } catch (_) {
      // Keep searching the next module.
    }
  }

  return null;
}

function pageStart(address) {
  const value = parseInt(address.toString().replace(/^0x/, ''), 16);
  return ptr(Math.floor(value / Process.pageSize) * Process.pageSize);
}

function bytesToHex(bytes) {
  const parts = [];
  for (let index = 0; index < bytes.length; index += 1) {
    parts.push(bytes[index].toString(16).padStart(2, '0'));
  }
  return parts.join(' ');
}

function readReturnedCFData(resultPointer) {
  const CFGetTypeID = new NativeFunction(findExport('CFGetTypeID'), 'ulong', ['pointer']);
  const CFDataGetTypeID = new NativeFunction(findExport('CFDataGetTypeID'), 'ulong', []);
  const CFDataGetLength = new NativeFunction(findExport('CFDataGetLength'), 'long', ['pointer']);
  const CFDataGetBytePtr = new NativeFunction(findExport('CFDataGetBytePtr'), 'pointer', ['pointer']);
  const cfDataTypeID = String(CFDataGetTypeID());

  if (resultPointer.isNull()) {
    console.log('[KeychainDump] Result pointer is null');
    return;
  }

  const returnedItem = resultPointer.readPointer();
  if (returnedItem.isNull()) {
    console.log('[KeychainDump] Returned item is null');
    return;
  }

  if (String(CFGetTypeID(returnedItem)) !== cfDataTypeID) {
    console.log('[KeychainDump] Returned item is not CFData');
    return;
  }

  const length = CFDataGetLength(returnedItem);
  const bytePointer = CFDataGetBytePtr(returnedItem);
  const byteArray = bytePointer.readByteArray(length);
  const bytes = new Uint8Array(byteArray);

  console.log(`[KeychainDump] Returned CFData length: ${length} bytes`);
  console.log(`[KeychainDump] UTF-8 value: ${bytePointer.readUtf8String(length)}`);
  console.log(`[KeychainDump] Hex bytes: ${bytesToHex(bytes)}`);
}

function replaceSecItemCopyMatchingImportSlot() {
  const originalAddress = findExport('SecItemCopyMatching');
  if (originalAddress === null) {
    throw new Error('SecItemCopyMatching export not found');
  }

  const originalFunction = new NativeFunction(originalAddress, 'int', ['pointer', 'pointer']);
  const callback = new NativeCallback(function (query, result) {
    console.log(`[KeychainDump] SecItemCopyMatching(query=${query}, result=${result})`);
    const status = originalFunction(query, result);
    console.log(`[KeychainDump] SecItemCopyMatching returned: ${status}`);

    if (status === 0) {
      readReturnedCFData(result);
    }

    return status;
  }, 'int', ['pointer', 'pointer']);

  retainedCallbacks.push(callback);

  // Current KeychainTestApp Release build lazy pointer for _SecItemCopyMatching.
  const secItemCopyMatchingSlot = mainModule.base.add(0xc168);
  Memory.protect(pageStart(secItemCopyMatchingSlot), Process.pageSize, 'rw-');
  secItemCopyMatchingSlot.writePointer(callback);

  console.log(`[KeychainDump] Wrapped SecItemCopyMatching import slot at ${secItemCopyMatchingSlot}`);
}

replaceSecItemCopyMatchingImportSlot();
