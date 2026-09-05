// Pre-load the REAL compiled Dart brain into globalThis.shauchmapCore so that
// interop.loadCore() resolves synchronously-ish in tests (the browser loader
// checks the global before touching `document`). Requires:
//   npm run build:core
import { loadCoreGlobalNode } from '../src/core/core-loader.node';

loadCoreGlobalNode();
