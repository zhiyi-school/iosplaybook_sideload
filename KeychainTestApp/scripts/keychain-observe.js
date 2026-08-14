'use strict';

const mainModule = Process.enumerateModules()[0];
const installedHooks = new Set();
const retainedCallbacks = [];

console.log(`[KeychainHook] Process id: ${Process.id}`);
console.log(`[KeychainHook] Main module: ${mainModule.name}`);
console.log(`[KeychainHook] Main module path: ${mainModule.path}`);

function findExport(name) {
  const candidates = findExports(name);
  return candidates.length > 0 ? candidates[0].address : null;
}

function findExports(name) {
  const candidates = [];

  if (typeof Module.findGlobalExportByName === 'function') {
    addCandidate(candidates, name, Module.findGlobalExportByName(name), 'global export');
  }

  if (typeof Module.getGlobalExportByName === 'function') {
    try {
      addCandidate(candidates, name, Module.getGlobalExportByName(name), 'global export');
    } catch (_) {
      // Keep searching other export paths.
    }
  }

  if (typeof Module.findExportByName === 'function') {
    addCandidate(candidates, name, Module.findExportByName(null, name), 'global export');
  }

  for (const moduleName of ['Security', 'CoreFoundation']) {
    const moduleCandidates = findModuleExports(moduleName, name);
    for (const candidate of moduleCandidates) {
      candidates.push(candidate);
    }
  }

  for (const candidate of findMainModuleImports(name)) {
    candidates.push(candidate);
  }

  return uniqueCandidates(candidates);
}

function findModuleExports(moduleName, exportName) {
  const candidates = [];
  const moduleObject = findModule(moduleName);
  if (moduleObject === null) {
    return candidates;
  }

  if (typeof moduleObject.findExportByName === 'function') {
    addCandidate(candidates, exportName, moduleObject.findExportByName(exportName), `${moduleObject.name} export`);
  }

  if (typeof moduleObject.getExportByName === 'function') {
    try {
      addCandidate(candidates, exportName, moduleObject.getExportByName(exportName), `${moduleObject.name} export`);
    } catch (_) {
      // Keep searching the module export table.
    }
  }

  if (typeof moduleObject.enumerateExports === 'function') {
    for (const item of moduleObject.enumerateExports()) {
      if (item.name === exportName) {
        addCandidate(candidates, exportName, item.address, `${moduleObject.name} export table`);
      }
    }
  }

  if (typeof Module.findExportByName === 'function') {
    addCandidate(candidates, exportName, Module.findExportByName(moduleName, exportName), `${moduleName} export`);
  }

  return candidates;
}

function findModule(moduleName) {
  if (typeof Process.findModuleByName === 'function') {
    const moduleObject = Process.findModuleByName(moduleName);
    if (moduleObject !== null) {
      return moduleObject;
    }
  }

  if (typeof Process.getModuleByName === 'function') {
    try {
      return Process.getModuleByName(moduleName);
    } catch (_) {
      // Fall through to path-based lookup.
    }
  }

  for (const moduleObject of Process.enumerateModules()) {
    if (moduleObject.name === moduleName || moduleObject.path.endsWith(`/${moduleName}.framework/${moduleName}`)) {
      return moduleObject;
    }
  }

  return null;
}

function findMainModuleImports(name) {
  const candidates = [];
  const imports = typeof mainModule.enumerateImports === 'function'
    ? mainModule.enumerateImports()
    : [];

  for (const item of imports) {
    if (item.name !== name) {
      continue;
    }

    if (item.address !== undefined && item.address !== null) {
      addCandidate(candidates, name, item.address, `${mainModule.name} import address`);
    }

    if (item.slot !== undefined && item.slot !== null) {
      try {
        addCandidate(candidates, name, item.slot.readPointer(), `${mainModule.name} import slot`);
      } catch (_) {
        // Some imports do not expose a readable slot.
      }
    }
  }

  return candidates;
}

function addCandidate(candidates, name, address, label) {
  if (address === null || address === undefined) {
    return;
  }

  candidates.push({ name, address, label });
}

function uniqueCandidates(candidates) {
  const seen = new Set();
  const unique = [];

  for (const candidate of candidates) {
    const key = candidate.address.toString();
    if (seen.has(key)) {
      continue;
    }

    seen.add(key);
    unique.push(candidate);
  }

  return unique;
}

function toStatus(retval) {
  return retval.toInt32();
}

function pageStart(address) {
  const value = parseInt(address.toString().replace(/^0x/, ''), 16);
  return ptr(Math.floor(value / Process.pageSize) * Process.pageSize);
}

function attachOnce(name, candidate, callbacks) {
  const key = `${name}:${candidate.address}`;
  if (installedHooks.has(key)) {
    return false;
  }

  installedHooks.add(key);
  Interceptor.attach(candidate.address, callbacks);
  console.log(`[KeychainHook] Hooked ${name} at ${candidate.address} (${candidate.label})`);
  return true;
}

function inspectReturnedCFData(resultPointer, helpers) {
  if (resultPointer.isNull()) {
    return;
  }

  if (!helpers.canInspectCFData) {
    console.log('[KeychainHook] CFData helpers unavailable; skipping returned item inspection');
    return;
  }

  try {
    const returnedItem = resultPointer.readPointer();
    if (returnedItem.isNull()) {
      return;
    }

    if (String(helpers.CFGetTypeID(returnedItem)) === helpers.cfDataTypeID) {
      const length = helpers.CFDataGetLength(returnedItem);
      console.log(`[KeychainHook] SecItemCopyMatching returned CFData length: ${length} bytes`);
    } else {
      console.log('[KeychainHook] SecItemCopyMatching returned a non-CFData item');
    }
  } catch (error) {
    console.log(`[KeychainHook] Could not inspect returned item: ${error}`);
  }
}

function hookStatusFunction(name, argumentFormatter) {
  const candidates = findExports(name);
  if (candidates.length === 0) {
    console.log(`[KeychainHook] ${name} not found`);
    return;
  }

  for (const candidate of candidates) {
    attachOnce(name, candidate, {
      onEnter(args) {
        console.log(`[KeychainHook] ${name}(${argumentFormatter(args)})`);
      },
      onLeave(retval) {
        console.log(`[KeychainHook] ${name} returned: ${toStatus(retval)}`);
      }
    });
  }
}

const cfGetTypeIDAddress = findExport('CFGetTypeID');
const cfDataGetTypeIDAddress = findExport('CFDataGetTypeID');
const cfDataGetLengthAddress = findExport('CFDataGetLength');
const secItemCopyMatchingCandidates = findExports('SecItemCopyMatching');
const cfHelpers = {
  canInspectCFData: cfGetTypeIDAddress !== null &&
    cfDataGetTypeIDAddress !== null &&
    cfDataGetLengthAddress !== null,
  CFGetTypeID: null,
  CFDataGetTypeID: null,
  CFDataGetLength: null,
  cfDataTypeID: null
};

if (cfHelpers.canInspectCFData) {
  cfHelpers.CFGetTypeID = new NativeFunction(cfGetTypeIDAddress, 'ulong', ['pointer']);
  cfHelpers.CFDataGetTypeID = new NativeFunction(cfDataGetTypeIDAddress, 'ulong', []);
  cfHelpers.CFDataGetLength = new NativeFunction(cfDataGetLengthAddress, 'long', ['pointer']);
  cfHelpers.cfDataTypeID = String(cfHelpers.CFDataGetTypeID());
}

if (secItemCopyMatchingCandidates.length === 0) {
  console.log('[KeychainHook] SecItemCopyMatching not found');
} else {
  for (const candidate of secItemCopyMatchingCandidates) {
    attachOnce('SecItemCopyMatching', candidate, {
      onEnter(args) {
        this.resultPointer = args[1];
        console.log(`[KeychainHook] SecItemCopyMatching(query=${args[0]}, result=${args[1]})`);
      },
      onLeave(retval) {
        const status = toStatus(retval);
        console.log(`[KeychainHook] SecItemCopyMatching returned: ${status}`);

        if (status !== 0 || this.resultPointer.isNull()) {
          return;
        }

        inspectReturnedCFData(this.resultPointer, cfHelpers);
      }
    });
  }
}

hookStatusFunction('SecItemAdd', args => `query=${args[0]}, result=${args[1]}`);
hookStatusFunction('SecItemDelete', args => `query=${args[0]}`);

function replaceImportSlot(name, slotOffset, returnType, argumentTypes, callbackFactory) {
  const originalAddress = findExport(name);
  if (originalAddress === null) {
    console.log(`[KeychainHook] Cannot wrap ${name} import slot; export not found`);
    return;
  }

  const slot = mainModule.base.add(slotOffset);
  const originalFunction = new NativeFunction(originalAddress, returnType, argumentTypes);
  const callback = new NativeCallback(callbackFactory(originalFunction), returnType, argumentTypes);
  retainedCallbacks.push(callback);

  try {
    Memory.protect(pageStart(slot), Process.pageSize, 'rw-');
    slot.writePointer(callback);
    console.log(`[KeychainHook] Wrapped ${name} import slot at ${slot} -> ${callback}`);
  } catch (error) {
    console.log(`[KeychainHook] Could not wrap ${name} import slot at ${slot}: ${error}`);
  }
}

if (mainModule.name === 'KeychainTestApp') {
  replaceImportSlot(
    'SecItemAdd',
    0xc160,
    'int',
    ['pointer', 'pointer'],
    originalFunction => function (query, result) {
      console.log(`[KeychainHook:Slot] SecItemAdd(query=${query}, result=${result})`);
      const status = originalFunction(query, result);
      console.log(`[KeychainHook:Slot] SecItemAdd returned: ${status}`);
      return status;
    }
  );

  replaceImportSlot(
    'SecItemCopyMatching',
    0xc168,
    'int',
    ['pointer', 'pointer'],
    originalFunction => function (query, result) {
      console.log(`[KeychainHook:Slot] SecItemCopyMatching(query=${query}, result=${result})`);
      const status = originalFunction(query, result);
      console.log(`[KeychainHook:Slot] SecItemCopyMatching returned: ${status}`);

      if (status === 0) {
        inspectReturnedCFData(result, cfHelpers);
      }

      return status;
    }
  );

  replaceImportSlot(
    'SecItemDelete',
    0xc170,
    'int',
    ['pointer'],
    originalFunction => function (query) {
      console.log(`[KeychainHook:Slot] SecItemDelete(query=${query})`);
      const status = originalFunction(query);
      console.log(`[KeychainHook:Slot] SecItemDelete returned: ${status}`);
      return status;
    }
  );
}
