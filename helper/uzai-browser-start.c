// Uzai-Browser: der Start-Stummel für CEFs bootstrap.exe (docs/BROWSER_PLAN.md 2.1, docs/SECURITY.md „Uzai-Browser“).
//
// CEF (Chromium Embedded Framework, M138+) schaltet die Windows-Sandbox nur ein, wenn das Hauptprogramm der
// offizielle bootstrap.exe ist. Der wird zu uzai-browser.exe umbenannt, lädt die gleichnamige DLL aus demselben
// Ordner (diese Datei, gebaut als assets/browser/cef/uzai-browser-start.dll) und ruft RunWinMain – in JEDEM
// Prozess: Browser, Renderer, GPU, Netz. Die Sandbox-Dienste hat er dann schon vorbereitet (sandbox_info).
//
// Was dieser Stummel tut, und zwar nur das:
//   Unterprozess (--type=… in der Befehlszeile): libcef.dll genau von dem Pfad laden, den der Browserprozess
//     mitgibt (--libcef-path=…), die API-Fassung festlegen (cef_api_hash) und cef_execute_process rufen. Keine
//     .NET-Laufzeit, kein eigener Code danach – der Renderer ist so abgeschottet wie bei cefclient.
//   Browserprozess: die .NET-Laufzeit (v4, mscoree) laden und uzai-browser-kern.dll (C#, vom Helfer übersetzt)
//     mit den Zeigern starten. Alles Weitere (CEF, Leitung zu Uzai, Regeln) steht dort.
//
// Freistehendes C ohne Laufzeitbibliothek: hier unter Linux mit clang (Ziel x86_64-pc-windows-msvc) und
// lld-link gebaut (tools/kern_shim_bauen.sh, reproduzierbar, Prüfsumme in src/core/browser_kern.gd und im Helfer).
// Keine Zeichenketten-Funktionen der C-Bibliothek, keine großen Stapel-Puffer (kein __chkstk), kein DllMain.

typedef unsigned short wchar;
typedef unsigned long dword;
typedef unsigned long long usize;
typedef void* handle;
typedef long hresult;

#define UZAI_CEF_API 15101
#define LOAD_WITH_ALTERED_SEARCH_PATH 0x00000008
#define GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS 0x00000004
#define GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT 0x00000002
#define MAX_PFAD 1024

// Rückgabewerte, wenn der Stummel selbst abbricht (CEF-Codes sind klein, die Installer-Codes 100–199).
#define UZS_KEINE_LIBCEF 201
#define UZS_LIBCEF_LADEN 202
#define UZS_API_FASSUNG 203
#define UZS_CLR 204
#define UZS_PFAD 205

typedef struct { handle instance; } cef_main_args_t;
typedef const char* (*cef_api_hash_t)(int version, int entry);
typedef int (*cef_execute_process_t)(const cef_main_args_t* args, void* application, void* windows_sandbox_info);

__declspec(dllimport) wchar* __stdcall GetCommandLineW(void);
__declspec(dllimport) handle __stdcall LoadLibraryExW(const wchar* name, handle file, dword flags);
__declspec(dllimport) void* __stdcall GetProcAddress(handle module, const char* name);
__declspec(dllimport) int __stdcall GetModuleHandleExW(dword flags, const void* name, handle* module);
__declspec(dllimport) dword __stdcall GetModuleFileNameW(handle module, wchar* name, dword size);
__declspec(dllimport) hresult __stdcall CLRCreateInstance(const void* clsid, const void* iid, void** out);

// Die drei COM-Schnittstellen der .NET-Laufzeit, nur die Einträge, die wir rufen (feste Plätze in der Tabelle).
typedef struct guid_t { dword a; unsigned short b; unsigned short c; unsigned char d[8]; } guid_t;
typedef struct meta_host_t { struct meta_host_vt* vt; } meta_host_t;
typedef struct runtime_info_t { struct runtime_info_vt* vt; } runtime_info_t;
typedef struct runtime_host_t { struct runtime_host_vt* vt; } runtime_host_t;
struct meta_host_vt {
  void* q; void* add; void* rel;
  hresult (__stdcall *GetRuntime)(meta_host_t*, const wchar*, const guid_t*, void**);
};
struct runtime_info_vt {
  void* q; void* add; void* rel;
  void* GetVersionString; void* GetRuntimeDirectory; void* IsLoaded; void* LoadErrorString; void* LoadLibrary; void* GetProcAddress;
  hresult (__stdcall *GetInterface)(runtime_info_t*, const guid_t*, const guid_t*, void**);
};
struct runtime_host_vt {
  void* q; void* add; void* rel;
  hresult (__stdcall *Start)(runtime_host_t*);
  void* Stop; void* SetHostControl; void* GetCLRControl; void* UnloadAppDomain; void* ExecuteInAppDomain; void* GetCurrentAppDomainId;
  void* ExecuteApplication;
  hresult (__stdcall *ExecuteInDefaultAppDomain)(runtime_host_t*, const wchar*, const wchar*, const wchar*, const wchar*, dword*);
};

static const guid_t CLSID_CLRMetaHost = { 0x9280188d, 0x0e8e, 0x4867, { 0xb3, 0x0c, 0x7f, 0xa8, 0x38, 0x84, 0xe8, 0xde } };
static const guid_t IID_ICLRMetaHost = { 0xd332db9e, 0xb9b3, 0x4125, { 0x82, 0x07, 0xa1, 0x48, 0x84, 0xf5, 0x32, 0x16 } };
static const guid_t IID_ICLRRuntimeInfo = { 0xbd39d1d2, 0xba2f, 0x486a, { 0x89, 0xb0, 0xb4, 0xb0, 0xcb, 0x46, 0x68, 0x91 } };
static const guid_t CLSID_CLRRuntimeHost = { 0x90f1a06e, 0x7712, 0x4762, { 0x86, 0xb5, 0x7a, 0x5e, 0xba, 0x6b, 0xdb, 0x02 } };
static const guid_t IID_ICLRRuntimeHost = { 0x90f1a06c, 0x7712, 0x4762, { 0x86, 0xb5, 0x7a, 0x5e, 0xba, 0x6b, 0xdb, 0x02 } };

// Der erwartete Windows-API-Hash der Fassung 15101 (cef_api_versions.json; tests/fixtures/cef_api_15101.json).
static const char ERWARTETER_HASH[] = "5933e18e1d2879e23205c70c637bf817c3f32454";

// --- kleine Helfer (statt der C-Bibliothek) -----------------------------------------------------------

static int w_laenge(const wchar* s) {
  int n = 0;
  while (s[n]) n++;
  return n;
}

static int w_beginnt(const wchar* s, const wchar* mit) {
  int i = 0;
  for (; mit[i]; i++) if (s[i] != mit[i]) return 0;
  return i;
}

static int c_gleich(const char* a, const char* b) {
  int i = 0;
  for (; a[i] && b[i]; i++) if (a[i] != b[i]) return 0;
  return a[i] == b[i];
}

// Wert eines Schalters „--name=wert“ aus der Befehlszeile (Anführungszeichen wie bei Chromium: der ganze
// Schalter oder nur der Wert kann in "…" stehen). Schreibt höchstens max-1 Zeichen nach aus; 0 = nicht da.
static int schalter(const wchar* zeile, const wchar* name, wchar* aus, int max) {
  int i = 0, n = 0;
  int in_anf = 0;
  while (zeile[i]) {
    // Ein Schalter beginnt am Anfang oder nach Leerraum (ggf. mit einem Anführungszeichen davor).
    int start = i;
    if (zeile[i] == '"') { in_anf = 1; i++; }
    if (zeile[i] == '-' && zeile[i + 1] == '-') {
      int k = w_beginnt(zeile + i + 2, name);
      if (k && zeile[i + 2 + k] == '=') {
        int j = i + 3 + k;
        int wert_anf = in_anf;
        if (zeile[j] == '"') { wert_anf = 1; j++; }
        while (zeile[j] && n < max - 1) {
          if (wert_anf ? zeile[j] == '"' : zeile[j] == ' ') break;
          aus[n++] = zeile[j++];
        }
        aus[n] = 0;
        return n;
      }
    }
    // Zum nächsten Leerzeichen außerhalb von Anführungszeichen.
    i = start;
    in_anf = 0;
    while (zeile[i]) {
      if (zeile[i] == '"') in_anf = !in_anf;
      else if (zeile[i] == ' ' && !in_anf) break;
      i++;
    }
    while (zeile[i] == ' ') i++;
  }
  aus[0] = 0;
  return 0;
}

static int hat_schalter(const wchar* zeile, const wchar* name) {
  wchar puffer[8];
  return schalter(zeile, name, puffer, 8) > 0;
}

static void hex(usize v, wchar* aus) {
  static const char z[] = "0123456789abcdef";
  for (int i = 15; i >= 0; i--) { aus[i] = (wchar)z[v & 15]; v >>= 4; }
  aus[16] = 0;
}

static void w_anhaengen(wchar* ziel, int* n, const wchar* s, int max) {
  for (int i = 0; s[i] && *n < max - 1; i++) ziel[(*n)++] = s[i];
  ziel[*n] = 0;
}

// Pfad dieser DLL, Dateiname durch „name“ ersetzt. 0 bei Fehler.
static int nachbar(const wchar* name, wchar* aus, int max) {
  handle modul = 0;
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (const void*)&nachbar, &modul)) return 0;
  dword n = GetModuleFileNameW(modul, aus, (dword)max);
  if (n == 0 || n >= (dword)max) return 0;
  int schnitt = -1;
  for (int i = 0; aus[i]; i++) if (aus[i] == '\\' || aus[i] == '/') schnitt = i;
  if (schnitt < 0) return 0;
  int k = schnitt + 1;
  for (int i = 0; name[i]; i++) { if (k >= max - 1) return 0; aus[k++] = name[i]; }
  aus[k] = 0;
  return 1;
}

// --- Unterprozess: nur libcef laden und ausführen ----------------------------------------------------

static int unterprozess(handle instance, void* sandbox_info) {
  wchar pfad[MAX_PFAD];
  const wchar* zeile = GetCommandLineW();
  if (!schalter(zeile, L"libcef-path", pfad, MAX_PFAD)) return UZS_KEINE_LIBCEF;
  // Nur ein voller Pfad auf libcef.dll – nichts Relatives, nichts anderes.
  int n = w_laenge(pfad);
  if (n < 12 || pfad[1] != ':' || pfad[2] != '\\') return UZS_PFAD;
  // „\libcef.dll“ sind 11 Zeichen (bis 0.16.35 stand hier 10: jeder Unterprozess endete mit 205, Chromium meldete
  // nach GPU, SwiftShader und Display-Compositor „GPU process isn't usable“).
  const wchar* ende = pfad + n - 11;
  if (!w_beginnt(ende, L"\\libcef.dll")) return UZS_PFAD;
  handle lib = LoadLibraryExW(pfad, 0, LOAD_WITH_ALTERED_SEARCH_PATH);
  if (!lib) return UZS_LIBCEF_LADEN;
  cef_api_hash_t api_hash = (cef_api_hash_t)GetProcAddress(lib, "cef_api_hash");
  cef_execute_process_t ausfuehren = (cef_execute_process_t)GetProcAddress(lib, "cef_execute_process");
  if (!api_hash || !ausfuehren) return UZS_LIBCEF_LADEN;
  // Legt die API-Fassung für diesen Prozess fest; NULL oder ein anderer Hash: diese libcef passt nicht zu uns.
  const char* h = api_hash(UZAI_CEF_API, 0);
  if (!h || !c_gleich(h, ERWARTETER_HASH)) return UZS_API_FASSUNG;
  cef_main_args_t args;
  args.instance = instance;
  return ausfuehren(&args, 0, sandbox_info);
}

// --- Browserprozess: .NET-Laufzeit laden und den Kern starten -------------------------------------------

static int browserprozess(handle instance, int cmd_show, void* sandbox_info, void* version_info) {
  wchar kern[MAX_PFAD];
  if (!nachbar(L"uzai-browser-kern.dll", kern, MAX_PFAD)) return UZS_PFAD;
  meta_host_t* meta = 0;
  runtime_info_t* info = 0;
  runtime_host_t* host = 0;
  if (CLRCreateInstance(&CLSID_CLRMetaHost, &IID_ICLRMetaHost, (void**)&meta) < 0 || !meta) return UZS_CLR;
  if (meta->vt->GetRuntime(meta, L"v4.0.30319", &IID_ICLRRuntimeInfo, (void**)&info) < 0 || !info) return UZS_CLR;
  if (info->vt->GetInterface(info, &CLSID_CLRRuntimeHost, &IID_ICLRRuntimeHost, (void**)&host) < 0 || !host) return UZS_CLR;
  if (host->vt->Start(host) < 0) return UZS_CLR;
  // Argument an den Kern: feste Form „instance=…;sandbox=…;version=…;show=…“ (Zahlen als 16 Hex-Ziffern).
  wchar arg[160];
  wchar z[17];
  int n = 0;
  arg[0] = 0;
  w_anhaengen(arg, &n, L"instance=", 160); hex((usize)instance, z); w_anhaengen(arg, &n, z, 160);
  w_anhaengen(arg, &n, L";sandbox=", 160); hex((usize)sandbox_info, z); w_anhaengen(arg, &n, z, 160);
  w_anhaengen(arg, &n, L";version=", 160); hex((usize)version_info, z); w_anhaengen(arg, &n, z, 160);
  w_anhaengen(arg, &n, L";show=", 160); hex((usize)(unsigned)cmd_show, z); w_anhaengen(arg, &n, z, 160);
  dword ergebnis = UZS_CLR;
  if (host->vt->ExecuteInDefaultAppDomain(host, kern, L"UzcEinstieg", L"Start", arg, &ergebnis) < 0) return UZS_CLR;
  return (int)ergebnis;
}

// --- Einstieg für bootstrap.exe --------------------------------------------------------------------------

__declspec(dllexport) int RunWinMain(handle instance, wchar* cmdline, int cmd_show, void* sandbox_info, void* version_info) {
  (void)cmdline;
  if (hat_schalter(GetCommandLineW(), L"type")) return unterprozess(instance, sandbox_info);
  return browserprozess(instance, cmd_show, sandbox_info, version_info);
}
