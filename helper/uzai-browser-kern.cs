// Uzai-Browser: der Browser-Kern – Chromium über CEF (Chromium Embedded Framework), docs/BROWSER_PLAN.md,
// docs/SECURITY.md „Uzai-Browser“.
//
// Wie er läuft: CEFs offizieller bootstrap.exe (umbenannt zu uzai-browser.exe, Sandbox-Broker) lädt den nativen
// Start-Stummel uzai-browser.dll (helper/uzai-browser-start.c); der lädt im Browserprozess die .NET-Laufzeit und ruft
// UzcEinstieg.Start. Renderer, GPU und Netz laufen ohne diesen Code in Chromiums Sandbox. Der Helfer übersetzt diese
// Datei zusammen mit helper/uzai-browser-gemeinsam.cs (JSON, Regeln, Schema, Leitung, Fenster, Blocker) als DLL;
// tests/browser_kern_cs.ps1 prüft sie unter Linux – auch, dass jede Struktur Bit für Bit zur C-Schnittstelle von
// CEF passt (tests/fixtures/cef_api_15101.json, API-Fassung 15101).
//
// Was fest im Code steht (keine Einstellung von außen):
//   - libcef.dll nur von dem Pfad, den der Installer im Bootstrap aufgelöst hat, nur mit gültiger Signatur des
//     CEF-Zertifikats, nur wenn cef_api_hash die Fassung 15101 bestätigt; Sandbox-Zeiger Pflicht, no_sandbox nie;
//   - kein Debug-Anschluss (remote_debugging_port = 0, keine Befehlszeilen-Schalter von außen), keine Brücke zur
//     Seite (keine Erweiterungen, kein Render-Prozess-Code von uns, Meldungen nur über die Bindung in der eigenen Welt);
//   - nur http/https; dieser PC nie, Heimnetz nur selbst eingegeben; andere Protokolle gesperrt; Pop-ups nur nach
//     einem Druck als Tab; Downloads nur erlaubte Dateiarten in Downloads\Uzai Browser, nie geöffnet; Kamera, Mikro,
//     Standort nur nach Rückfrage in Uzai, alles andere abgelehnt; Anmelde- und Dateidialoge, Zertifikatsfehler,
//     Kontextmenüs, Chrome-Befehle (DevTools, Drucken …) gesperrt; Werbe-/Tracker-Blocker im Prozess (UzbFilter);
//   - Chromium ohne Google: Komponenten-Update, Hintergrundnetz, Absturzberichte, Sync, Vorschläge, Übersetzung aus;
//   - Spotify-Sitzung („--uzai-spotify“, UzcSpotify): eigener Datenordner spotify-daten, Hauptrahmen nur Spotify und
//     seine Anmeldedienste (https), ein Tab, stumm, ohne Blocker, Downloads und Rechte; die Seite wird nie ein
//     Connect-Gerät; der Kern liest nur den Schlüssel aus den Kopfzeilen ihrer Anfragen und meldet ihn über die Leitung.
// Leitung zu Uzai: JSON-Zeilen über Standardein-/-ausgabe wie beim WebView2-Wirt (gleiches Schema, UzbSchema).

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

// --- Versatz und Größen der CEF-Strukturen (aus tests/fixtures/cef_api_15101.json) -----------------------

public static class UzcV {
    public const int API = 15101;
    public const string API_HASH = "5933e18e1d2879e23205c70c637bf817c3f32454";
    public const string CEF_ZERTIFIKAT = "3906F72B1D5FA45A6334A8590495FAEB93347E5B";
    public const int BASIS = 40;

    // Größen der Strukturen (Basis 40 + 8 je Funktionszeiger) und Versatz jedes benutzten Zeigers – aus
    // tests/fixtures/cef_api_15101.json (tools/cef_api_tabelle.py); tests/browser_kern_cs.ps1 vergleicht beides.
    public const int APP_GROESSE = 80;
    public const int APP_ON_BEFORE_COMMAND_LINE_PROCESSING = 40;
    public const int APP_GET_BROWSER_PROCESS_HANDLER = 64;
    public const int BROWSER_PROCESS_HANDLER_GROESSE = 96;
    public const int BROWSER_PROCESS_HANDLER_ON_CONTEXT_INITIALIZED = 48;
    public const int BROWSER_PROCESS_HANDLER_ON_BEFORE_CHILD_PROCESS_LAUNCH = 56;
    public const int BROWSER_PROCESS_HANDLER_GET_DEFAULT_CLIENT = 80;
    public const int CLIENT_GROESSE = 192;
    public const int CLIENT_GET_COMMAND_HANDLER = 48;
    public const int CLIENT_GET_CONTEXT_MENU_HANDLER = 56;
    public const int CLIENT_GET_DIALOG_HANDLER = 64;
    public const int CLIENT_GET_DISPLAY_HANDLER = 72;
    public const int CLIENT_GET_DOWNLOAD_HANDLER = 80;
    public const int CLIENT_GET_FOCUS_HANDLER = 104;
    public const int CLIENT_GET_PERMISSION_HANDLER = 120;
    public const int CLIENT_GET_JSDIALOG_HANDLER = 128;
    public const int CLIENT_GET_KEYBOARD_HANDLER = 136;
    public const int CLIENT_GET_LIFE_SPAN_HANDLER = 144;
    public const int CLIENT_GET_LOAD_HANDLER = 152;
    public const int CLIENT_GET_REQUEST_HANDLER = 176;
    public const int LIFE_SPAN_HANDLER_GROESSE = 88;
    public const int LIFE_SPAN_HANDLER_ON_BEFORE_POPUP = 40;
    public const int LIFE_SPAN_HANDLER_ON_AFTER_CREATED = 64;
    public const int LIFE_SPAN_HANDLER_DO_CLOSE = 72;
    public const int LIFE_SPAN_HANDLER_ON_BEFORE_CLOSE = 80;
    public const int LOAD_HANDLER_GROESSE = 72;
    public const int LOAD_HANDLER_ON_LOADING_STATE_CHANGE = 40;
    public const int LOAD_HANDLER_ON_LOAD_ERROR = 64;
    public const int DISPLAY_HANDLER_GROESSE = 144;
    public const int DISPLAY_HANDLER_ON_ADDRESS_CHANGE = 40;
    public const int DISPLAY_HANDLER_ON_TITLE_CHANGE = 48;
    public const int DISPLAY_HANDLER_ON_FULLSCREEN_MODE_CHANGE = 64;
    public const int DISPLAY_HANDLER_ON_CONSOLE_MESSAGE = 88;
    public const int DISPLAY_HANDLER_ON_TOOLTIP = 72;
    public const int DISPLAY_HANDLER_ON_STATUS_MESSAGE = 80;
    public const int REQUEST_HANDLER_GROESSE = 128;
    public const int REQUEST_HANDLER_ON_BEFORE_BROWSE = 40;
    public const int REQUEST_HANDLER_ON_OPEN_URLFROM_TAB = 48;
    public const int REQUEST_HANDLER_GET_RESOURCE_REQUEST_HANDLER = 56;
    public const int REQUEST_HANDLER_GET_AUTH_CREDENTIALS = 64;
    public const int REQUEST_HANDLER_ON_CERTIFICATE_ERROR = 72;
    public const int REQUEST_HANDLER_ON_SELECT_CLIENT_CERTIFICATE = 80;
    public const int REQUEST_HANDLER_ON_RENDER_PROCESS_UNRESPONSIVE = 96;
    public const int REQUEST_HANDLER_ON_RENDER_PROCESS_TERMINATED = 112;
    public const int RESOURCE_REQUEST_HANDLER_GROESSE = 104;
    public const int RESOURCE_REQUEST_HANDLER_ON_BEFORE_RESOURCE_LOAD = 48;
    public const int RESOURCE_REQUEST_HANDLER_ON_PROTOCOL_EXECUTION = 96;
    public const int PERMISSION_HANDLER_GROESSE = 64;
    public const int PERMISSION_HANDLER_ON_REQUEST_MEDIA_ACCESS_PERMISSION = 40;
    public const int PERMISSION_HANDLER_ON_SHOW_PERMISSION_PROMPT = 48;
    public const int DOWNLOAD_HANDLER_GROESSE = 64;
    public const int DOWNLOAD_HANDLER_CAN_DOWNLOAD = 40;
    public const int DOWNLOAD_HANDLER_ON_BEFORE_DOWNLOAD = 48;
    public const int DOWNLOAD_HANDLER_ON_DOWNLOAD_UPDATED = 56;
    public const int JSDIALOG_HANDLER_GROESSE = 72;
    public const int JSDIALOG_HANDLER_ON_JSDIALOG = 40;
    public const int JSDIALOG_HANDLER_ON_BEFORE_UNLOAD_DIALOG = 48;
    public const int DIALOG_HANDLER_GROESSE = 48;
    public const int DIALOG_HANDLER_ON_FILE_DIALOG = 40;
    public const int CONTEXT_MENU_HANDLER_GROESSE = 96;
    public const int CONTEXT_MENU_HANDLER_ON_BEFORE_CONTEXT_MENU = 40;
    public const int CONTEXT_MENU_HANDLER_RUN_CONTEXT_MENU = 48;
    public const int COMMAND_HANDLER_GROESSE = 80;
    public const int COMMAND_HANDLER_ON_CHROME_COMMAND = 40;
    public const int COMMAND_HANDLER_IS_CHROME_APP_MENU_ITEM_VISIBLE = 48;
    public const int COMMAND_HANDLER_IS_CHROME_PAGE_ACTION_ICON_VISIBLE = 64;
    public const int COMMAND_HANDLER_IS_CHROME_TOOLBAR_BUTTON_VISIBLE = 72;
    public const int FOCUS_HANDLER_GROESSE = 64;
    public const int FOCUS_HANDLER_ON_SET_FOCUS = 48;
    public const int KEYBOARD_HANDLER_GROESSE = 56;
    public const int KEYBOARD_HANDLER_ON_PRE_KEY_EVENT = 40;
    public const int DEV_TOOLS_MESSAGE_OBSERVER_GROESSE = 80;
    public const int DEV_TOOLS_MESSAGE_OBSERVER_ON_DEV_TOOLS_METHOD_RESULT = 48;
    public const int DEV_TOOLS_MESSAGE_OBSERVER_ON_DEV_TOOLS_EVENT = 56;
    public const int TASK_GROESSE = 48;
    public const int TASK_EXECUTE = 40;
    public const int BROWSER_GROESSE = 208;
    public const int BROWSER_GET_HOST = 48;
    public const int BROWSER_CAN_GO_BACK = 56;
    public const int BROWSER_GO_BACK = 64;
    public const int BROWSER_CAN_GO_FORWARD = 72;
    public const int BROWSER_GO_FORWARD = 80;
    public const int BROWSER_IS_LOADING = 88;
    public const int BROWSER_RELOAD = 96;
    public const int BROWSER_STOP_LOAD = 112;
    public const int BROWSER_GET_IDENTIFIER = 120;
    public const int BROWSER_GET_MAIN_FRAME = 152;
    public const int BROWSER_HOST_GROESSE = 584;
    public const int BROWSER_HOST_CLOSE_BROWSER = 48;
    public const int BROWSER_HOST_SET_FOCUS = 72;
    public const int BROWSER_HOST_GET_WINDOW_HANDLE = 80;
    public const int BROWSER_HOST_GET_ZOOM_LEVEL = 152;
    public const int BROWSER_HOST_SET_ZOOM_LEVEL = 160;
    public const int BROWSER_HOST_SEND_DEV_TOOLS_MESSAGE = 248;
    public const int BROWSER_HOST_ADD_DEV_TOOLS_MESSAGE_OBSERVER = 264;
    public const int BROWSER_HOST_WAS_HIDDEN = 312;
    public const int BROWSER_HOST_SET_AUDIO_MUTED = 520;
    public const int BROWSER_HOST_IS_FULLSCREEN = 536;
    public const int BROWSER_HOST_EXIT_FULLSCREEN = 544;
    public const int FRAME_GROESSE = 248;
    public const int FRAME_LOAD_URL = 144;
    public const int FRAME_GET_URL = 200;
    public const int FRAME_IS_MAIN = 160;
    public const int REQUEST_GROESSE = 216;
    public const int REQUEST_GET_URL = 48;
    public const int REQUEST_GET_RESOURCE_TYPE = 192;
    public const int REQUEST_GET_FIRST_PARTY_FOR_COOKIES = 176;
    public const int REQUEST_GET_REFERRER_URL = 88;
    public const int REQUEST_GET_HEADER_BY_NAME = 136;
    public const int REQUEST_CONTEXT_GROESSE = 272;
    public const int REQUEST_CONTEXT_SET_PREFERENCE = 72;
    public const int REQUEST_CONTEXT_GET_CACHE_PATH = 120;
    public const int VALUE_GROESSE = 216;
    public const int VALUE_SET_BOOL = 160;
    public const int VALUE_SET_INT = 168;
    public const int VALUE_SET_STRING = 184;
    public const int CALLBACK_GROESSE = 56;
    public const int CALLBACK_CONTINUE = 40;
    public const int CALLBACK_CANCEL = 48;
    public const int AUTH_CALLBACK_GROESSE = 56;
    public const int AUTH_CALLBACK_CANCEL = 48;
    public const int JSDIALOG_CALLBACK_GROESSE = 48;
    public const int JSDIALOG_CALLBACK_CONTINUE = 40;
    public const int BEFORE_DOWNLOAD_CALLBACK_GROESSE = 48;
    public const int BEFORE_DOWNLOAD_CALLBACK_CONTINUE = 40;
    public const int DOWNLOAD_ITEM_CALLBACK_GROESSE = 64;
    public const int DOWNLOAD_ITEM_CALLBACK_CANCEL = 40;
    public const int DOWNLOAD_ITEM_GROESSE = 200;
    public const int DOWNLOAD_ITEM_IS_VALID = 40;
    public const int DOWNLOAD_ITEM_IS_IN_PROGRESS = 48;
    public const int DOWNLOAD_ITEM_IS_COMPLETE = 56;
    public const int DOWNLOAD_ITEM_IS_CANCELED = 64;
    public const int DOWNLOAD_ITEM_IS_INTERRUPTED = 72;
    public const int DOWNLOAD_ITEM_GET_FULL_PATH = 136;
    public const int DOWNLOAD_ITEM_GET_ID = 144;
    public const int DOWNLOAD_ITEM_GET_URL = 152;
    public const int DOWNLOAD_ITEM_GET_SUGGESTED_FILE_NAME = 168;
    public const int MEDIA_ACCESS_CALLBACK_GROESSE = 56;
    public const int MEDIA_ACCESS_CALLBACK_CONTINUE = 40;
    public const int MEDIA_ACCESS_CALLBACK_CANCEL = 48;
    public const int PERMISSION_PROMPT_CALLBACK_GROESSE = 48;
    public const int PERMISSION_PROMPT_CALLBACK_CONTINUE = 40;
    public const int COMMAND_LINE_GROESSE = 208;
    public const int COMMAND_LINE_HAS_SWITCH = 128;
    public const int COMMAND_LINE_GET_SWITCH_VALUE = 136;
    public const int COMMAND_LINE_APPEND_SWITCH = 152;
    public const int COMMAND_LINE_APPEND_SWITCH_WITH_VALUE = 160;
    public const int COMMAND_LINE_REMOVE_SWITCH = 200;
    public const int MENU_MODEL_GROESSE = 488;
    public const int MENU_MODEL_CLEAR = 48;
    public const int UNRESPONSIVE_PROCESS_CALLBACK_GROESSE = 56;
    public const int UNRESPONSIVE_PROCESS_CALLBACK_WAIT = 40;
    public const int SELECT_CLIENT_CERTIFICATE_CALLBACK_GROESSE = 48;
    public const int SELECT_CLIENT_CERTIFICATE_CALLBACK_SELECT = 40;
    public const int FILE_DIALOG_CALLBACK_GROESSE = 56;
    public const int FILE_DIALOG_CALLBACK_CANCEL = 48;
    public const int RUN_CONTEXT_MENU_CALLBACK_GROESSE = 56;
    public const int RUN_CONTEXT_MENU_CALLBACK_CANCEL = 48;
    public const int REGISTRATION_GROESSE = 40;

    // Von Hand geschriebene C-Strukturen (include/internal/cef_types*.h, cef_version_info.h), Felder mit Versatz.
    public const int SETTINGS_GROESSE = 448;
    public const int SETTINGS_NO_SANDBOX = 8, SETTINGS_MULTI_THREADED_MESSAGE_LOOP = 88, SETTINGS_EXTERNAL_MESSAGE_PUMP = 92,
        SETTINGS_WINDOWLESS_RENDERING_ENABLED = 96, SETTINGS_COMMAND_LINE_ARGS_DISABLED = 100, SETTINGS_CACHE_PATH = 104,
        SETTINGS_ROOT_CACHE_PATH = 128, SETTINGS_PERSIST_SESSION_COOKIES = 152, SETTINGS_LOCALE = 208, SETTINGS_LOG_FILE = 232,
        SETTINGS_LOG_SEVERITY = 256, SETTINGS_LOG_ITEMS = 260, SETTINGS_REMOTE_DEBUGGING_PORT = 336, SETTINGS_BACKGROUND_COLOR = 344,
        SETTINGS_ACCEPT_LANGUAGE_LIST = 352;
    public const int REQUEST_CONTEXT_SETTINGS_GROESSE = 96;
    public const int REQUEST_CONTEXT_SETTINGS_CACHE_PATH = 8, REQUEST_CONTEXT_SETTINGS_PERSIST_SESSION_COOKIES = 32,
        REQUEST_CONTEXT_SETTINGS_ACCEPT_LANGUAGE_LIST = 40;
    public const int BROWSER_SETTINGS_GROESSE = 264;
    public const int BROWSER_SETTINGS_JAVASCRIPT_CLOSE_WINDOWS = 208, BROWSER_SETTINGS_JAVASCRIPT_ACCESS_CLIPBOARD = 212,
        BROWSER_SETTINGS_JAVASCRIPT_DOM_PASTE = 216, BROWSER_SETTINGS_BACKGROUND_COLOR = 248, BROWSER_SETTINGS_CHROME_STATUS_BUBBLE = 252,
        BROWSER_SETTINGS_CHROME_ZOOM_BUBBLE = 256;
    public const int WINDOW_INFO_GROESSE = 112;
    public const int WINDOW_INFO_EX_STYLE = 8, WINDOW_INFO_WINDOW_NAME = 16, WINDOW_INFO_STYLE = 40, WINDOW_INFO_BOUNDS = 44,
        WINDOW_INFO_PARENT_WINDOW = 64, WINDOW_INFO_RUNTIME_STYLE = 104;
    public const int VERSION_INFO_MIT_INSTALLER = 104;
    public const int VERSION_INFO_CEF_VERSION_MAJOR = 8, VERSION_INFO_SANDBOX_COMPAT_HASH = 40, VERSION_INFO_LIBCEF_PATH = 64,
        VERSION_INFO_LIBCEF_IS_BUNDLED = 72, VERSION_INFO_LIBCEF_VERSION_FULL = 80, VERSION_INFO_INSTALLER_ERROR_CODE = 88,
        VERSION_INFO_INSTALLER_ERROR_MESSAGE = 96;
    public const int MAIN_ARGS_GROESSE = 8;
    public const int STRING_GROESSE = 24;
}

// --- Aufrufformen der Funktionszeiger (CEF_CALLBACK = __stdcall; unter x64 ohne Unterschied) ---------------

public static class UzcD {
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate void SelfD(IntPtr self);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int IntSelfD(IntPtr self);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate uint UIntSelfD(IntPtr self);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate IntPtr PtrSelfD(IntPtr self);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate double DoubleSelfD(IntPtr self);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate void SelfIntD(IntPtr self, int a);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate void SelfUIntD(IntPtr self, uint a);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate void SelfDoubleD(IntPtr self, double a);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate void SelfPtrD(IntPtr self, IntPtr a);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int IntSelfPtrD(IntPtr self, IntPtr a);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int IntSelfIntD(IntPtr self, int a);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate IntPtr PtrSelfPtrD(IntPtr self, IntPtr a);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate void SelfPtrPtrD(IntPtr self, IntPtr a, IntPtr b);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int IntSelfPtrPtrD(IntPtr self, IntPtr a, IntPtr b);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate void SelfPtrIntD(IntPtr self, IntPtr a, int b);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int IntSelfPtrIntD(IntPtr self, IntPtr a, int b);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate void SelfPtr3D(IntPtr self, IntPtr a, IntPtr b, IntPtr c);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate void SelfPtr4D(IntPtr self, IntPtr a, IntPtr b, IntPtr c, IntPtr d);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int IntSelfPtr5D(IntPtr self, IntPtr a, IntPtr b, IntPtr c, IntPtr d, IntPtr e);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int SendDtD(IntPtr self, IntPtr message, UIntPtr size);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate void JsContD(IntPtr self, int success, IntPtr userInput);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate void DlContD(IntPtr self, IntPtr path, int showDialog);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int SetPrefD(IntPtr self, IntPtr name, IntPtr value, IntPtr error);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int BeforePopupD(IntPtr self, IntPtr browser, IntPtr frame, int popupId,
        IntPtr targetUrl, IntPtr targetFrameName, int disposition, int userGesture, IntPtr features, IntPtr windowInfo, IntPtr client, IntPtr settings,
        IntPtr extraInfo, IntPtr noJs);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate void LoadStateD(IntPtr self, IntPtr browser, int laedt, int zurueck, int vor);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate void LoadErrorD(IntPtr self, IntPtr browser, IntPtr frame, int code, IntPtr text, IntPtr url);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int ConsoleD(IntPtr self, IntPtr browser, int level, IntPtr msg, IntPtr src, int line);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int BeforeBrowseD(IntPtr self, IntPtr browser, IntPtr frame, IntPtr request, int gesture, int redirect);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int OpenUrlD(IntPtr self, IntPtr browser, IntPtr frame, IntPtr url, int disp, int gesture);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate IntPtr GetRrhD(IntPtr self, IntPtr browser, IntPtr frame, IntPtr request, int nav, int dl,
        IntPtr initiator, IntPtr disable);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int AuthD(IntPtr self, IntPtr browser, IntPtr origin, int proxy, IntPtr host, int port,
        IntPtr realm, IntPtr scheme, IntPtr callback);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int CertErrD(IntPtr self, IntPtr browser, int err, IntPtr url, IntPtr ssl, IntPtr cb);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int SelectCertD(IntPtr self, IntPtr browser, int proxy, IntPtr host, int port, UIntPtr count,
        IntPtr certs, IntPtr cb);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate void TerminatedD(IntPtr self, IntPtr browser, int status, int code, IntPtr text);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int BeforeLoadD(IntPtr self, IntPtr browser, IntPtr frame, IntPtr request, IntPtr cb);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate void ProtoExecD(IntPtr self, IntPtr browser, IntPtr frame, IntPtr request, IntPtr allow);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int MediaPermD(IntPtr self, IntPtr browser, IntPtr frame, IntPtr origin, uint requested, IntPtr cb);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int PermPromptD(IntPtr self, IntPtr browser, ulong id, IntPtr origin, uint requested, IntPtr cb);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int CanDlD(IntPtr self, IntPtr browser, IntPtr url, IntPtr method);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int BeforeDlD(IntPtr self, IntPtr browser, IntPtr item, IntPtr name, IntPtr cb);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate void DlUpdD(IntPtr self, IntPtr browser, IntPtr item, IntPtr cb);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int JsDialogD(IntPtr self, IntPtr browser, IntPtr origin, int type, IntPtr msg, IntPtr def,
        IntPtr cb, IntPtr suppress);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int UnloadD(IntPtr self, IntPtr browser, IntPtr msg, int reload, IntPtr cb);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int FileDialogD(IntPtr self, IntPtr browser, int mode, IntPtr title, IntPtr def, IntPtr f1,
        IntPtr f2, IntPtr f3, IntPtr cb);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int ChromeCmdD(IntPtr self, IntPtr browser, int cmd, int disp);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int PreKeyD(IntPtr self, IntPtr browser, IntPtr ev, IntPtr os, IntPtr shortcut);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate void DtResultD(IntPtr self, IntPtr browser, int id, int ok, IntPtr data, UIntPtr size);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate void DtEventD(IntPtr self, IntPtr browser, IntPtr method, IntPtr data, UIntPtr size);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate IntPtr RunInstallerD(byte[] command, byte[] config);
}

// --- Die C-Schnittstelle: Exporte, Zeichenketten, eigene Objekte mit Referenzzählung --------------------------

public static class UzcApi {
    [DllImport("libcef.dll", CallingConvention = CallingConvention.Cdecl)] public static extern IntPtr cef_api_hash(int version, int entry);
    [DllImport("libcef.dll", CallingConvention = CallingConvention.Cdecl)] public static extern IntPtr cef_version_full();
    [DllImport("libcef.dll", CallingConvention = CallingConvention.Cdecl)] public static extern int cef_version_info(int entry);
    [DllImport("libcef.dll", CallingConvention = CallingConvention.Cdecl)] public static extern int cef_execute_process(IntPtr args, IntPtr app, IntPtr sandbox);
    [DllImport("libcef.dll", CallingConvention = CallingConvention.Cdecl)] public static extern int cef_initialize(IntPtr args, IntPtr settings, IntPtr app, IntPtr sandbox);
    [DllImport("libcef.dll", CallingConvention = CallingConvention.Cdecl)] public static extern void cef_shutdown();
    [DllImport("libcef.dll", CallingConvention = CallingConvention.Cdecl)] public static extern void cef_run_message_loop();
    [DllImport("libcef.dll", CallingConvention = CallingConvention.Cdecl)] public static extern void cef_quit_message_loop();
    [DllImport("libcef.dll", CallingConvention = CallingConvention.Cdecl)] public static extern int cef_get_exit_code();
    [DllImport("libcef.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr cef_browser_host_create_browser_sync(IntPtr windowInfo, IntPtr client, IntPtr url, IntPtr settings, IntPtr extraInfo, IntPtr requestContext);
    [DllImport("libcef.dll", CallingConvention = CallingConvention.Cdecl)] public static extern IntPtr cef_request_context_create_context(IntPtr settings, IntPtr handler);
    [DllImport("libcef.dll", CallingConvention = CallingConvention.Cdecl)] public static extern IntPtr cef_request_context_get_global_context();
    [DllImport("libcef.dll", CallingConvention = CallingConvention.Cdecl)] public static extern void cef_string_userfree_utf16_free(IntPtr s);
    [DllImport("libcef.dll", CallingConvention = CallingConvention.Cdecl)] public static extern void cef_string_utf16_clear(IntPtr s);
    [DllImport("libcef.dll", CallingConvention = CallingConvention.Cdecl)] public static extern IntPtr cef_value_create();
    [DllImport("libcef.dll", CallingConvention = CallingConvention.Cdecl)] public static extern int cef_currently_on(int threadId);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] public static extern IntPtr LoadLibraryExW(string name, IntPtr file, uint flags);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr GetModuleHandleW(string name);
    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, ExactSpelling = true)] public static extern IntPtr GetProcAddress(IntPtr module, string name);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindResourceW(IntPtr module, string name, IntPtr type);
    [DllImport("kernel32.dll")] public static extern IntPtr LoadResource(IntPtr module, IntPtr res);
    [DllImport("kernel32.dll")] public static extern IntPtr LockResource(IntPtr res);
    [DllImport("kernel32.dll")] public static extern uint SizeofResource(IntPtr module, IntPtr res);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int hh, uint flags);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll")] static extern bool SetHandleInformation(IntPtr h, uint mask, uint flags);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr p, uint access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool GetTokenInformation(IntPtr t, int cls, out int info, int len, out int ret);

    public const uint LOAD_WITH_ALTERED_SEARCH_PATH = 0x00000008;

    // Standardein- und -ausgabe nicht vererben: Kein Unterprozess von Chromium bekommt die Leitung.
    public static void HandlesSchliessen() {
        foreach (int n in new[] { -10, -11, -12 }) {
            IntPtr h = GetStdHandle(n);
            if (h != IntPtr.Zero && h != new IntPtr(-1)) SetHandleInformation(h, 1, 0);
        }
    }

    public static bool Erhoeht() {
        IntPtr t;
        if (!OpenProcessToken(GetCurrentProcess(), 0x0008, out t)) return true;
        try {
            int erh, len;
            if (!GetTokenInformation(t, 20, out erh, 4, out len)) return true;
            return erh != 0;
        } finally {
            CloseHandle(t);
        }
    }

    // --- Zeichenketten (cef_string_t = utf16: str, length, dtor) -------------------------------------------

    public static string Text(IntPtr p) {
        if (p == IntPtr.Zero) return "";
        IntPtr s = Marshal.ReadIntPtr(p);
        long n = Marshal.ReadIntPtr(p, 8).ToInt64();
        if (s == IntPtr.Zero || n <= 0) return "";
        if (n > 4 * 1024 * 1024) n = 4 * 1024 * 1024;
        return Marshal.PtrToStringUni(s, (int)n);
    }

    // Ergebnis einer Bibliotheksfunktion (cef_string_userfree_t): lesen und freigeben.
    public static string Frei(IntPtr p) {
        if (p == IntPtr.Zero) return "";
        string t = Text(p);
        cef_string_userfree_utf16_free(p);
        return t;
    }

    public static string Utf8(IntPtr p, int max) {
        if (p == IntPtr.Zero) return "";
        int n = 0;
        while (n < max && Marshal.ReadByte(p, n) != 0) n++;
        var b = new byte[n];
        Marshal.Copy(p, b, 0, n);
        return Encoding.UTF8.GetString(b);
    }

    // Ein cef_string_t für die Dauer eines Aufrufs.
    public sealed class Str : IDisposable {
        public IntPtr P;
        IntPtr puffer;

        public Str(string s) {
            s = s ?? "";
            P = Marshal.AllocHGlobal(UzcV.STRING_GROESSE);
            puffer = Marshal.StringToHGlobalUni(s);
            Marshal.WriteIntPtr(P, 0, puffer);
            Marshal.WriteIntPtr(P, 8, new IntPtr(s.Length));
            Marshal.WriteIntPtr(P, 16, IntPtr.Zero);
        }

        public void Dispose() {
            if (P != IntPtr.Zero) { Marshal.FreeHGlobal(puffer); Marshal.FreeHGlobal(P); P = IntPtr.Zero; }
        }
    }

    // Ein cef_string_t-Feld in einer Struktur füllen; der Puffer lebt, solange die Liste ihn hält.
    public static void StrFeld(IntPtr struktur, int versatz, string s, List<IntPtr> halter) {
        s = s ?? "";
        IntPtr puffer = Marshal.StringToHGlobalUni(s);
        halter.Add(puffer);
        Marshal.WriteIntPtr(struktur, versatz, puffer);
        Marshal.WriteIntPtr(struktur, versatz + 8, new IntPtr(s.Length));
        Marshal.WriteIntPtr(struktur, versatz + 16, IntPtr.Zero);
    }

    public static IntPtr Leer(int groesse) {
        IntPtr p = Marshal.AllocHGlobal(groesse);
        for (int i = 0; i < groesse; i++) Marshal.WriteByte(p, i, 0);
        Marshal.WriteIntPtr(p, 0, new IntPtr(groesse));
        return p;
    }

    // --- Bibliotheksobjekte: Funktionszeiger am Versatz rufen, Referenzen halten/freigeben ------------------

    public static T Fn<T>(IntPtr obj, int versatz) where T : class {
        IntPtr fp = Marshal.ReadIntPtr(obj, versatz);
        if (fp == IntPtr.Zero) return null;
        return (T)(object)Marshal.GetDelegateForFunctionPointer(fp, typeof(T));
    }

    public static void Halten(IntPtr obj) {
        if (obj == IntPtr.Zero) return;
        var f = Fn<UzcD.SelfD>(obj, 8);
        if (f != null) f(obj);
    }

    public static void Loslassen(IntPtr obj) {
        if (obj == IntPtr.Zero) return;
        var f = Fn<UzcD.IntSelfD>(obj, 16);
        if (f != null) f(obj);
    }

    // --- Eigene Objekte (source=client): Struktur mit Basis und unseren Funktionszeigern ----------------------

    sealed class Objekt {
        public int Refs = 1;
        public readonly List<Delegate> Halter = new List<Delegate>();
    }

    static readonly object sperre = new object();
    static readonly Dictionary<IntPtr, Objekt> objekte = new Dictionary<IntPtr, Objekt>();
    static readonly UzcD.SelfD dAddRef = AddRef;
    static readonly UzcD.IntSelfD dRelease = Release;
    static readonly UzcD.IntSelfD dHasOne = HasOne;
    static readonly UzcD.IntSelfD dHasAtLeastOne = HasAtLeastOne;
    static readonly IntPtr pAddRef = Marshal.GetFunctionPointerForDelegate(dAddRef);
    static readonly IntPtr pRelease = Marshal.GetFunctionPointerForDelegate(dRelease);
    static readonly IntPtr pHasOne = Marshal.GetFunctionPointerForDelegate(dHasOne);
    static readonly IntPtr pHasAtLeastOne = Marshal.GetFunctionPointerForDelegate(dHasAtLeastOne);

    // paare: Versatz, Delegate, Versatz, Delegate … Die Delegates bleiben am Leben, solange das Objekt lebt.
    public static IntPtr Neu(int groesse, params object[] paare) {
        IntPtr p = Leer(groesse);
        Marshal.WriteIntPtr(p, 8, pAddRef);
        Marshal.WriteIntPtr(p, 16, pRelease);
        Marshal.WriteIntPtr(p, 24, pHasOne);
        Marshal.WriteIntPtr(p, 32, pHasAtLeastOne);
        var o = new Objekt();
        for (int i = 0; i + 1 < paare.Length; i += 2) {
            int v = (int)paare[i];
            var d = (Delegate)paare[i + 1];
            if (v < UzcV.BASIS || v + 8 > groesse) throw new ArgumentException("Versatz");
            o.Halter.Add(d);
            Marshal.WriteIntPtr(p, v, Marshal.GetFunctionPointerForDelegate(d));
        }
        lock (sperre) objekte[p] = o;
        return p;
    }

    // Vor der Rückgabe an CEF (Regel 3 der C-Schnittstelle): eine Referenz dazu.
    public static IntPtr Geben(IntPtr p) {
        AddRef(p);
        return p;
    }

    static void AddRef(IntPtr self) {
        lock (sperre) {
            Objekt o;
            if (objekte.TryGetValue(self, out o)) o.Refs++;
        }
    }

    static int Release(IntPtr self) {
        lock (sperre) {
            Objekt o;
            if (!objekte.TryGetValue(self, out o)) return 0;
            o.Refs--;
            if (o.Refs > 0) return 0;
            objekte.Remove(self);
        }
        Marshal.FreeHGlobal(self);
        return 1;
    }

    static int HasOne(IntPtr self) {
        lock (sperre) {
            Objekt o;
            return objekte.TryGetValue(self, out o) && o.Refs == 1 ? 1 : 0;
        }
    }

    static int HasAtLeastOne(IntPtr self) {
        lock (sperre) {
            Objekt o;
            return objekte.TryGetValue(self, out o) && o.Refs >= 1 ? 1 : 0;
        }
    }

    public static int Refs(IntPtr self) {
        lock (sperre) {
            Objekt o;
            return objekte.TryGetValue(self, out o) ? o.Refs : -1;
        }
    }
}

// --- Was der Bootstrap mitgibt (cef_version_info_t) ----------------------------------------------------------

public sealed class UzcStart {
    public IntPtr Instance, Sandbox, VersionInfo;
    public int CmdShow;
    public string LibcefPfad = "", VersionVoll = "", InstallerText = "";
    public int InstallerCode;
    public bool Gebuendelt;

    // „instance=…;sandbox=…;version=…;show=…“ vom Start-Stummel (16 Hex-Ziffern je Wert).
    public static UzcStart Lesen(string arg) {
        var s = new UzcStart();
        if (arg == null) return null;
        foreach (string teil in arg.Split(';')) {
            int eq = teil.IndexOf('=');
            if (eq <= 0) return null;
            string k = teil.Substring(0, eq), v = teil.Substring(eq + 1);
            ulong n;
            if (v.Length != 16 || !ulong.TryParse(v, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out n)) return null;
            switch (k) {
                case "instance": s.Instance = new IntPtr((long)n); break;
                case "sandbox": s.Sandbox = new IntPtr((long)n); break;
                case "version": s.VersionInfo = new IntPtr((long)n); break;
                case "show": s.CmdShow = (int)n; break;
                default: return null;
            }
        }
        if (s.VersionInfo != IntPtr.Zero) {
            long groesse = Marshal.ReadIntPtr(s.VersionInfo).ToInt64();
            if (groesse >= UzcV.VERSION_INFO_MIT_INSTALLER) {
                IntPtr pfad = Marshal.ReadIntPtr(s.VersionInfo, UzcV.VERSION_INFO_LIBCEF_PATH);
                s.LibcefPfad = pfad == IntPtr.Zero ? "" : (Marshal.PtrToStringUni(pfad) ?? "");
                s.Gebuendelt = Marshal.ReadInt32(s.VersionInfo, UzcV.VERSION_INFO_LIBCEF_IS_BUNDLED) != 0;
                s.VersionVoll = UzcApi.Utf8(Marshal.ReadIntPtr(s.VersionInfo, UzcV.VERSION_INFO_LIBCEF_VERSION_FULL), 256);
                s.InstallerCode = Marshal.ReadInt32(s.VersionInfo, UzcV.VERSION_INFO_INSTALLER_ERROR_CODE);
                s.InstallerText = UzcApi.Utf8(Marshal.ReadIntPtr(s.VersionInfo, UzcV.VERSION_INFO_INSTALLER_ERROR_MESSAGE), 2000);
            }
        }
        return s;
    }
}

// --- Vordergrund: die unsichtbare Spotify-Sitzung nimmt Uzai den Fokus nicht ------------------------------

public static class UzcVorn {
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("kernel32.dll")] static extern uint GetCurrentProcessId();

    static IntPtr vorher = IntPtr.Zero;

    static bool Eigen(IntPtr h) {
        uint pid;
        return h != IntPtr.Zero && GetWindowThreadProcessId(h, out pid) != 0 && pid == GetCurrentProcessId();
    }

    // Vor dem ersten eigenen Fenster: wer vorn liegt (in der Regel Uzai, das den Kern gestartet hat).
    public static void Merken() {
        IntPtr h = GetForegroundWindow();
        vorher = Eigen(h) ? IntPtr.Zero : h;
    }

    // Liegt ein Fenster dieses Prozesses vorn, bekommt das Fenster von vorher den Vordergrund zurück. Solange wir vorn
    // sind, lässt Windows das zu. true = zurückgegeben.
    public static bool Zurueck() {
        if (vorher == IntPtr.Zero || !IsWindow(vorher) || !Eigen(GetForegroundWindow())) return false;
        return SetForegroundWindow(vorher);
    }
}

// --- Der Installer im Bootstrap (RunInstaller): Laden, Update, Gesundheitsmeldung --------------------------

public static class UzcInstaller {
    const ulong CEFI = 0x43454649;

    public static UzcD.RunInstallerD Finden() {
        IntPtr exe = UzcApi.GetModuleHandleW(null);
        IntPtr f = exe == IntPtr.Zero ? IntPtr.Zero : UzcApi.GetProcAddress(exe, "RunInstaller");
        return f == IntPtr.Zero ? null : (UzcD.RunInstallerD)Marshal.GetDelegateForFunctionPointer(f, typeof(UzcD.RunInstallerD));
    }

    static byte[] Nul(string s) {
        return Encoding.UTF8.GetBytes((s ?? "") + "\0");
    }

    // Blockiert – nur in einem eigenen Faden rufen. Ergebnis: JSON-Text (fremde Daten) oder "".
    public static string Rufen(UzcD.RunInstallerD f, string befehl, string json) {
        IntPtr r = f(Nul(befehl), json == null ? null : Nul(json));
        return UzcApi.Utf8(r, 65536);
    }

    // Die eingebettete Konfiguration unserer DLL (CEF_INSTALLER_CONFIG, vom Helfer geschrieben) als JSON-Objekt.
    public static Dictionary<string, object> Konfiguration() {
        IntPtr modul = UzcApi.GetModuleHandleW("uzai-browser.dll");
        if (modul == IntPtr.Zero) return null;
        IntPtr res = UzcApi.FindResourceW(modul, "CEF_INSTALLER_CONFIG", new IntPtr(10));
        if (res == IntPtr.Zero) return null;
        uint n = UzcApi.SizeofResource(modul, res);
        IntPtr daten = UzcApi.LockResource(UzcApi.LoadResource(modul, res));
        if (daten == IntPtr.Zero || n == 0 || n > 65536) return null;
        var b = new byte[n];
        Marshal.Copy(daten, b, 0, (int)n);
        return UzbJson.Lesen(Encoding.UTF8.GetString(b).TrimStart('﻿')) as Dictionary<string, object>;
    }

    public static bool AppIdOk(string s) {
        return s != null && System.Text.RegularExpressions.Regex.IsMatch(s, "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\\z");
    }

    public static bool FassungOk(string s) {
        return s != null && (s == "" || System.Text.RegularExpressions.Regex.IsMatch(s, "^[0-9]{2,4}(\\.[0-9]{1,4}){1,2}\\z"));
    }

    public static bool AbiOk(string s) {
        return s != null && (s == "" || System.Text.RegularExpressions.Regex.IsMatch(s, "^[0-9a-f]{16}\\z"));
    }

    // Ordner nur unter %LOCALAPPDATA%\Uzai\browser\kern, ohne „..“, ohne Datenströme.
    public static bool OrdnerOk(string p) {
        if (string.IsNullOrEmpty(p) || p.Length > 400 || p.Contains("..") || p.IndexOf(':', 2) >= 0) return false;
        string wurzel = Path.Combine(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Uzai"), "browser");
        wurzel = Path.Combine(wurzel, "kern");
        string voll;
        try { voll = Path.GetFullPath(p); } catch (Exception) { return false; }
        return voll.StartsWith(wurzel + "\\", StringComparison.OrdinalIgnoreCase) || string.Equals(voll, wurzel, StringComparison.OrdinalIgnoreCase);
    }

    // WM_COPYDATA des Installers → { schritt, prozent } oder null.
    public static Dictionary<string, object> Fortschritt(IntPtr lParam) {
        if (lParam == IntPtr.Zero) return null;
        ulong art = (ulong)Marshal.ReadIntPtr(lParam).ToInt64();
        int n = Marshal.ReadInt32(lParam, 8);
        IntPtr daten = Marshal.ReadIntPtr(lParam, 16);
        if (art != CEFI || daten == IntPtr.Zero || n <= 0 || n > 32768) return null;
        var b = new byte[n];
        Marshal.Copy(daten, b, 0, n);
        var d = UzbJson.Lesen(Encoding.UTF8.GetString(b).TrimEnd('\0')) as Dictionary<string, object>;
        if (d == null) return null;
        object schritt, done, total;
        double getan = 0, gesamt = 0;
        if (d.TryGetValue("bytes_done", out done) && done is double) getan = (double)done;
        if (d.TryGetValue("bytes_total", out total) && total is double) gesamt = (double)total;
        var o = new Dictionary<string, object>();
        o["schritt"] = d.TryGetValue("step_name", out schritt) && schritt is string ? UzbRegeln.Sauber((string)schritt, 32) : "";
        o["prozent"] = gesamt > 0 ? (int)Math.Max(0, Math.Min(100, Math.Floor(getan * 100.0 / gesamt))) : 0;
        return o;
    }
}

// --- Ein Tab -----------------------------------------------------------------------------------------------

public sealed class UzcTab {
    public int Id;
    public IntPtr Browser, Host, Hwnd, Registrierung;
    public int BrowserId;
    public int Kontext;             // Ausführungskontext der Welt „uzai“ im aktuellen Dokument (aus „hallo“)
    public bool Privat, Intern, Zu, Bereit, Laedt, Zurueck, Vor;
    public int Zoom = 100;
    public string HeimHost = "";    // Heimnetz-Name, den du selbst eingegeben hast (nur dorthin darf die Seite)
    public string Url = "about:blank", Titel = "";
    public string StartUrl = "";
    public bool StartNutzer;
    public int Blockiert, Versteckt;
    public string Cookies = "";
    public bool HalloSeitLaden;       // das Sprung-Skript hat sich im aktuellen Dokument gemeldet
    public bool HalloGemeldet, OhneWeltGemeldet, StummGemeldet, WeltGemeldet;
    public long BlockerGemeldet;
    public readonly HashSet<uint> DownloadsGesperrt = new HashSet<uint>();
}

// --- Spotify-Sitzung („Mit Spotify anmelden“, docs/BROWSER_PLAN.md 8) -------------------------------------------
// Ein eigener Kern-Prozess mit eigenem Datenordner (spotify-daten, getrennt vom Browser), der nur Spotify zeigt:
// einmal sichtbar die echte Anmeldeseite, danach unsichtbar den Webplayer. Den Zugriffsschlüssel liest der Kern aus den
// eigenen Anfragen der Seite (Kopfzeile „Authorization: Bearer …“ an pathfinder/spclient) – Uzai berechnet ihn nie
// selbst, und erneuern tut ihn die Seite. Werte nur nach festem Zeichensatz und Länge, nie ins Protokoll.

public static class UzcSpotify {
    // Hauptrahmen nur zu Spotify und zu den Anmeldediensten, die Spotifys Anmeldeseite selbst anbietet (nur https).
    static readonly string[] ANMELDUNG = { "accounts.google.com", "appleid.apple.com", "www.facebook.com", "m.facebook.com" };
    public const int MAX_SCHLUESSEL = 2048;
    public const int MAX_FASSUNG = 40;
    public const string START = "https://open.spotify.com/";

    public static bool HostErlaubt(string h) {
        if (h == null || h.Length == 0 || h.Length > 253) return false;
        if (h == "spotify.com" || h.EndsWith(".spotify.com", StringComparison.Ordinal)) return true;
        return Array.IndexOf(ANMELDUNG, h) >= 0;
    }

    public static bool Erlaubt(string url) {
        if (url == null || url.Length > UzbRegeln.MAX_URL || !url.StartsWith("https://", StringComparison.Ordinal)) return false;
        if (UzbRegeln.UrlGrund(url, false) != "") return false;
        return HostErlaubt(UzbRegeln.Host(url));
    }

    // Anfragen, die den Schlüssel der Seite tragen: pathfinder, spclient (auch gew…-spclient), Web-API.
    public static bool TraegtSchluessel(string url) {
        if (url == null || !url.StartsWith("https://", StringComparison.Ordinal)) return false;
        string h = UzbRegeln.Host(url);
        return h == "api-partner.spotify.com" || h == "api.spotify.com" || h == "spclient.wg.spotify.com"
            || (h.EndsWith("-spclient.spotify.com", StringComparison.Ordinal) && h.Length <= 64);
    }

    // Die Seite meldet sich nie als Spotify-Connect-Gerät an und steuert nichts (sie spielt nie; Abspielen läuft über die
    // Spotify-App am PC): Anmeldung als Gerät, Zustand und Befehle der Seite gehen nicht hinaus.
    public static bool Gesperrt(string url) {
        if (!TraegtSchluessel(url)) return false;
        string p = Pfad(url);
        return p.StartsWith("/connect-state/v1/", StringComparison.Ordinal) || p.StartsWith("/track-playback/v1/", StringComparison.Ordinal);
    }

    public static string Pfad(string url) {
        int a = url.IndexOf("://", StringComparison.Ordinal);
        if (a < 0) return "";
        int b = url.IndexOf('/', a + 3);
        if (b < 0) return "/";
        int q = url.IndexOfAny(new[] { '?', '#' }, b);
        return q < 0 ? url.Substring(b) : url.Substring(b, q - b);
    }

    // „Bearer <schlüssel>“ → Schlüssel; sonst "".
    public static string Bearer(string kopf) {
        if (kopf == null || !kopf.StartsWith("Bearer ", StringComparison.Ordinal)) return "";
        string t = kopf.Substring(7);
        return Zeichen(t, 20, MAX_SCHLUESSEL) ? t : "";
    }

    public static string Schluessel(string kopf) {
        return kopf != null && Zeichen(kopf, 20, MAX_SCHLUESSEL) ? kopf : "";
    }

    // Fassung des Webplayers („1.2.73.157.gd7f98bd8“): Ziffern vorn, dann Punkte, Ziffern und kleine Buchstaben.
    public static string Fassung(string kopf) {
        if (kopf == null || kopf.Length < 3 || kopf.Length > MAX_FASSUNG || kopf[0] < '0' || kopf[0] > '9') return "";
        foreach (char c in kopf) if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || c == '.')) return "";
        return kopf;
    }

    // --- Abfragen in der Seite (Ereignis „spotify-antwort“) ----------------------------------------------------
    // Uzai fragt Spotify nicht selbst, sondern der Kern IN der angemeldeten Seite: fetch() im Kontext der Welt „uzai“
    // (Herkunft open.spotify.com, Chromiums Netz, TLS und Cookies-Regeln), mit den Kopfzeilen, die die Seite selbst
    // schickt. Uzai nennt nur Ziel-Art, Methode, Pfad und Inhalt (dieselben Regeln wie spotify_abfrage_grund in
    // src/core/browser_protokoll.gd); Host und Kopfzeilen setzt der Kern, nie Uzai.
    public const string SPCLIENT_STANDARD = "spclient.wg.spotify.com";
    public const int MAX_OFFEN = 8;

    // "" = die Abfrage darf in der Seite laufen, sonst "ziel" (Regeln in UzbSchema.SpotifyAbfrageGrund, gleich für die Leitung).
    public static string AbfrageGrund(string ziel, string methode, string pfad, string inhalt, string verbindung) {
        return UzbSchema.SpotifyAbfrageGrund(ziel, methode, pfad, inhalt, verbindung);
    }

    // Spclient-Host aus einer Anfrage der Seite (gew4-spclient.spotify.com …), sonst "".
    public static string SpclientHost(string url) {
        if (!TraegtSchluessel(url)) return "";
        string h = UzbRegeln.Host(url);
        return h == "spclient.wg.spotify.com" || h.EndsWith("-spclient.spotify.com", StringComparison.Ordinal) ? h : "";
    }

    // Feste Adresse je Ziel-Art: api-partner, der spclient der Seite (sonst spclient.wg), api.spotify.com.
    public static string Adresse(string ziel, string pfad, string spclient) {
        if (ziel == "pathfinder") return "https://api-partner.spotify.com" + UzbSchema.PATHFINDER_PFAD;
        if (ziel == "spclient") return "https://" + (SpclientHost("https://" + spclient + "/") != "" ? spclient : SPCLIENT_STANDARD) + pfad;
        return "https://api.spotify.com" + pfad;
    }

    // Kopfzeilen wie die der Seite: Schlüssel, Client-Token, Plattform und Fassung für pathfinder/spclient; die Web-API
    // bekommt nur den Schlüssel (wie bei der Seite). Werte nur aus dem Kern, nie von Uzai (bis auf die geprüfte
    // Verbindungs-Kennung von Spotify Connect).
    public static Dictionary<string, object> Kopf(string ziel, string token, string client, string fassung, bool inhalt, string verbindung) {
        var h = new Dictionary<string, object>();
        h["authorization"] = "Bearer " + token;
        h["accept"] = "application/json";
        if (ziel != "webapi") {
            h["app-platform"] = "WebPlayer";
            if (client.Length > 0) h["client-token"] = client;
            if (fassung.Length > 0) h["spotify-app-version"] = fassung;
        }
        if (inhalt) h["content-type"] = "application/json;charset=UTF-8";
        if (verbindung.Length > 0) h["x-spotify-connection-id"] = verbindung;
        return h;
    }

    // Läuft in der Seite (Welt „uzai“): fetch mit Zeitlimit, Text höchstens a.n Zeichen. Fehler werden zu {s:0, f:…}.
    public const string FUNKTION = "async function (a) {"
        + " var c = new AbortController(); var z = setTimeout(function () { c.abort(); }, a.z);"
        + " try {"
        + "  var o = { method: a.m, headers: a.h, signal: c.signal, cache: 'no-store', redirect: 'error' };"
        + "  if (a.b !== '') o.body = a.b;"
        + "  var r = await fetch(a.u, o);"
        + "  var w = parseInt(r.headers.get('retry-after') || '0', 10);"
        + "  var x = await r.text();"
        + "  var g = x.length > a.n;"
        + "  return { s: r.status, x: g ? x.slice(0, a.n) : x, g: g, f: '', w: (w > 0 && w < 86400) ? w : 0 };"
        + " } catch (e) {"
        + "  return { s: 0, x: '', g: false, f: (e && e.name === 'AbortError') ? 'zeit' : 'netz', w: 0 };"
        + " } finally { clearTimeout(z); }"
        + "}";

    // Nur A–Z, a–z, 0–9 und - _ . + / = (Base64 bzw. Base64url), Länge in Grenzen.
    public static bool Zeichen(string s, int min, int max) {
        if (s == null || s.Length < min || s.Length > max) return false;
        foreach (char c in s) {
            if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) continue;
            if (c == '-' || c == '_' || c == '.' || c == '+' || c == '/' || c == '=') continue;
            return false;
        }
        return true;
    }
}

// --- Der Kern selbst -------------------------------------------------------------------------------------------

public sealed class UzcKern {
    public const string VERSION = "2";
    public const int MAX_TABS = 12;
    const string WELT = "uzai";
    const string BINDUNG = "__uzaiMeldung";
    const string FUNKTION = "function (a) { var u = globalThis.__uzai; if (u) u.befehl(a); }";
    const int RT_MAIN_FRAME = 0;
    const int SW_HIDE = 0, SW_SHOWNA = 8;
    const uint SWP_NOACTIVATE = 0x0010, SWP_NOZORDER = 0x0004;
    const uint WS_CHILD = 0x40000000, WS_VISIBLE = 0x10000000, WS_CLIPCHILDREN = 0x02000000, WS_CLIPSIBLINGS = 0x04000000, WS_TABSTOP = 0x00010000;
    const uint GRAPHIT = 0xFF0B0B0D;
    const int LOGSEVERITY_DISABLE = 99, LOG_ITEMS_NONE = 1, STATE_DISABLED = 2, RUNTIME_STYLE_ALLOY = 2;
    const int RV_CANCEL = 0, RV_CONTINUE = 1;
    const int PERMISSION_DENY = 1, PERMISSION_ACCEPT = 0;
    const uint MEDIA_AUDIO = 1, MEDIA_VIDEO = 2;
    const uint PERM_GEOLOCATION = 1u << 8;
    const int INTERN_TAB = 999999;

    static readonly string[] GRAFIK_SOFTWARE = { "disable-gpu", "disable-gpu-compositing" };
    // Chromium ohne Google und ohne Überraschungen (nur Schalter, die Dinge ausschalten).
    static readonly string[] SCHALTER = { "disable-component-update", "disable-background-networking", "disable-domain-reliability",
        "disable-breakpad", "disable-crash-reporter", "no-pings", "disable-sync", "metrics-recording-only", "disable-default-apps",
        "no-first-run", "disable-client-side-phishing-detection", "disable-speech-api", "disable-notifications" };
    static readonly string[] SCHALTER_MIT_WERT = { "autoplay-policy", "no-user-gesture-required",
        "disable-features", "MediaRouter,OptimizationHints,Translate,DialMediaRouteProvider,InterestFeedContentSuggestions,AutofillServerCommunication,"
            + "SafeBrowsingEnhancedProtection,PrivacySandboxSettings4,TopicsAPI,FledgeAPI,AttributionReporting" };
    // Spotify-Sitzung: die unsichtbare Seite soll arbeiten wie eine sichtbare (Anfragen beim Laden, Erneuern des Schlüssels).
    static readonly string[] SCHALTER_SPOTIFY = { "disable-renderer-backgrounding", "disable-background-timer-throttling",
        "disable-backgrounding-occluded-windows" };
    // Einstellungen des Profils (Chromium-Prefs); was es nicht gibt, wird still übergangen.
    static readonly object[] PREFS = { "credentials_enable_service", false, "autofill.profile_enabled", false, "autofill.credit_card_enabled", false,
        "profile.cookie_controls_mode", 1, "profile.default_content_setting_values.notifications", 2, "webrtc.ip_handling_policy", "disable_non_proxied_udp",
        "safebrowsing.enabled", false, "alternate_error_pages.enabled", false, "search.suggest_enabled", false, "translate.enabled", false,
        "spellcheck.use_spelling_service", false, "signin.allowed", false, "net.network_prediction_options", 2, "enable_do_not_track", true };

    readonly UzbFenster f;
    readonly UzbAusgabe aus;
    readonly UzcStart start;
    readonly string profil, sprache, skript, skriptFilter;
    readonly UzbFilter filter;
    readonly bool software;
    readonly bool spotify;          // Spotify-Sitzung: eigener Datenordner, nur Spotify, Schlüssel aus den Anfragen der Seite
    readonly object spotifySperre = new object();
    string spotifyToken = "", spotifyClient = "", spotifyFassung = "";
    string spotifyGemeldet = "", spotifyClientGemeldet = "";   // zuletzt an Uzai gemeldet (nach dem Laden wieder melden)
    string spotifySpclient = "";                                 // spclient-Host, den die Seite selbst benutzt
    readonly Dictionary<string, int> spotifyErwartet = new Dictionary<string, int>(StringComparer.Ordinal);   // eigene Connect-Abfragen
    int spotifyOffen;                                            // laufende Abfragen in der Seite (nur Fenster-Faden)
    readonly HashSet<Timer> spotifyUhren = new HashSet<Timer>();  // Sicherungen je Abfrage (gehalten, bis sie fertig ist)
    readonly Dictionary<int, UzcTab> tabs = new Dictionary<int, UzcTab>();
    readonly Dictionary<int, UzcTab> nachBrowser = new Dictionary<int, UzcTab>();
    readonly Dictionary<int, Action<bool, string>> antworten = new Dictionary<int, Action<bool, string>>();
    readonly Dictionary<int, Action<bool>> fragen = new Dictionary<int, Action<bool>>();
    readonly HashSet<string> blockerAus = new HashSet<string>(StringComparer.Ordinal);
    readonly List<IntPtr> halter = new List<IntPtr>();
    IntPtr app, client, rrh, kontextPrivat;
    int aktiv, naechsterTab = 1, naechsteFrage = 1, naechsteCdp = 1;
    bool sichtbar, ende, initialisiert;
    string downloads = "", vorschau = "";
    UzcD.RunInstallerD installer;
    bool updateLaeuft;

    public UzcKern(UzbFenster f, UzbAusgabe aus, UzcStart start, string profil, string sprache, string skript, string skriptFilter, UzbFilter filter,
            bool software, bool spotify) {
        this.software = software;
        this.spotify = spotify;
        this.f = f;
        this.aus = aus;
        this.start = start;
        this.profil = profil;
        this.sprache = sprache;
        this.skript = skript;
        this.skriptFilter = skriptFilter;
        this.filter = filter;
        f.Groesse = delegate (int w, int h) {
            foreach (var t in tabs.Values) if (t.Hwnd != IntPtr.Zero) UzcApi.SetWindowPos(t.Hwnd, IntPtr.Zero, 0, 0, w, h, SWP_NOACTIVATE | SWP_NOZORDER);
        };
        f.Schliessen = Beenden;
        f.CopyData = delegate (IntPtr w, IntPtr l) {
            var p = UzcInstaller.Fortschritt(l);
            if (p != null) Kern("laedt", (string)p["schritt"], (int)p["prozent"], "", "");
            return new IntPtr(1);
        };
    }

    static Dictionary<string, object> E(string art) {
        var d = new Dictionary<string, object>();
        d["t"] = art;
        return d;
    }

    void Gesperrt(int tab, string grund) {
        var d = E("gesperrt");
        d["tab"] = tab;
        d["grund"] = grund;
        aus.Senden(d);
    }

    public void Kern(string stand, string schritt, int prozent, string fassung, string text) {
        var d = E("kern");
        d["stand"] = stand;
        d["schritt"] = schritt ?? "";
        d["prozent"] = prozent;
        d["fassung"] = fassung ?? "";
        d["text"] = text ?? "";
        aus.Senden(d);
    }

    // --- Start und Ende -------------------------------------------------------------------------------------

    // Früherer Stand: alle Uzai-Profile in daten\Default, der Schlüssel der Cookies in daten\Local State. Seit jedes
    // Profil seine eigene Wurzel hat, erreicht das niemand mehr – die alten Anmeldungen bleiben nicht liegen.
    // Nur diese beiden Namen direkt in daten; Verknüpfungen werden nicht verfolgt (Directory.Delete löscht nur den Link).
    static void AltesGemeinsamesWeg(string daten) {
        try {
            string d = Path.Combine(daten, "Default");
            if (Directory.Exists(d)) Directory.Delete(d, true);
            string ls = Path.Combine(daten, "Local State");
            if (File.Exists(ls)) File.Delete(ls);
        } catch (Exception) { }   // gesperrt (ein alter Kern läuft noch): beim nächsten Start wieder
    }

    // Alles vor cef_initialize: Fenster steht schon. false = nicht gestartet (Fehler ist gemeldet).
    public bool Initialisieren() {
        string lokal = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string wurzel = Path.Combine(Path.Combine(lokal, "Uzai"), "browser");
        string daten = Path.Combine(wurzel, spotify ? "spotify-daten" : "kern-daten");
        string profilOrdner = Path.Combine(Path.Combine(daten, "profil"), profil);
        vorschau = Path.Combine(wurzel, "vorschau");
        downloads = Path.Combine(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads"), "Uzai Browser");
        Directory.CreateDirectory(profilOrdner);
        Directory.CreateDirectory(vorschau);
        AltesGemeinsamesWeg(daten);
        installer = UzcInstaller.Finden();

        app = UzcApi.Neu(UzcV.APP_GROESSE,
            UzcV.APP_ON_BEFORE_COMMAND_LINE_PROCESSING, new UzcD.SelfPtrPtrD(BefehlszeileVorbereiten),
            UzcV.APP_GET_BROWSER_PROCESS_HANDLER, new UzcD.PtrSelfD(BrowserProzessHandler));
        browserProzess = UzcApi.Neu(UzcV.BROWSER_PROCESS_HANDLER_GROESSE,
            UzcV.BROWSER_PROCESS_HANDLER_ON_CONTEXT_INITIALIZED, new UzcD.SelfD(KontextBereit),
            UzcV.BROWSER_PROCESS_HANDLER_ON_BEFORE_CHILD_PROCESS_LAUNCH, new UzcD.SelfPtrD(VorKindprozess));
        ClientBauen();

        var args = UzcApi.Leer(UzcV.MAIN_ARGS_GROESSE);
        Marshal.WriteIntPtr(args, 0, start.Instance);
        int code = UzcApi.cef_execute_process(args, IntPtr.Zero, start.Sandbox);
        if (code >= 0) { UzcEinstieg.Grund(aus, "K14 cef_execute_process " + code.ToString(CultureInfo.InvariantCulture)); Fehler("start"); return false; }   // wären wir ein Unterprozess – sind wir nie (Stummel)

        IntPtr s = UzcApi.Leer(UzcV.SETTINGS_GROESSE);
        var puffer = new List<IntPtr>();
        Marshal.WriteInt32(s, UzcV.SETTINGS_NO_SANDBOX, 0);
        Marshal.WriteInt32(s, UzcV.SETTINGS_MULTI_THREADED_MESSAGE_LOOP, 0);
        Marshal.WriteInt32(s, UzcV.SETTINGS_EXTERNAL_MESSAGE_PUMP, 0);
        Marshal.WriteInt32(s, UzcV.SETTINGS_WINDOWLESS_RENDERING_ENABLED, 0);
        Marshal.WriteInt32(s, UzcV.SETTINGS_COMMAND_LINE_ARGS_DISABLED, 1);
        // Wurzel = Ordner des Profils. Chrome-Stil nimmt als Profil nur die Wurzel selbst oder ein direktes Kind;
        // mit der gemeinsamen Wurzel (daten) und profil\<kennung> darunter landete alles in daten\Default – alle
        // Uzai-Profile teilten sich dieselben Anmeldungen, und Abmelden (Ordner des Profils löschen) half nicht.
        UzcApi.StrFeld(s, UzcV.SETTINGS_CACHE_PATH, profilOrdner, puffer);
        UzcApi.StrFeld(s, UzcV.SETTINGS_ROOT_CACHE_PATH, profilOrdner, puffer);
        Marshal.WriteInt32(s, UzcV.SETTINGS_PERSIST_SESSION_COOKIES, 1);
        UzcApi.StrFeld(s, UzcV.SETTINGS_LOCALE, sprache, puffer);
        UzcApi.StrFeld(s, UzcV.SETTINGS_LOG_FILE, "", puffer);
        Marshal.WriteInt32(s, UzcV.SETTINGS_LOG_SEVERITY, LOGSEVERITY_DISABLE);
        Marshal.WriteInt32(s, UzcV.SETTINGS_LOG_ITEMS, LOG_ITEMS_NONE);
        Marshal.WriteInt32(s, UzcV.SETTINGS_REMOTE_DEBUGGING_PORT, 0);
        Marshal.WriteInt32(s, UzcV.SETTINGS_BACKGROUND_COLOR, unchecked((int)GRAPHIT));
        UzcApi.StrFeld(s, UzcV.SETTINGS_ACCEPT_LANGUAGE_LIST, sprache + "," + sprache.Substring(0, 2), puffer);
        if (UzcApi.cef_initialize(args, s, UzcApi.Geben(app), start.Sandbox) == 0) {
            // CEFs eigener Grund (z. B. 21 = CEF_RESULT_CODE_PROFILE_IN_USE, 31 = INVALID_SANDBOX_STATE).
            UzcEinstieg.Grund(aus, "K14 cef_initialize, CEF-Code " + UzcApi.cef_get_exit_code().ToString(CultureInfo.InvariantCulture));
            Fehler("start");
            return false;
        }
        foreach (IntPtr p in puffer) halter.Add(p);
        initialisiert = true;
        return true;
    }

    public void Schleife() {
        UzcApi.cef_run_message_loop();
        UzcApi.cef_shutdown();
    }

    public void Beenden() {
        if (ende) return;
        ende = true;
        bool offen = false;
        foreach (var t in new List<UzcTab>(tabs.Values)) {
            if (t.Host != IntPtr.Zero && !t.Zu) {
                offen = true;
                try { UzcApi.Fn<UzcD.SelfIntD>(t.Host, UzcV.BROWSER_HOST_CLOSE_BROWSER)(t.Host, 1); } catch (Exception) { }
            }
        }
        if (!offen) { Aus(); return; }
        // Spätestens nach 3 s geht der Kern, auch wenn eine Seite nicht loslässt.
        new Timer(delegate (object o) { f.Post(Aus); }, null, 3000, Timeout.Infinite);
    }

    void Aus() {
        if (initialisiert) UzcApi.cef_quit_message_loop();
        f.Ende();
    }

    void Fehler(string code) { aus.Fehler(code); }

    // --- App und Browserprozess ------------------------------------------------------------------------------

    IntPtr browserProzess;

    IntPtr BrowserProzessHandler(IntPtr self) { return UzcApi.Geben(browserProzess); }

    void BefehlszeileVorbereiten(IntPtr self, IntPtr prozessArt, IntPtr befehlszeile) {
        if (UzcApi.Text(prozessArt) != "") return;   // nur der Browserprozess
        var hat = UzcApi.Fn<UzcD.IntSelfPtrD>(befehlszeile, UzcV.COMMAND_LINE_HAS_SWITCH);
        var weg = UzcApi.Fn<UzcD.SelfPtrD>(befehlszeile, UzcV.COMMAND_LINE_REMOVE_SWITCH);
        var dazu = UzcApi.Fn<UzcD.SelfPtrD>(befehlszeile, UzcV.COMMAND_LINE_APPEND_SWITCH);
        var dazuWert = UzcApi.Fn<UzcD.SelfPtrPtrD>(befehlszeile, UzcV.COMMAND_LINE_APPEND_SWITCH_WITH_VALUE);
        var entfernt = new List<string>();
        foreach (string nie in new[] { "no-sandbox", "remote-debugging-port", "remote-debugging-pipe", "remote-allow-origins", "load-extension", "disable-web-security",
                "allow-running-insecure-content", "user-data-dir", "js-flags", "enable-logging", "single-process", "in-process-gpu", "disable-site-isolation-trials",
                "disable-gpu-sandbox", "disable-software-rasterizer" }) {
            using (var n = new UzcApi.Str(nie)) if (hat(befehlszeile, n.P) != 0) { weg(befehlszeile, n.P); entfernt.Add(nie); }
        }
        foreach (string sch in SCHALTER) using (var n = new UzcApi.Str(sch)) dazu(befehlszeile, n.P);
        // Rückfall ohne GPU: Chromium zeichnet dann in Software (SwiftShader/WARP); die Sandbox bleibt, auch für den
        // GPU-Prozess, der als Display-Compositor weiterläuft.
        if (software) foreach (string sch in GRAFIK_SOFTWARE) using (var n = new UzcApi.Str(sch)) dazu(befehlszeile, n.P);
        if (spotify) foreach (string sch in SCHALTER_SPOTIFY) using (var n = new UzcApi.Str(sch)) dazu(befehlszeile, n.P);
        // Fürs Protokoll in Uzai (ohne Pfade): welche Grafik, was entfernt wurde.
        Kern("info", "schalter", 0, "", "grafik=" + (software ? "software (" + string.Join(" ", GRAFIK_SOFTWARE) + ")" : "hardware")
            + "; entfernt: " + (entfernt.Count == 0 ? "-" : string.Join(" ", entfernt.ToArray())) + "; " + SCHALTER.Length.ToString(CultureInfo.InvariantCulture) + " Aus-Schalter"
            + (spotify ? "; Spotify-Sitzung" : ""));
        for (int i = 0; i + 1 < SCHALTER_MIT_WERT.Length; i += 2) {
            using (var n = new UzcApi.Str(SCHALTER_MIT_WERT[i]))
            using (var w = new UzcApi.Str(SCHALTER_MIT_WERT[i + 1])) dazuWert(befehlszeile, n.P, w.P);
        }
    }

    // Ein Kindprozess ohne Sandbox wäre ein Fehler im Aufbau: dann lieber gar kein Browser.
    void VorKindprozess(IntPtr self, IntPtr befehlszeile) {
        var hat = UzcApi.Fn<UzcD.IntSelfPtrD>(befehlszeile, UzcV.COMMAND_LINE_HAS_SWITCH);
        using (var n = new UzcApi.Str("no-sandbox")) {
            if (hat(befehlszeile, n.P) != 0) {
                f.Post(delegate () { Fehler("kern_sandbox"); Beenden(); });
            }
        }
        // Fürs Protokoll, je Art einmal: welcher Unterprozess startet und ob er den Pfad zu libcef bekommt (der Stummel
        // braucht --libcef-path, sonst endet er mit 201). Keine Pfade, nur Art und ja/nein.
        try {
            var wert = UzcApi.Fn<UzcD.PtrSelfPtrD>(befehlszeile, UzcV.COMMAND_LINE_GET_SWITCH_VALUE);
            string art;
            using (var t = new UzcApi.Str("type")) art = UzcApi.Frei(wert(befehlszeile, t.P));
            art = UzbRegeln.Sauber(art, 40);
            bool mitPfad;
            using (var l = new UzcApi.Str("libcef-path")) mitPfad = hat(befehlszeile, l.P) != 0;
            lock (kinderArten) {
                if (kinderArten.Count >= 12 || !kinderArten.Add(art)) return;
            }
            Kern("info", "kind", 0, "", "Unterprozess " + (art == "" ? "?" : art) + ", libcef-path " + (mitPfad ? "ja" : "nein"));
        } catch (Exception) { }
    }

    readonly HashSet<string> kinderArten = new HashSet<string>(StringComparer.Ordinal);

    void KontextBereit(IntPtr self) {
        Einstellungen(UzcApi.cef_request_context_get_global_context(), true);
        var b = E("bereit");
        b["version"] = VERSION + " cef " + UzcApi.Utf8(UzcApi.cef_version_full(), 80);   // höchstens 87 Zeichen (Schema: 96)
        aus.Senden(b);
        if (spotify) foreach (int ms in new[] { 0, 1000, 3000, 8000 }) vornUhren.Add(new Timer(delegate (object o) { f.Post(VornZurueck); }, null, ms, Timeout.Infinite));
    }

    // Spotify session: its window stays invisible and must never take the foreground from Uzai, because Uzai only
    // accepts controller input while it has focus (otherwise nothing responds after the start until Guide is pressed).
    // Chromium still activates the window when the page is created (WS_EX_NOACTIVATE does not help there), so the
    // foreground is handed back to the window that was in front before the start.
    readonly List<Timer> vornUhren = new List<Timer>();

    void VornZurueck() {
        if (!spotify || ende) return;
        if (UzcVorn.Zurueck()) Kern("info", "vorn", 0, "", "Vordergrund an das Fenster von vor dem Start zurückgegeben");
    }

    // Prefs eines Kontexts; ein Kontext aus der Bibliothek (eigene Referenz) wird danach freigegeben.
    void Einstellungen(IntPtr kontext, bool freigeben) {
        if (kontext == IntPtr.Zero) return;
        var setzen = UzcApi.Fn<UzcD.SetPrefD>(kontext, UzcV.REQUEST_CONTEXT_SET_PREFERENCE);
        for (int i = 0; i + 1 < PREFS.Length; i += 2) {
            IntPtr wert = UzcApi.cef_value_create();
            object v = PREFS[i + 1];
            if (v is bool) UzcApi.Fn<UzcD.IntSelfIntD>(wert, UzcV.VALUE_SET_BOOL)(wert, (bool)v ? 1 : 0);
            else if (v is int) UzcApi.Fn<UzcD.IntSelfIntD>(wert, UzcV.VALUE_SET_INT)(wert, (int)v);
            else using (var sv = new UzcApi.Str((string)v)) UzcApi.Fn<UzcD.IntSelfPtrD>(wert, UzcV.VALUE_SET_STRING)(wert, sv.P);
            IntPtr fehler = UzcApi.Leer(UzcV.STRING_GROESSE);
            Marshal.WriteIntPtr(fehler, 0, IntPtr.Zero);
            using (var n = new UzcApi.Str((string)PREFS[i])) setzen(kontext, n.P, wert, fehler);   // übernimmt die Referenz auf wert
            UzcApi.cef_string_utf16_clear(fehler);
            Marshal.FreeHGlobal(fehler);
        }
        if (freigeben) UzcApi.Loslassen(kontext);
    }

    // --- Client und Handler ----------------------------------------------------------------------------------

    IntPtr lifeSpan, load, display, request, permission, download, jsdialog, dialog, kontextMenue, befehle, fokus, tastatur, beobachter;

    void ClientBauen() {
        lifeSpan = UzcApi.Neu(UzcV.LIFE_SPAN_HANDLER_GROESSE,
            UzcV.LIFE_SPAN_HANDLER_ON_BEFORE_POPUP, new UzcD.BeforePopupD(VorPopup),
            UzcV.LIFE_SPAN_HANDLER_ON_AFTER_CREATED, new UzcD.SelfPtrD(NachErzeugung),
            UzcV.LIFE_SPAN_HANDLER_DO_CLOSE, new UzcD.IntSelfPtrD(DoClose),
            UzcV.LIFE_SPAN_HANDLER_ON_BEFORE_CLOSE, new UzcD.SelfPtrD(VorSchliessen));
        load = UzcApi.Neu(UzcV.LOAD_HANDLER_GROESSE,
            UzcV.LOAD_HANDLER_ON_LOADING_STATE_CHANGE, new UzcD.LoadStateD(Ladestand),
            UzcV.LOAD_HANDLER_ON_LOAD_ERROR, new UzcD.LoadErrorD(Ladefehler));
        display = UzcApi.Neu(UzcV.DISPLAY_HANDLER_GROESSE,
            UzcV.DISPLAY_HANDLER_ON_ADDRESS_CHANGE, new UzcD.SelfPtr3D(AdresseGeaendert),
            UzcV.DISPLAY_HANDLER_ON_TITLE_CHANGE, new UzcD.SelfPtrPtrD(TitelGeaendert),
            UzcV.DISPLAY_HANDLER_ON_FULLSCREEN_MODE_CHANGE, new UzcD.SelfPtrIntD(Vollbild),
            UzcV.DISPLAY_HANDLER_ON_CONSOLE_MESSAGE, new UzcD.ConsoleD(Konsole),
            UzcV.DISPLAY_HANDLER_ON_TOOLTIP, new UzcD.IntSelfPtrPtrD(Tooltip));
        request = UzcApi.Neu(UzcV.REQUEST_HANDLER_GROESSE,
            UzcV.REQUEST_HANDLER_ON_BEFORE_BROWSE, new UzcD.BeforeBrowseD(VorNavigation),
            UzcV.REQUEST_HANDLER_ON_OPEN_URLFROM_TAB, new UzcD.OpenUrlD(OeffnenAusTab),
            UzcV.REQUEST_HANDLER_GET_RESOURCE_REQUEST_HANDLER, new UzcD.GetRrhD(RessourcenHandler),
            UzcV.REQUEST_HANDLER_GET_AUTH_CREDENTIALS, new UzcD.AuthD(Anmeldung),
            UzcV.REQUEST_HANDLER_ON_CERTIFICATE_ERROR, new UzcD.CertErrD(Zertifikatsfehler),
            UzcV.REQUEST_HANDLER_ON_SELECT_CLIENT_CERTIFICATE, new UzcD.SelectCertD(ClientZertifikat),
            UzcV.REQUEST_HANDLER_ON_RENDER_PROCESS_UNRESPONSIVE, new UzcD.IntSelfPtrPtrD(RendererHaengt),
            UzcV.REQUEST_HANDLER_ON_RENDER_PROCESS_TERMINATED, new UzcD.TerminatedD(RendererWeg));
        rrh = UzcApi.Neu(UzcV.RESOURCE_REQUEST_HANDLER_GROESSE,
            UzcV.RESOURCE_REQUEST_HANDLER_ON_BEFORE_RESOURCE_LOAD, new UzcD.BeforeLoadD(VorAnfrage),
            UzcV.RESOURCE_REQUEST_HANDLER_ON_PROTOCOL_EXECUTION, new UzcD.ProtoExecD(Protokoll));
        permission = UzcApi.Neu(UzcV.PERMISSION_HANDLER_GROESSE,
            UzcV.PERMISSION_HANDLER_ON_REQUEST_MEDIA_ACCESS_PERMISSION, new UzcD.MediaPermD(Medienrecht),
            UzcV.PERMISSION_HANDLER_ON_SHOW_PERMISSION_PROMPT, new UzcD.PermPromptD(Recht));
        download = UzcApi.Neu(UzcV.DOWNLOAD_HANDLER_GROESSE,
            UzcV.DOWNLOAD_HANDLER_CAN_DOWNLOAD, new UzcD.CanDlD(DownloadErlaubt),
            UzcV.DOWNLOAD_HANDLER_ON_BEFORE_DOWNLOAD, new UzcD.BeforeDlD(VorDownload),
            UzcV.DOWNLOAD_HANDLER_ON_DOWNLOAD_UPDATED, new UzcD.DlUpdD(DownloadStand));
        jsdialog = UzcApi.Neu(UzcV.JSDIALOG_HANDLER_GROESSE,
            UzcV.JSDIALOG_HANDLER_ON_JSDIALOG, new UzcD.JsDialogD(Dialog),
            UzcV.JSDIALOG_HANDLER_ON_BEFORE_UNLOAD_DIALOG, new UzcD.UnloadD(VorVerlassen));
        dialog = UzcApi.Neu(UzcV.DIALOG_HANDLER_GROESSE, UzcV.DIALOG_HANDLER_ON_FILE_DIALOG, new UzcD.FileDialogD(Dateidialog));
        kontextMenue = UzcApi.Neu(UzcV.CONTEXT_MENU_HANDLER_GROESSE,
            UzcV.CONTEXT_MENU_HANDLER_ON_BEFORE_CONTEXT_MENU, new UzcD.SelfPtr4D(VorKontextmenue),
            UzcV.CONTEXT_MENU_HANDLER_RUN_CONTEXT_MENU, new UzcD.IntSelfPtr5D(Kontextmenue));
        befehle = UzcApi.Neu(UzcV.COMMAND_HANDLER_GROESSE,
            UzcV.COMMAND_HANDLER_ON_CHROME_COMMAND, new UzcD.ChromeCmdD(ChromeBefehl),
            UzcV.COMMAND_HANDLER_IS_CHROME_APP_MENU_ITEM_VISIBLE, new UzcD.IntSelfPtrIntD(NieSichtbar),
            UzcV.COMMAND_HANDLER_IS_CHROME_PAGE_ACTION_ICON_VISIBLE, new UzcD.IntSelfIntD(NieSichtbar2),
            UzcV.COMMAND_HANDLER_IS_CHROME_TOOLBAR_BUTTON_VISIBLE, new UzcD.IntSelfIntD(NieSichtbar2));
        fokus = UzcApi.Neu(UzcV.FOCUS_HANDLER_GROESSE, UzcV.FOCUS_HANDLER_ON_SET_FOCUS, new UzcD.IntSelfPtrIntD(FokusSetzen));
        tastatur = UzcApi.Neu(UzcV.KEYBOARD_HANDLER_GROESSE, UzcV.KEYBOARD_HANDLER_ON_PRE_KEY_EVENT, new UzcD.PreKeyD(Taste));
        beobachter = UzcApi.Neu(UzcV.DEV_TOOLS_MESSAGE_OBSERVER_GROESSE,
            UzcV.DEV_TOOLS_MESSAGE_OBSERVER_ON_DEV_TOOLS_METHOD_RESULT, new UzcD.DtResultD(CdpErgebnis),
            UzcV.DEV_TOOLS_MESSAGE_OBSERVER_ON_DEV_TOOLS_EVENT, new UzcD.DtEventD(CdpEreignis));
        client = UzcApi.Neu(UzcV.CLIENT_GROESSE,
            UzcV.CLIENT_GET_COMMAND_HANDLER, new UzcD.PtrSelfD(delegate (IntPtr s) { return UzcApi.Geben(befehle); }),
            UzcV.CLIENT_GET_CONTEXT_MENU_HANDLER, new UzcD.PtrSelfD(delegate (IntPtr s) { return UzcApi.Geben(kontextMenue); }),
            UzcV.CLIENT_GET_DIALOG_HANDLER, new UzcD.PtrSelfD(delegate (IntPtr s) { return UzcApi.Geben(dialog); }),
            UzcV.CLIENT_GET_DISPLAY_HANDLER, new UzcD.PtrSelfD(delegate (IntPtr s) { return UzcApi.Geben(display); }),
            UzcV.CLIENT_GET_DOWNLOAD_HANDLER, new UzcD.PtrSelfD(delegate (IntPtr s) { return UzcApi.Geben(download); }),
            UzcV.CLIENT_GET_FOCUS_HANDLER, new UzcD.PtrSelfD(delegate (IntPtr s) { return UzcApi.Geben(fokus); }),
            UzcV.CLIENT_GET_PERMISSION_HANDLER, new UzcD.PtrSelfD(delegate (IntPtr s) { return UzcApi.Geben(permission); }),
            UzcV.CLIENT_GET_JSDIALOG_HANDLER, new UzcD.PtrSelfD(delegate (IntPtr s) { return UzcApi.Geben(jsdialog); }),
            UzcV.CLIENT_GET_KEYBOARD_HANDLER, new UzcD.PtrSelfD(delegate (IntPtr s) { return UzcApi.Geben(tastatur); }),
            UzcV.CLIENT_GET_LIFE_SPAN_HANDLER, new UzcD.PtrSelfD(delegate (IntPtr s) { return UzcApi.Geben(lifeSpan); }),
            UzcV.CLIENT_GET_LOAD_HANDLER, new UzcD.PtrSelfD(delegate (IntPtr s) { return UzcApi.Geben(load); }),
            UzcV.CLIENT_GET_REQUEST_HANDLER, new UzcD.PtrSelfD(delegate (IntPtr s) { return UzcApi.Geben(request); }));
    }

    UzcTab TabVon(IntPtr browser) {
        if (browser == IntPtr.Zero) return null;
        int id = UzcApi.Fn<UzcD.IntSelfD>(browser, UzcV.BROWSER_GET_IDENTIFIER)(browser);
        UzcTab t;
        lock (nachBrowser) return nachBrowser.TryGetValue(id, out t) ? t : null;
    }

    // --- Befehle von Uzai (geprüft), auf dem Faden des Fensters ----------------------------------------------

    UzcTab Tab(Dictionary<string, object> b) {
        UzcTab t;
        return tabs.TryGetValue((int)b["tab"], out t) && t.Host != IntPtr.Zero && !t.Zu && !t.Intern ? t : null;
    }

    public void Befehl(Dictionary<string, object> b) {
        if (ende) return;
        string art = (string)b["t"];
        if (art == "ende") { Beenden(); return; }
        if (!initialisiert) return;
        if (art == "fenster") { f.Lage((int)b["x"], (int)b["y"], (int)b["w"], (int)b["h"]); return; }
        if (art == "zeigen") { Zeigen((bool)b["an"]); return; }
        if (art == "tab-neu") { TabNeu((string)b["url"], (bool)b["privat"], (bool)b["vorn"], (bool)b["nutzer"], false); return; }
        if (art == "antwort") {
            Action<bool> a;
            if (fragen.TryGetValue((int)b["frage"], out a)) { fragen.Remove((int)b["frage"]); a((bool)b["ja"]); }
            return;
        }
        if (art == "blocker-liste") {
            lock (blockerAus) { blockerAus.Clear(); foreach (object h in (List<object>)b["hosts"]) blockerAus.Add(((string)h).ToLowerInvariant()); }
            return;
        }
        if (art == "kern") { KernBefehl((string)b["aktion"]); return; }
        if (art == "spotify-abfrage") { SpotifyAbfrage(b); return; }
        UzcTab t = Tab(b);
        if (t == null) return;
        switch (art) {
            case "tab-zu": TabZu(t); break;
            case "tab-wahl": Waehlen(t); break;
            case "laden": Laden(t, (string)b["url"], (bool)b["nutzer"]); break;
            case "zurueck": if (UzcApi.Fn<UzcD.IntSelfD>(t.Browser, UzcV.BROWSER_CAN_GO_BACK)(t.Browser) != 0) UzcApi.Fn<UzcD.SelfD>(t.Browser, UzcV.BROWSER_GO_BACK)(t.Browser); break;
            case "vor": if (UzcApi.Fn<UzcD.IntSelfD>(t.Browser, UzcV.BROWSER_CAN_GO_FORWARD)(t.Browser) != 0) UzcApi.Fn<UzcD.SelfD>(t.Browser, UzcV.BROWSER_GO_FORWARD)(t.Browser); break;
            case "neu": UzcApi.Fn<UzcD.SelfD>(t.Browser, UzcV.BROWSER_RELOAD)(t.Browser); break;
            case "stopp": UzcApi.Fn<UzcD.SelfD>(t.Browser, UzcV.BROWSER_STOP_LOAD)(t.Browser); break;
            case "zoom":
                t.Zoom = (int)b["prozent"];
                UzcApi.Fn<UzcD.SelfDoubleD>(t.Host, UzcV.BROWSER_HOST_SET_ZOOM_LEVEL)(t.Host, Math.Log(t.Zoom / 100.0) / Math.Log(1.2));
                Skript(t, Arg("zoom"));
                Status(t);
                break;
            case "rollen": { var a = Arg("rollen"); a["vx"] = b["vx"]; a["vy"] = b["vy"]; Skript(t, a); break; }
            case "karte": Skript(t, Arg("karte")); break;
            case "fokus": { var a = Arg("fokus"); a["id"] = b["id"]; Skript(t, a); break; }
            case "aktivieren": { var a = Arg("aktivieren"); a["id"] = b["id"]; a["neu"] = b["neu"]; Skript(t, a, true); break; }
            case "link": { var a = Arg("link"); a["id"] = b["id"]; Skript(t, a, true); break; }
            case "feld": { var a = Arg("feld"); a["id"] = b["id"]; Skript(t, a, true); break; }
            case "text": Tippen(t, (string)b["text"]); break;
            case "taste": Taste(t, (string)b["taste"]); break;
            case "klick": Klick(t, (int)b["x"], (int)b["y"]); break;
            case "zeiger": Maus(t, "mouseMoved", (int)b["x"], (int)b["y"], 0); break;
            case "rad": Maus(t, "mouseWheel", (int)b["x"], (int)b["y"], (int)b["dy"]); break;
            case "video": { var a = Arg("video"); a["aktion"] = b["aktion"]; Skript(t, a, true); break; }
            case "vorschau": Vorschau(t); break;
            case "lesen": Skript(t, Arg("lesen")); break;
            case "gliederung": Skript(t, Arg("gliederung")); break;
            case "springe": { var a = Arg("springe"); a["id"] = b["id"]; Skript(t, a); break; }
            case "wahl": { var a = Arg("wahl"); a["id"] = b["id"]; Skript(t, a, true); break; }
            case "wahl-setzen": { var a = Arg("wahl-setzen"); a["id"] = b["id"]; a["index"] = b["index"]; Skript(t, a, true); break; }
            case "feld-weiter": { var a = Arg("feld-weiter"); a["id"] = b["id"]; a["richtung"] = b["richtung"]; Skript(t, a); break; }
            case "suche": { var a = Arg("suche"); a["text"] = b["text"]; Skript(t, a); break; }
            case "suche-weiter": { var a = Arg("suche-weiter"); a["richtung"] = b["richtung"]; Skript(t, a); break; }
            case "blocker": {
                string h = UzbRegeln.Host(t.Url);
                lock (blockerAus) { if ((bool)b["an"]) blockerAus.Remove(h); else if (h != "") blockerAus.Add(h); }
                UzcApi.Fn<UzcD.SelfD>(t.Browser, UzcV.BROWSER_RELOAD)(t.Browser);
                break;
            }
        }
    }

    static Dictionary<string, object> Arg(string art) {
        var d = new Dictionary<string, object>();
        d["t"] = art;
        return d;
    }

    void Zeigen(bool an) {
        sichtbar = an;
        f.Zeigen(an);
        UzcTab t;
        if (tabs.TryGetValue(aktiv, out t) && t.Hwnd != IntPtr.Zero) UzcApi.ShowWindow(t.Hwnd, an ? SW_SHOWNA : SW_HIDE);
    }

    // --- Tabs ---------------------------------------------------------------------------------------------------

    void TabNeu(string url, bool privat, bool vorn, bool nutzer, bool intern) {
        if (spotify) {
            // Nur Spotify, nur ein Tab, nie privat: eine zweite Seite lädt in den einen Tab.
            if (intern || !UzcSpotify.Erlaubt(url)) { Gesperrt(0, "nur_spotify"); return; }
            foreach (var x in tabs.Values) if (!x.Intern && !x.Zu) { Laden(x, url, false); return; }
            privat = false;
            nutzer = false;
        }
        int sichtbare = 0;
        foreach (var x in tabs.Values) if (!x.Intern) sichtbare++;
        if (!intern && sichtbare >= MAX_TABS) { Fehler("tabs"); return; }
        var t = new UzcTab();
        t.Id = intern ? INTERN_TAB : naechsterTab++;
        t.Privat = privat;
        t.Intern = intern;
        t.StartUrl = url;
        t.StartNutzer = nutzer;
        if (nutzer) {
            string h = UzbRegeln.Host(url);
            t.HeimHost = UzbRegeln.IstHeimnetz(h) && !UzbRegeln.IstLokal(h) ? h : "";
        }
        tabs[t.Id] = t;
        IntPtr wi = UzcApi.Leer(UzcV.WINDOW_INFO_GROESSE);
        var puffer = new List<IntPtr>();
        Marshal.WriteInt32(wi, UzcV.WINDOW_INFO_EX_STYLE, 0);
        UzcApi.StrFeld(wi, UzcV.WINDOW_INFO_WINDOW_NAME, "", puffer);
        Marshal.WriteInt32(wi, UzcV.WINDOW_INFO_STYLE, unchecked((int)(WS_CHILD | WS_CLIPCHILDREN | WS_CLIPSIBLINGS | WS_TABSTOP | (intern ? 0 : WS_VISIBLE))));
        Marshal.WriteInt32(wi, UzcV.WINDOW_INFO_BOUNDS, 0);
        Marshal.WriteInt32(wi, UzcV.WINDOW_INFO_BOUNDS + 4, 0);
        Marshal.WriteInt32(wi, UzcV.WINDOW_INFO_BOUNDS + 8, Math.Max(1, f.Breite));
        Marshal.WriteInt32(wi, UzcV.WINDOW_INFO_BOUNDS + 12, Math.Max(1, f.Hoehe));
        Marshal.WriteIntPtr(wi, UzcV.WINDOW_INFO_PARENT_WINDOW, f.Hwnd);
        Marshal.WriteInt32(wi, UzcV.WINDOW_INFO_RUNTIME_STYLE, RUNTIME_STYLE_ALLOY);
        IntPtr bs = UzcApi.Leer(UzcV.BROWSER_SETTINGS_GROESSE);
        Marshal.WriteInt32(bs, UzcV.BROWSER_SETTINGS_JAVASCRIPT_CLOSE_WINDOWS, STATE_DISABLED);
        Marshal.WriteInt32(bs, UzcV.BROWSER_SETTINGS_JAVASCRIPT_ACCESS_CLIPBOARD, STATE_DISABLED);
        Marshal.WriteInt32(bs, UzcV.BROWSER_SETTINGS_JAVASCRIPT_DOM_PASTE, STATE_DISABLED);
        Marshal.WriteInt32(bs, UzcV.BROWSER_SETTINGS_BACKGROUND_COLOR, unchecked((int)GRAPHIT));
        Marshal.WriteInt32(bs, UzcV.BROWSER_SETTINGS_CHROME_STATUS_BUBBLE, STATE_DISABLED);
        Marshal.WriteInt32(bs, UzcV.BROWSER_SETTINGS_CHROME_ZOOM_BUBBLE, STATE_DISABLED);
        IntPtr kontext = privat ? KontextPrivat() : IntPtr.Zero;
        if (kontext != IntPtr.Zero) UzcApi.Halten(kontext);   // der Aufruf verbraucht eine Referenz
        IntPtr browser;
        using (var leer = new UzcApi.Str("about:blank")) {
            browser = UzcApi.cef_browser_host_create_browser_sync(wi, UzcApi.Geben(client), leer.P, bs, IntPtr.Zero, kontext);
        }
        foreach (IntPtr p in puffer) Marshal.FreeHGlobal(p);
        Marshal.FreeHGlobal(wi);
        Marshal.FreeHGlobal(bs);
        if (browser == IntPtr.Zero) { tabs.Remove(t.Id); Fehler("start"); return; }
        t.Browser = browser;
        t.BrowserId = UzcApi.Fn<UzcD.IntSelfD>(browser, UzcV.BROWSER_GET_IDENTIFIER)(browser);
        lock (nachBrowser) nachBrowser[t.BrowserId] = t;
        t.Host = UzcApi.Fn<UzcD.PtrSelfD>(browser, UzcV.BROWSER_GET_HOST)(browser);
        t.Hwnd = UzcApi.Fn<UzcD.PtrSelfD>(t.Host, UzcV.BROWSER_HOST_GET_WINDOW_HANDLE)(t.Host);
        UzcApi.ShowWindow(t.Hwnd, SW_HIDE);
        UzcApi.Fn<UzcD.SelfIntD>(t.Host, UzcV.BROWSER_HOST_WAS_HIDDEN)(t.Host, spotify ? 0 : 1);
        if (spotify) UzcApi.Fn<UzcD.SelfIntD>(t.Host, UzcV.BROWSER_HOST_SET_AUDIO_MUTED)(t.Host, 1);   // die Seite spielt nie
        t.Registrierung = UzcApi.Fn<UzcD.PtrSelfPtrD>(t.Host, UzcV.BROWSER_HOST_ADD_DEV_TOOLS_MESSAGE_OBSERVER)(t.Host, UzcApi.Geben(beobachter));
        WeltEinrichten(t);
        if (!intern && (vorn || aktiv == 0)) Waehlen(t);
        if (!intern) Status(t);
    }

    IntPtr KontextPrivat() {
        if (kontextPrivat != IntPtr.Zero) return kontextPrivat;
        IntPtr s = UzcApi.Leer(UzcV.REQUEST_CONTEXT_SETTINGS_GROESSE);
        var puffer = new List<IntPtr>();
        UzcApi.StrFeld(s, UzcV.REQUEST_CONTEXT_SETTINGS_CACHE_PATH, "", puffer);   // leer = nur im Speicher, nichts auf der Platte
        Marshal.WriteInt32(s, UzcV.REQUEST_CONTEXT_SETTINGS_PERSIST_SESSION_COOKIES, 0);
        UzcApi.StrFeld(s, UzcV.REQUEST_CONTEXT_SETTINGS_ACCEPT_LANGUAGE_LIST, sprache, puffer);
        kontextPrivat = UzcApi.cef_request_context_create_context(s, IntPtr.Zero);
        foreach (IntPtr p in puffer) Marshal.FreeHGlobal(p);
        Marshal.FreeHGlobal(s);
        Einstellungen(kontextPrivat, false);
        return kontextPrivat;
    }

    void TabZu(UzcTab t) {
        if (t.Zu) return;
        t.Zu = true;
        tabs.Remove(t.Id);
        if (aktiv == t.Id) aktiv = 0;
        try { UzcApi.Fn<UzcD.SelfIntD>(t.Host, UzcV.BROWSER_HOST_CLOSE_BROWSER)(t.Host, 1); } catch (Exception) { }
        try { File.Delete(Path.Combine(vorschau, "tab-" + t.Id.ToString(CultureInfo.InvariantCulture) + ".jpg")); } catch (Exception) { }
        if (!t.Intern) {
            var d = E("tab-zu");
            d["tab"] = t.Id;
            aus.Senden(d);
        }
    }

    void Waehlen(UzcTab t) {
        UzcTab alt;
        if (aktiv != t.Id && tabs.TryGetValue(aktiv, out alt) && alt.Hwnd != IntPtr.Zero) {
            UzcApi.ShowWindow(alt.Hwnd, SW_HIDE);
            UzcApi.Fn<UzcD.SelfIntD>(alt.Host, UzcV.BROWSER_HOST_WAS_HIDDEN)(alt.Host, 1);
        }
        aktiv = t.Id;
        UzcApi.SetWindowPos(t.Hwnd, IntPtr.Zero, 0, 0, Math.Max(1, f.Breite), Math.Max(1, f.Hoehe), SWP_NOACTIVATE | SWP_NOZORDER);
        UzcApi.Fn<UzcD.SelfIntD>(t.Host, UzcV.BROWSER_HOST_WAS_HIDDEN)(t.Host, sichtbar || spotify ? 0 : 1);
        UzcApi.ShowWindow(t.Hwnd, sichtbar ? SW_SHOWNA : SW_HIDE);
        Skript(t, Arg("karte"));
        Status(t);
    }

    void Laden(UzcTab t, string url, bool nutzer) {
        if (nutzer) {
            string h = UzbRegeln.Host(url);
            t.HeimHost = UzbRegeln.IstHeimnetz(h) && !UzbRegeln.IstLokal(h) ? h : "";
        }
        string g = UzbRegeln.UrlGrund(url, HeimErlaubt(t, url));
        if (g == "" && spotify && !UzcSpotify.Erlaubt(url)) g = "nur_spotify";
        if (g != "") { Gesperrt(t.Id, g); return; }
        if (spotify) lock (spotifySperre) spotifyGemeldet = "";   // nach dem (Neu-)Laden den ersten Schlüssel immer melden
        if (!t.Bereit) { t.StartUrl = url; t.StartNutzer = nutzer; return; }
        IntPtr frame = UzcApi.Fn<UzcD.PtrSelfD>(t.Browser, UzcV.BROWSER_GET_MAIN_FRAME)(t.Browser);
        if (frame == IntPtr.Zero) return;
        using (var u = new UzcApi.Str(url)) UzcApi.Fn<UzcD.SelfPtrD>(frame, UzcV.FRAME_LOAD_URL)(frame, u.P);
        UzcApi.Loslassen(frame);
    }

    static bool HeimErlaubt(UzcTab t, string url) {
        return t.HeimHost != "" && UzbRegeln.Host(url) == t.HeimHost;
    }

    static bool HeimSeite(UzcTab t) {
        return t.HeimHost != "" && UzbRegeln.Host(t.Url) == t.HeimHost;
    }

    void Status(UzcTab t) {
        if (t.Zu || t.Intern || t.Browser == IntPtr.Zero) return;
        var d = E("tab");
        d["tab"] = t.Id;
        d["url"] = t.Url == "about:blank" || UzbRegeln.UrlGrund(t.Url, true) == "" ? t.Url : "about:blank";
        d["titel"] = UzbRegeln.Sauber(t.Titel, 300);
        d["laedt"] = t.Laedt;
        d["zurueck"] = t.Zurueck;
        d["vor"] = t.Vor;
        d["zoom"] = t.Zoom;
        d["privat"] = t.Privat;
        d["aktiv"] = t.Id == aktiv;
        aus.Senden(d);
    }

    // --- Lebenslauf eines Browsers --------------------------------------------------------------------------

    int VorPopup(IntPtr self, IntPtr browser, IntPtr frame, int popupId, IntPtr zielUrl, IntPtr zielName, int disposition, int geste, IntPtr features,
            IntPtr windowInfo, IntPtr clientAus, IntPtr settings, IntPtr extraInfo, IntPtr keinJs) {
        var t = TabVon(browser);
        if (t == null || t.Intern) return 1;
        if (geste == 0) { Gesperrt(t.Id, "popup"); return 1; }
        string u = UzcApi.Text(zielUrl);
        string g = UzbRegeln.UrlGrund(u, HeimErlaubt(t, u));
        if (g != "") { Gesperrt(t.Id, g); return 1; }
        if (spotify) {
            // Spotify-Sitzung: kein zweites Fenster – eine erlaubte Seite (Anmeldedienst) lädt im selben Tab.
            if (!UzcSpotify.Erlaubt(u)) { Gesperrt(t.Id, "nur_spotify"); return 1; }
            f.Post(delegate () { if (!ende && !t.Zu) Laden(t, u, false); });
            return 1;
        }
        bool privat = t.Privat;
        f.Post(delegate () { if (!ende) TabNeu(u, privat, true, false, false); });
        return 1;   // nie ein eigenes Fenster – immer ein Tab ohne Verbindung zur öffnenden Seite
    }

    void NachErzeugung(IntPtr self, IntPtr browser) { }

    int DoClose(IntPtr self, IntPtr browser) { return 0; }

    void VorSchliessen(IntPtr self, IntPtr browser) {
        var t = TabVon(browser);
        if (t == null) return;
        lock (nachBrowser) nachBrowser.Remove(t.BrowserId);
        t.Zu = true;
        tabs.Remove(t.Id);
        if (t.Registrierung != IntPtr.Zero) UzcApi.Loslassen(t.Registrierung);
        if (t.Host != IntPtr.Zero) UzcApi.Loslassen(t.Host);
        if (t.Browser != IntPtr.Zero) UzcApi.Loslassen(t.Browser);
        t.Registrierung = t.Host = t.Browser = IntPtr.Zero;
        if (ende && tabs.Count == 0) Aus();
    }

    void Ladestand(IntPtr self, IntPtr browser, int laedt, int zurueck, int vor) {
        var t = TabVon(browser);
        if (t == null) return;
        if (laedt != 0 && !t.Laedt) t.HalloSeitLaden = false;
        t.Laedt = laedt != 0;
        t.Zurueck = zurueck != 0;
        t.Vor = vor != 0;
        Status(t);
        if (laedt == 0) BlockerMelden(t, true);
        if (laedt == 0 && spotify) VornZurueck();
        // Seite fertig, aber das Sprung-Skript blieb stumm: ohne Karte gibt es kein Springen, kein A (einmal je Tab).
        if (laedt == 0 && !t.HalloSeitLaden && !t.StummGemeldet && t.Url != "about:blank" && !t.Intern) {
            t.StummGemeldet = true;
            Kern("info", "stumm", 0, "", "Tab " + t.Id.ToString(CultureInfo.InvariantCulture) + ": Seite geladen, Sprung-Skript meldet sich nicht");
        }
    }

    void Ladefehler(IntPtr self, IntPtr browser, IntPtr frame, int code, IntPtr text, IntPtr url) {
        var t = TabVon(browser);
        if (t == null || code == -3) return;   // ERR_ABORTED: wir selbst haben abgebrochen
        var d = E("meldung");
        d["tab"] = t.Id;
        d["herkunft"] = UzbRegeln.Host(UzcApi.Text(url));
        d["text"] = "Seite nicht erreichbar (" + code.ToString(CultureInfo.InvariantCulture) + ")";
        aus.Senden(d);
    }

    void AdresseGeaendert(IntPtr self, IntPtr browser, IntPtr frame, IntPtr url) {
        var t = TabVon(browser);
        if (t == null || frame == IntPtr.Zero || UzcApi.Fn<UzcD.IntSelfD>(frame, UzcV.FRAME_IS_MAIN)(frame) == 0) return;
        t.Url = UzcApi.Text(url);
        Status(t);
    }

    void TitelGeaendert(IntPtr self, IntPtr browser, IntPtr titel) {
        var t = TabVon(browser);
        if (t == null) return;
        t.Titel = UzcApi.Text(titel);
        Status(t);
    }

    void Vollbild(IntPtr self, IntPtr browser, int an) {
        var t = TabVon(browser);
        if (t == null || t.Intern) return;
        var d = E("vollbild");
        d["tab"] = t.Id;
        d["an"] = an != 0;
        aus.Senden(d);
    }

    int Konsole(IntPtr self, IntPtr browser, int level, IntPtr msg, IntPtr src, int line) { return 1; }   // nichts protokollieren

    int Tooltip(IntPtr self, IntPtr browser, IntPtr text) { return 1; }   // keine Windows-Tooltips über Uzai

    // --- Anfragen: Adressen, Rahmen, Unteranfragen, Blocker ------------------------------------------------------

    int VorNavigation(IntPtr self, IntPtr browser, IntPtr frame, IntPtr anfrage, int geste, int weiterleitung) {
        var t = TabVon(browser);
        if (t == null) return 1;
        string u = UzcApi.Frei(UzcApi.Fn<UzcD.PtrSelfD>(anfrage, UzcV.REQUEST_GET_URL)(anfrage));
        string low = u.ToLowerInvariant();
        if (t.Intern) return low == "chrome://sandbox/" || low == "about:blank" ? 0 : 1;
        bool haupt = UzcApi.Fn<UzcD.IntSelfD>(frame, UzcV.FRAME_IS_MAIN)(frame) != 0;
        if (low == "about:blank") return 0;
        if (!haupt && (low.StartsWith("about:", StringComparison.Ordinal) || low.StartsWith("data:", StringComparison.Ordinal) || low.StartsWith("blob:", StringComparison.Ordinal))) return 0;
        string g = UzbRegeln.UrlGrund(u, HeimErlaubt(t, u));
        if (g == "heimnetz" && !haupt && HeimSeite(t)) g = "";
        if (g == "" && spotify && haupt && !UzcSpotify.Erlaubt(u)) g = "nur_spotify";
        if (g != "") { if (haupt) Gesperrt(t.Id, g); return 1; }
        // Verlässt der Tab die selbst eingegebene Heimnetz-Adresse (Link, Lesezeichen, Weiterleitung), gilt die Freigabe
        // nicht mehr: Die nächste Seite dürfte sonst den Router ansprechen (Anfragen mit dessen Cookies).
        if (haupt && t.HeimHost != "" && UzbRegeln.Host(u) != t.HeimHost) t.HeimHost = "";
        return 0;
    }

    int OeffnenAusTab(IntPtr self, IntPtr browser, IntPtr frame, IntPtr url, int disposition, int geste) {
        var t = TabVon(browser);
        if (t == null || geste == 0) return 1;
        string u = UzcApi.Text(url);
        if (UzbRegeln.UrlGrund(u, HeimErlaubt(t, u)) != "") return 1;
        if (spotify) {
            if (UzcSpotify.Erlaubt(u)) f.Post(delegate () { if (!ende && !t.Zu) Laden(t, u, false); });
            return 1;
        }
        bool privat = t.Privat;
        f.Post(delegate () { if (!ende) TabNeu(u, privat, false, false, false); });
        return 1;
    }

    IntPtr RessourcenHandler(IntPtr self, IntPtr browser, IntPtr frame, IntPtr anfrage, int navigation, int dl, IntPtr initiator, IntPtr standard) {
        return UzcApi.Geben(rrh);
    }

    // Läuft auf dem IO-Faden: nur lesen, zählen, entscheiden.
    int VorAnfrage(IntPtr self, IntPtr browser, IntPtr frame, IntPtr anfrage, IntPtr callback) {
        var t = TabVon(browser);
        if (t == null) return RV_CANCEL;
        string u = UzcApi.Frei(UzcApi.Fn<UzcD.PtrSelfD>(anfrage, UzcV.REQUEST_GET_URL)(anfrage));
        if (t.Intern) return u.StartsWith("chrome://", StringComparison.OrdinalIgnoreCase) ? RV_CONTINUE : RV_CANCEL;
        if (UzbRegeln.ZielGesperrt(u, HeimErlaubt(t, u) || HeimSeite(t))) return RV_CANCEL;
        if (spotify) {
            if (UzcSpotify.Gesperrt(u) && !SpotifyErwartet(u)) return RV_CANCEL;
            if (UzcSpotify.TraegtSchluessel(u)) SpotifyBeobachten(anfrage, u);
            return RV_CONTINUE;   // ohne Blocker: Spotify bekommt, was die Seite braucht
        }
        if (filter == null) return RV_CONTINUE;
        int art = UzcApi.Fn<UzcD.IntSelfD>(anfrage, UzcV.REQUEST_GET_RESOURCE_TYPE)(anfrage);
        if (art == RT_MAIN_FRAME) return RV_CONTINUE;
        string seite = UzbRegeln.Host(t.Url);
        lock (blockerAus) { if (seite != "" && blockerAus.Contains(seite)) return RV_CONTINUE; }
        if (!filter.Gesperrt(u, art, seite)) return RV_CONTINUE;
        Interlocked.Increment(ref t.Blockiert);
        BlockerMelden(t, false);
        return RV_CANCEL;
    }

    // Spotify-Sitzung (IO-Faden): Schlüssel, Client-Token und Fassung aus den Kopfzeilen der Seite; gemeldet nur, wenn
    // sich der Schlüssel ändert (die Seite erneuert ihn selbst). Nie ins Protokoll, nur über die Leitung zu Uzai.
    void SpotifyBeobachten(IntPtr anfrage, string u) {
        string tok = UzcSpotify.Bearer(Kopf(anfrage, "Authorization"));
        if (tok == "") return;
        string ct = UzcSpotify.Schluessel(Kopf(anfrage, "client-token"));
        string fa = UzcSpotify.Fassung(Kopf(anfrage, "spotify-app-version"));
        string sp = UzcSpotify.SpclientHost(u);
        lock (spotifySperre) {
            if (sp != "") spotifySpclient = sp;
            spotifyToken = tok;
            if (ct != "") spotifyClient = ct;
            if (fa != "") spotifyFassung = fa;
            if (tok == spotifyGemeldet && spotifyClient == spotifyClientGemeldet) return;
            spotifyGemeldet = tok;
            spotifyClientGemeldet = spotifyClient;
            var d = E("spotify");
            d["token"] = tok;
            d["client"] = spotifyClient;
            d["version"] = spotifyFassung;
            aus.Senden(d);
        }
    }

    // Eigene Abfrage an Spotify Connect (Uzais verstecktes Gerät, Befehle): diese eine Adresse darf hinaus, solange
    // die Abfrage läuft – die Seite selbst wird nie ein Connect-Gerät (IO-Faden: nur nachsehen).
    bool SpotifyErwartet(string u) {
        lock (spotifySperre) return spotifyErwartet.ContainsKey(u);
    }

    void SpotifyErwarten(string u, bool an) {
        lock (spotifySperre) {
            int n;
            spotifyErwartet.TryGetValue(u, out n);
            n += an ? 1 : -1;
            if (n > 0) spotifyErwartet[u] = n; else spotifyErwartet.Remove(u);
        }
    }

    UzcTab SpotifyTab() {
        foreach (var t in tabs.Values)
            if (!t.Intern && !t.Zu && t.Host != IntPtr.Zero && t.Kontext != 0 && UzbRegeln.Host(t.Url) == "open.spotify.com") return t;
        return null;
    }

    // Befehl „spotify-abfrage“ (Fenster-Faden): geprüft, dann per fetch IN der Seite (UzcSpotify.FUNKTION). Die Antwort
    // kommt als „spotify-antwort“ – genau eine je Kennung, auch bei Fehlern (grund) und spätestens nach zeit + 5 s.
    void SpotifyAbfrage(Dictionary<string, object> b) {
        int id = (int)b["id"];
        string ziel = (string)b["ziel"], methode = (string)b["methode"], pfad = (string)b["pfad"], inhalt = (string)b["inhalt"], verbindung = (string)b["verbindung"];
        int zeit = (int)b["zeit"];
        if (!spotify || UzcSpotify.AbfrageGrund(ziel, methode, pfad, inhalt, verbindung) != "") { SpotifyAntwort(id, 0, "ziel", "", false, 0); return; }
        UzcTab t = SpotifyTab();
        if (t == null) { SpotifyAntwort(id, 0, "welt", "", false, 0); return; }
        string tok, ct, fa, sp;
        lock (spotifySperre) { tok = spotifyToken; ct = spotifyClient; fa = spotifyFassung; sp = spotifySpclient; }
        if (tok == "") { SpotifyAntwort(id, 0, "schluessel", "", false, 0); return; }
        if (spotifyOffen >= UzcSpotify.MAX_OFFEN) { SpotifyAntwort(id, 0, "voll", "", false, 0); return; }
        string url = UzcSpotify.Adresse(ziel, pfad, sp);
        var a = new Dictionary<string, object>();
        a["u"] = url;
        a["m"] = methode;
        a["b"] = inhalt;
        a["h"] = UzcSpotify.Kopf(ziel, tok, ct, fa, inhalt.Length > 0, verbindung);
        a["n"] = UzbSchema.MAX_ANTWORT;
        a["z"] = zeit;
        bool erwartet = UzcSpotify.Gesperrt(url);
        if (erwartet) SpotifyErwarten(url, true);
        spotifyOffen++;
        bool[] fertig = { false };
        Timer[] uhr = { null };
        Action<bool, string> ende = delegate (bool ok, string ergebnis) {
            f.Post(delegate () {
                if (fertig[0]) return;
                fertig[0] = true;
                spotifyOffen--;
                if (erwartet) SpotifyErwarten(url, false);
                if (uhr[0] != null) { lock (spotifyUhren) spotifyUhren.Remove(uhr[0]); uhr[0].Dispose(); }
                SpotifyErgebnis(id, ok, ergebnis);
            });
        };
        var p = new Dictionary<string, object>();
        p["functionDeclaration"] = UzcSpotify.FUNKTION;
        p["executionContextId"] = t.Kontext;
        var wert = new Dictionary<string, object>();
        wert["value"] = a;
        p["arguments"] = new List<object> { wert };
        p["returnByValue"] = true;
        p["awaitPromise"] = true;
        p["silent"] = true;
        if (Cdp(t, "Runtime.callFunctionOn", p, ende) == 0) { ende(false, ""); return; }
        // Sicherung: kommt aus der Seite nichts (Renderer hängt), trotzdem genau eine Antwort.
        uhr[0] = new Timer(delegate (object o) { ende(false, "zeit"); }, null, Timeout.Infinite, Timeout.Infinite);
        lock (spotifyUhren) spotifyUhren.Add(uhr[0]);
        uhr[0].Change(zeit + 5000, Timeout.Infinite);
    }

    // Ergebnis von Runtime.callFunctionOn → „spotify-antwort“. Fremde Daten: nur die festen Felder, Typen geprüft.
    void SpotifyErgebnis(int id, bool ok, string ergebnis) {
        if (!ok) { SpotifyAntwort(id, 0, ergebnis == "zeit" ? "zeit" : "welt", "", false, 0); return; }
        var d = UzbJson.Lesen(ergebnis) as Dictionary<string, object>;
        object r, v, s, x, g, fe, w;
        var res = d != null && !d.ContainsKey("exceptionDetails") && d.TryGetValue("result", out r) ? r as Dictionary<string, object> : null;
        var val = res != null && res.TryGetValue("value", out v) ? v as Dictionary<string, object> : null;
        if (val == null || !val.TryGetValue("s", out s) || !(s is double) || !val.TryGetValue("x", out x) || !(x is string)) {
            SpotifyAntwort(id, 0, "welt", "", false, 0);
            return;
        }
        int code = (double)s >= 0 && (double)s <= 999 ? (int)(double)s : 0;
        string text = (string)x;
        bool gekuerzt = val.TryGetValue("g", out g) && g is bool && (bool)g;
        if (text.Length > UzbSchema.MAX_ANTWORT) { text = text.Substring(0, UzbSchema.MAX_ANTWORT); gekuerzt = true; }
        string grund = "";
        if (code == 0) grund = val.TryGetValue("f", out fe) && fe is string && (string)fe == "zeit" ? "zeit" : "netz";
        int warte = val.TryGetValue("w", out w) && w is double && (double)w > 0 && (double)w <= 86400 ? (int)(double)w : 0;
        SpotifyAntwort(id, code, grund, text, gekuerzt, warte);
    }

    // Nie ins Protokoll (der Text kann persönliche Daten tragen), nur über die Leitung. Passt die Zeile nicht, geht
    // dieselbe Antwort ohne Text (grund „gross“).
    void SpotifyAntwort(int id, int code, string grund, string text, bool gekuerzt, int warte) {
        var d = E("spotify-antwort");
        d["id"] = id;
        d["code"] = code;
        d["grund"] = grund;
        d["text"] = text;
        d["gekuerzt"] = gekuerzt;
        d["warte"] = warte;
        if (aus.Senden(d) || text.Length == 0) return;
        d["text"] = "";
        d["gekuerzt"] = true;
        d["grund"] = "gross";
        aus.Senden(d);
    }

    static string Kopf(IntPtr anfrage, string name) {
        using (var n = new UzcApi.Str(name)) return UzcApi.Frei(UzcApi.Fn<UzcD.PtrSelfPtrD>(anfrage, UzcV.REQUEST_GET_HEADER_BY_NAME)(anfrage, n.P));
    }

    void BlockerMelden(UzcTab t, bool jetzt) {
        if (t.Intern) return;
        long tick = Environment.TickCount;
        if (!jetzt && tick - Interlocked.Read(ref t.BlockerGemeldet) < 700) return;
        Interlocked.Exchange(ref t.BlockerGemeldet, tick);
        var d = E("blocker");
        d["tab"] = t.Id;
        d["anzahl"] = Math.Min(1000000, t.Blockiert);
        d["versteckt"] = Math.Min(1000000, t.Versteckt);
        d["cookies"] = t.Cookies;
        aus.Senden(d);
    }

    void Protokoll(IntPtr self, IntPtr browser, IntPtr frame, IntPtr anfrage, IntPtr erlauben) {
        Marshal.WriteInt32(erlauben, 0);
        var t = TabVon(browser);
        if (t != null && !t.Intern) f.Post(delegate () { Gesperrt(t.Id, "app"); });
    }

    int Anmeldung(IntPtr self, IntPtr browser, IntPtr origin, int proxy, IntPtr host, int port, IntPtr realm, IntPtr schema, IntPtr callback) {
        var t = TabVon(browser);
        if (t != null && !t.Intern) Gesperrt(t.Id, "anmeldedialog");
        return 0;   // abbrechen
    }

    int Zertifikatsfehler(IntPtr self, IntPtr browser, int fehler, IntPtr url, IntPtr ssl, IntPtr callback) {
        var t = TabVon(browser);
        if (t != null && !t.Intern) Gesperrt(t.Id, "zertifikat");
        return 0;   // kein „trotzdem fortfahren“
    }

    int ClientZertifikat(IntPtr self, IntPtr browser, int proxy, IntPtr host, int port, UIntPtr anzahl, IntPtr zertifikate, IntPtr callback) {
        UzcApi.Fn<UzcD.SelfPtrD>(callback, UzcV.SELECT_CLIENT_CERTIFICATE_CALLBACK_SELECT)(callback, IntPtr.Zero);   // ohne Zertifikat weiter
        return 1;
    }

    int RendererHaengt(IntPtr self, IntPtr browser, IntPtr callback) {
        var t = TabVon(browser);
        if (t != null && !t.Intern) { var d = E("absturz"); d["tab"] = t.Id; aus.Senden(d); }
        return 0;   // Chromium wartet wie gewohnt
    }

    void RendererWeg(IntPtr self, IntPtr browser, int status, int code, IntPtr text) {
        var t = TabVon(browser);
        if (t != null && !t.Intern) { var d = E("absturz"); d["tab"] = t.Id; aus.Senden(d); }
    }

    // --- Rechte, Dialoge, Downloads --------------------------------------------------------------------------

    int Medienrecht(IntPtr self, IntPtr browser, IntPtr frame, IntPtr herkunft, uint gewuenscht, IntPtr callback) {
        var t = TabVon(browser);
        var weiter = UzcApi.Fn<UzcD.SelfUIntD>(callback, UzcV.MEDIA_ACCESS_CALLBACK_CONTINUE);
        var abbrechen = UzcApi.Fn<UzcD.SelfD>(callback, UzcV.MEDIA_ACCESS_CALLBACK_CANCEL);
        if (t == null || t.Intern || spotify || (gewuenscht & ~(MEDIA_AUDIO | MEDIA_VIDEO)) != 0) { abbrechen(callback); return 1; }   // Bildschirm teilen: nie
        UzcApi.Halten(callback);
        string art = (gewuenscht & MEDIA_VIDEO) != 0 ? "kamera" : "mikrofon";
        uint erlaubt = gewuenscht;
        Fragen(art, UzbRegeln.Host(UzcApi.Text(herkunft)), "", delegate (bool ja) {
            try { if (ja) weiter(callback, erlaubt); else abbrechen(callback); } finally { UzcApi.Loslassen(callback); }
        });
        return 1;
    }

    int Recht(IntPtr self, IntPtr browser, ulong id, IntPtr herkunft, uint gewuenscht, IntPtr callback) {
        var t = TabVon(browser);
        var weiter = UzcApi.Fn<UzcD.SelfIntD>(callback, UzcV.PERMISSION_PROMPT_CALLBACK_CONTINUE);
        if (t == null || t.Intern || spotify || gewuenscht != PERM_GEOLOCATION) { weiter(callback, PERMISSION_DENY); return 1; }
        UzcApi.Halten(callback);
        Fragen("standort", UzbRegeln.Host(UzcApi.Text(herkunft)), "", delegate (bool ja) {
            try { weiter(callback, ja ? PERMISSION_ACCEPT : PERMISSION_DENY); } finally { UzcApi.Loslassen(callback); }
        });
        return 1;
    }

    int Dialog(IntPtr self, IntPtr browser, IntPtr herkunft, int art, IntPtr text, IntPtr vorgabe, IntPtr callback, IntPtr unterdruecken) {
        var t = TabVon(browser);
        var weiter = UzcApi.Fn<UzcD.JsContD>(callback, UzcV.JSDIALOG_CALLBACK_CONTINUE);
        if (t == null || t.Intern) { weiter(callback, 0, IntPtr.Zero); return 1; }
        string wo = UzbRegeln.Host(UzcApi.Text(herkunft));
        string was = UzbRegeln.Sauber(UzcApi.Text(text), 300);
        if (art == 0) {   // alert
            var d = E("meldung");
            d["tab"] = t.Id;
            d["herkunft"] = wo;
            d["text"] = was;
            aus.Senden(d);
            weiter(callback, 1, IntPtr.Zero);
            return 1;
        }
        if (art == 1) {   // confirm
            UzcApi.Halten(callback);
            Fragen("bestaetigen", wo, was, delegate (bool ja) {
                try { weiter(callback, ja ? 1 : 0, IntPtr.Zero); } finally { UzcApi.Loslassen(callback); }
            });
            return 1;
        }
        weiter(callback, 0, IntPtr.Zero);   // prompt: Texte tippt man in Uzais Tastatur
        return 1;
    }

    int VorVerlassen(IntPtr self, IntPtr browser, IntPtr text, int neu, IntPtr callback) {
        UzcApi.Fn<UzcD.JsContD>(callback, UzcV.JSDIALOG_CALLBACK_CONTINUE)(callback, 1, IntPtr.Zero);
        return 1;
    }

    int Dateidialog(IntPtr self, IntPtr browser, int modus, IntPtr titel, IntPtr vorgabe, IntPtr f1, IntPtr f2, IntPtr f3, IntPtr callback) {
        UzcApi.Fn<UzcD.SelfD>(callback, UzcV.FILE_DIALOG_CALLBACK_CANCEL)(callback);
        return 1;
    }

    void VorKontextmenue(IntPtr self, IntPtr browser, IntPtr frame, IntPtr parameter, IntPtr modell) {
        UzcApi.Fn<UzcD.IntSelfD>(modell, UzcV.MENU_MODEL_CLEAR)(modell);
    }

    int Kontextmenue(IntPtr self, IntPtr browser, IntPtr frame, IntPtr parameter, IntPtr modell, IntPtr callback) {
        UzcApi.Fn<UzcD.SelfD>(callback, UzcV.RUN_CONTEXT_MENU_CALLBACK_CANCEL)(callback);
        return 1;
    }

    int ChromeBefehl(IntPtr self, IntPtr browser, int befehl, int disposition) { return 1; }   // alle Chrome-Befehle (DevTools, Drucken …) gesperrt
    int NieSichtbar(IntPtr self, IntPtr browser, int befehl) { return 0; }
    int NieSichtbar2(IntPtr self, int art) { return 0; }
    int FokusSetzen(IntPtr self, IntPtr browser, int quelle) { return 1; }   // die Seite holt sich nie den Fokus von Uzai
    int Taste(IntPtr self, IntPtr browser, IntPtr ereignis, IntPtr os, IntPtr kuerzel) { return 1; }   // echte Tastatur: nicht an die Seite

    int DownloadErlaubt(IntPtr self, IntPtr browser, IntPtr url, IntPtr methode) {
        var t = TabVon(browser);
        string u = UzcApi.Text(url);
        if (t == null || t.Intern || spotify || UzbRegeln.UrlGrund(u, HeimErlaubt(t, u)) != "") return 0;
        return 1;
    }

    int VorDownload(IntPtr self, IntPtr browser, IntPtr eintrag, IntPtr vorschlag, IntPtr callback) {
        var t = TabVon(browser);
        var weiter = UzcApi.Fn<UzcD.DlContD>(callback, UzcV.BEFORE_DOWNLOAD_CALLBACK_CONTINUE);
        string name = UzbRegeln.Dateiname(UzcApi.Text(vorschlag));
        uint id = UzcApi.Fn<UzcD.UIntSelfD>(eintrag, UzcV.DOWNLOAD_ITEM_GET_ID)(eintrag);
        string u = UzcApi.Frei(UzcApi.Fn<UzcD.PtrSelfD>(eintrag, UzcV.DOWNLOAD_ITEM_GET_URL)(eintrag));
        var d = E("download");
        d["name"] = UzbRegeln.Sauber(name, 120);
        if (t == null || t.Intern || !UzbRegeln.DownloadOk(name) || UzbRegeln.UrlGrund(u, HeimErlaubt(t, u)) != "") {
            if (t != null) lock (t.DownloadsGesperrt) t.DownloadsGesperrt.Add(id);
            d["stand"] = "gesperrt";
            aus.Senden(d);
            weiter(callback, IntPtr.Zero, 0);   // startet nur, um gleich im nächsten Stand abgebrochen zu werden
            return 1;
        }
        string ziel;
        try {
            Directory.CreateDirectory(downloads);
            ziel = Path.Combine(downloads, name);
            int n = 2;
            string stamm = Path.GetFileNameWithoutExtension(name), ext = Path.GetExtension(name);
            while (File.Exists(ziel) && n < 1000) ziel = Path.Combine(downloads, stamm + " (" + (n++).ToString(CultureInfo.InvariantCulture) + ")" + ext);
        } catch (Exception) {
            d["stand"] = "fehler";
            aus.Senden(d);
            lock (t.DownloadsGesperrt) t.DownloadsGesperrt.Add(id);
            weiter(callback, IntPtr.Zero, 0);
            return 1;
        }
        d["stand"] = "laeuft";
        aus.Senden(d);
        using (var z = new UzcApi.Str(ziel)) weiter(callback, z.P, 0);
        return 1;
    }

    void DownloadStand(IntPtr self, IntPtr browser, IntPtr eintrag, IntPtr callback) {
        var t = TabVon(browser);
        if (t == null) return;
        uint id = UzcApi.Fn<UzcD.UIntSelfD>(eintrag, UzcV.DOWNLOAD_ITEM_GET_ID)(eintrag);
        bool gesperrt;
        lock (t.DownloadsGesperrt) gesperrt = t.DownloadsGesperrt.Contains(id);
        if (gesperrt) {
            UzcApi.Fn<UzcD.SelfD>(callback, UzcV.DOWNLOAD_ITEM_CALLBACK_CANCEL)(callback);
            string pfad = UzcApi.Frei(UzcApi.Fn<UzcD.PtrSelfD>(eintrag, UzcV.DOWNLOAD_ITEM_GET_FULL_PATH)(eintrag));
            if (pfad != "") try { File.Delete(pfad); } catch (Exception) { }
            return;
        }
        if (UzcApi.Fn<UzcD.IntSelfD>(eintrag, UzcV.DOWNLOAD_ITEM_IS_IN_PROGRESS)(eintrag) != 0) return;
        string name = Path.GetFileName(UzcApi.Frei(UzcApi.Fn<UzcD.PtrSelfD>(eintrag, UzcV.DOWNLOAD_ITEM_GET_FULL_PATH)(eintrag)));
        var d = E("download");
        d["name"] = UzbRegeln.Sauber(name, 120);
        d["stand"] = UzcApi.Fn<UzcD.IntSelfD>(eintrag, UzcV.DOWNLOAD_ITEM_IS_COMPLETE)(eintrag) != 0 ? "fertig" : "fehler";
        aus.Senden(d);
    }

    void Fragen(string art, string herkunft, string text, Action<bool> antwort) {
        int id = naechsteFrage++;
        Timer uhr = null;
        bool fertig = false;
        Action<bool> einmal = delegate (bool ja) {
            if (fertig) return;
            fertig = true;
            fragen.Remove(id);
            if (uhr != null) uhr.Dispose();
            antwort(ja);
        };
        fragen[id] = einmal;
        var d = E("frage");
        d["frage"] = id;
        d["art"] = art;
        d["herkunft"] = UzbRegeln.Sauber(herkunft, 253);
        d["text"] = text;
        if (!aus.Senden(d)) { einmal(false); return; }
        uhr = new Timer(delegate (object s) { f.Post(delegate () { einmal(false); }); }, null, 60000, Timeout.Infinite);
    }

    // --- DevTools-Protokoll ohne Anschluss: Welt, Bindung, Eingaben, Vorschau ------------------------------------

    int Cdp(UzcTab t, string methode, Dictionary<string, object> p, Action<bool, string> weiter) {
        if (t.Zu || t.Host == IntPtr.Zero) return 0;
        int id = naechsteCdp++;
        var m = new Dictionary<string, object>();
        m["id"] = id;
        m["method"] = methode;
        m["params"] = p ?? new Dictionary<string, object>();
        byte[] b = Encoding.UTF8.GetBytes(UzbJson.Schreiben(m));
        if (weiter != null) lock (antworten) antworten[id] = weiter;
        IntPtr puffer = Marshal.AllocHGlobal(b.Length);
        Marshal.Copy(b, 0, puffer, b.Length);
        try {
            if (UzcApi.Fn<UzcD.SendDtD>(t.Host, UzcV.BROWSER_HOST_SEND_DEV_TOOLS_MESSAGE)(t.Host, puffer, new UIntPtr((uint)b.Length)) == 0) {
                lock (antworten) antworten.Remove(id);
                return 0;
            }
        } finally {
            Marshal.FreeHGlobal(puffer);
        }
        return id;
    }

    // Fürs Protokoll in Uzai: wie die Einrichtung der Welt „uzai“ ausging (je Tab einmal; nur ok/Fehler, keine Inhalte).
    Action<bool, string> Schritt(UzcTab t, string name, List<string> stand) {
        return delegate (bool ok, string ergebnis) {
            lock (stand) {
                stand.Add(name + (ok ? " ok" : " FEHLER " + UzbRegeln.Sauber(ergebnis, 80)));
                if (stand.Count == 5 && !t.WeltGemeldet) {
                    t.WeltGemeldet = true;
                    Kern("info", "welt", 0, "", "Tab " + t.Id.ToString(CultureInfo.InvariantCulture) + " Welt: " + string.Join(", ", stand.ToArray()));
                }
            }
        };
    }

    void WeltEinrichten(UzcTab t) {
        var stand = new List<string>();
        Cdp(t, "Page.enable", null, Schritt(t, "Page", stand));
        Cdp(t, "Runtime.enable", null, Schritt(t, "Runtime", stand));
        var bind = new Dictionary<string, object>();
        bind["name"] = BINDUNG;
        bind["executionContextName"] = WELT;
        Cdp(t, "Runtime.addBinding", bind, Schritt(t, "Bindung", stand));
        var fokusEmu = new Dictionary<string, object>();
        fokusEmu["enabled"] = true;
        Cdp(t, "Emulation.setFocusEmulationEnabled", fokusEmu, null);
        var sk = new Dictionary<string, object>();
        sk["source"] = skript;
        sk["worldName"] = WELT;
        sk["runImmediately"] = true;
        Cdp(t, "Page.addScriptToEvaluateOnNewDocument", sk, Schritt(t, "Sprung-Skript", stand));
        var sf = new Dictionary<string, object>();
        sf["source"] = skriptFilter;
        sf["worldName"] = WELT;
        sf["runImmediately"] = true;
        var filterSchritt = Schritt(t, "Filter-Skript", stand);
        Cdp(t, "Page.addScriptToEvaluateOnNewDocument", sf, delegate (bool ok, string ergebnis) {
            filterSchritt(ok, ergebnis);
            f.Post(delegate () {
                t.Bereit = true;
                if (t.StartUrl != "") { string u = t.StartUrl; t.StartUrl = ""; if (t.Intern) LadenIntern(t, u); else Laden(t, u, t.StartNutzer); }
            });
        });
    }

    void LadenIntern(UzcTab t, string url) {
        IntPtr frame = UzcApi.Fn<UzcD.PtrSelfD>(t.Browser, UzcV.BROWSER_GET_MAIN_FRAME)(t.Browser);
        if (frame == IntPtr.Zero) return;
        using (var u = new UzcApi.Str(url)) UzcApi.Fn<UzcD.SelfPtrD>(frame, UzcV.FRAME_LOAD_URL)(frame, u.P);
        UzcApi.Loslassen(frame);
    }

    void CdpErgebnis(IntPtr self, IntPtr browser, int id, int ok, IntPtr daten, UIntPtr groesse) {
        Action<bool, string> weiter;
        lock (antworten) { if (!antworten.TryGetValue(id, out weiter)) return; antworten.Remove(id); }
        long n = (long)groesse.ToUInt64();
        string text = "";
        if (daten != IntPtr.Zero && n > 0 && n <= 16 * 1024 * 1024) {
            var b = new byte[n];
            Marshal.Copy(daten, b, 0, (int)n);
            text = Encoding.UTF8.GetString(b);
        }
        weiter(ok != 0, text);
    }

    void CdpEreignis(IntPtr self, IntPtr browser, IntPtr methode, IntPtr daten, UIntPtr groesse) {
        if (UzcApi.Text(methode) != "Runtime.bindingCalled") return;
        var t = TabVon(browser);
        long n = (long)groesse.ToUInt64();
        if (t == null || daten == IntPtr.Zero || n <= 0 || n > UzbSchema.MAX_EREIGNIS + 4096) return;
        var b = new byte[n];
        Marshal.Copy(daten, b, 0, (int)n);
        string json = Encoding.UTF8.GetString(b);
        f.Post(delegate () { Meldung(t, json); });
    }

    // Meldung des Sprung-Skripts: fremde Daten.
    void Meldung(UzcTab t, string json) {
        if (t.Zu) return;
        var p = UzbJson.Lesen(json) as Dictionary<string, object>;
        if (p == null) return;
        object name, payload, ctx;
        if (!p.TryGetValue("name", out name) || !(name is string) || (string)name != BINDUNG) return;
        if (!p.TryGetValue("payload", out payload) || !(payload is string) || ((string)payload).Length > UzbSchema.MAX_EREIGNIS) return;
        int kontext = 0;
        if (p.TryGetValue("executionContextId", out ctx) && ctx is double) kontext = (int)(double)ctx;
        var m = UzbSchema.Skript(UzbJson.Lesen((string)payload));
        if (m == null) return;
        string art = (string)m["t"];
        if (art == "hallo") {
            if (!t.HalloGemeldet) {
                t.HalloGemeldet = true;
                Kern("info", "hallo", 0, "", "Tab " + t.Id.ToString(CultureInfo.InvariantCulture) + ": Sprung-Skript meldet sich (Kontext " + kontext.ToString(CultureInfo.InvariantCulture) + ")");
            }
            t.HalloSeitLaden = true;
            t.Kontext = kontext;
            t.Blockiert = 0;
            t.Versteckt = 0;
            t.Cookies = "";
            FilterSchicken(t);
            return;
        }
        if (kontext != t.Kontext) return;
        if (t.Intern) {
            if (art == "lesen") {
                var abs = (List<object>)m["absaetze"];
                var sb = new StringBuilder();
                foreach (object a in abs) { if (sb.Length > 0) sb.Append('\n'); sb.Append((string)a); }
                Kern("diagnose", "sandbox", 100, UzcApi.Utf8(UzcApi.cef_version_full(), 60), UzbRegeln.Sauber(sb.ToString(), 3000));
                TabZu(t);
            }
            return;
        }
        if (art == "klick") { if (t.Id == aktiv) Klick(t, (int)m["x"], (int)m["y"]); return; }
        if (art == "zeiger") { if (t.Id == aktiv) Maus(t, "mouseMoved", (int)m["x"], (int)m["y"], 0); return; }
        if (art == "oeffnen") {
            string u = (string)m["url"];
            string g = UzbRegeln.UrlGrund(u, HeimErlaubt(t, u));
            if (g != "") Gesperrt(t.Id, g); else TabNeu(u, t.Privat, false, false, false);
            return;
        }
        if (art == "blocker") {
            t.Versteckt = (int)m["versteckt"];
            t.Cookies = (string)m["cookies"];
            m["anzahl"] = Math.Min(1000000, t.Blockiert);
        }
        m["tab"] = t.Id;
        aus.Senden(m);
    }

    // Kosmetik und Cookie-Regel für die Seite an das Skript (als Werte).
    void FilterSchicken(UzcTab t) {
        string seite = UzbRegeln.Host(t.Url);
        bool an;
        lock (blockerAus) an = seite == "" || !blockerAus.Contains(seite);
        var a = Arg("filter");
        a["an"] = an && !t.Intern;
        var sel = new List<object>();
        if (an && filter != null && !t.Intern) foreach (string s in filter.Kosmetik(seite)) sel.Add(s);
        a["selektoren"] = sel;
        Skript(t, a);
    }

    // geste: nur bei Befehlen, die direkt auf einen Tastendruck folgen (aktivieren, Link, Feld, Video, Auswahl). Ein
    // userGesture des DevTools-Aufrufs zählt in Chromium als echte Nutzer-Aktivierung für den ganzen Rahmen – auch
    // für das Skript der Seite. Bei Filter, Karte, Zoom, Rollen … hätte jede Seite sonst gleich nach dem Laden
    // Pop-ups öffnen (vorn, als neuer Tab) und in die Zwischenablage schreiben dürfen.
    void Skript(UzcTab t, Dictionary<string, object> arg, bool geste = false) {
        if (t.Zu) return;
        if (t.Kontext == 0) {
            // Ohne Welt (das Sprung-Skript hat sich nicht gemeldet) gehen Befehle ins Leere: einmal je Tab melden.
            if (!t.OhneWeltGemeldet) {
                t.OhneWeltGemeldet = true;
                object a;
                Kern("info", "ohne-welt", 0, "", "Tab " + t.Id.ToString(CultureInfo.InvariantCulture) + ": Befehl " + (arg.TryGetValue("t", out a) ? UzbRegeln.Sauber(a as string ?? "?", 20) : "?") + " ohne Sprung-Skript (kein hallo)");
            }
            return;
        }
        var p = new Dictionary<string, object>();
        p["functionDeclaration"] = FUNKTION;
        p["executionContextId"] = t.Kontext;
        var wert = new Dictionary<string, object>();
        wert["value"] = arg;
        p["arguments"] = new List<object> { wert };
        p["returnByValue"] = true;
        if (geste) p["userGesture"] = true;
        p["silent"] = true;
        Cdp(t, "Runtime.callFunctionOn", p, null);
    }

    // CSS-Pixel der Seite (Rechtecke des Sprung-Skripts) → Punkte des Fensters: mit dem Zoom des Tabs.
    static double Punkt(UzcTab t, int css) { return Math.Round(css * t.Zoom / 100.0, 1); }

    void Klick(UzcTab t, int x, int y) {
        foreach (string typ in new[] { "mouseMoved", "mousePressed", "mouseReleased" }) {
            var p = new Dictionary<string, object>();
            p["type"] = typ;
            p["x"] = Punkt(t, x);
            p["y"] = Punkt(t, y);
            if (typ != "mouseMoved") { p["button"] = "left"; p["buttons"] = typ == "mousePressed" ? 1 : 0; p["clickCount"] = 1; }
            Cdp(t, "Input.dispatchMouseEvent", p, null);
        }
    }

    void Maus(UzcTab t, string typ, int x, int y, int dy) {
        var p = new Dictionary<string, object>();
        p["type"] = typ;
        p["x"] = Punkt(t, x);
        p["y"] = Punkt(t, y);
        if (typ == "mouseWheel") { p["deltaX"] = 0; p["deltaY"] = dy; }
        Cdp(t, "Input.dispatchMouseEvent", p, null);
    }

    void Tippen(UzcTab t, string text) {
        var p = new Dictionary<string, object>();
        p["text"] = text;
        Cdp(t, "Input.insertText", p, null);
    }

    void Taste(UzcTab t, string taste) {
        string key = "", code = "", text = "";
        int vk = 0, mod = 0;
        switch (taste) {
            case "enter": key = "Enter"; code = "Enter"; vk = 13; text = "\r"; break;
            case "tab": key = "Tab"; code = "Tab"; vk = 9; break;
            case "umschalt_tab": key = "Tab"; code = "Tab"; vk = 9; mod = 8; break;
            case "escape": key = "Escape"; code = "Escape"; vk = 27; break;
            case "backspace": key = "Backspace"; code = "Backspace"; vk = 8; break;
            case "links": key = "ArrowLeft"; code = "ArrowLeft"; vk = 37; break;
            case "rechts": key = "ArrowRight"; code = "ArrowRight"; vk = 39; break;
            case "hoch": key = "ArrowUp"; code = "ArrowUp"; vk = 38; break;
            case "runter": key = "ArrowDown"; code = "ArrowDown"; vk = 40; break;
            case "seite_hoch": key = "PageUp"; code = "PageUp"; vk = 33; break;
            case "seite_runter": key = "PageDown"; code = "PageDown"; vk = 34; break;
            case "pos1": key = "Home"; code = "Home"; vk = 36; break;
            case "ende": key = "End"; code = "End"; vk = 35; break;
            case "leer": key = " "; code = "Space"; vk = 32; text = " "; break;
            default: return;
        }
        foreach (string typ in new[] { "keyDown", "keyUp" }) {
            var p = new Dictionary<string, object>();
            p["type"] = typ == "keyDown" && text != "" ? "keyDown" : (typ == "keyDown" ? "rawKeyDown" : "keyUp");
            p["key"] = key;
            p["code"] = code;
            p["windowsVirtualKeyCode"] = vk;
            p["modifiers"] = mod;
            if (typ == "keyDown" && text != "") p["text"] = text;
            Cdp(t, "Input.dispatchKeyEvent", p, null);
        }
    }

    void Vorschau(UzcTab t) {
        var p = new Dictionary<string, object>();
        p["format"] = "jpeg";
        p["quality"] = 70;
        int id = t.Id;
        Cdp(t, "Page.captureScreenshot", p, delegate (bool ok, string ergebnis) {
            if (!ok) return;
            var d = UzbJson.Lesen(ergebnis) as Dictionary<string, object>;
            object b64;
            if (d == null || !d.TryGetValue("data", out b64) || !(b64 is string)) return;
            byte[] bild;
            try { bild = Convert.FromBase64String((string)b64); } catch (FormatException) { return; }
            if (bild.Length > 4 * 1024 * 1024) return;
            string name = "tab-" + id.ToString(CultureInfo.InvariantCulture) + ".jpg";
            string ziel = Path.Combine(vorschau, name), neu = ziel + ".neu";
            try {
                File.WriteAllBytes(neu, bild);
                if (File.Exists(ziel)) File.Delete(ziel);
                File.Move(neu, ziel);
            } catch (Exception) { return; }
            f.Post(delegate () {
                var e = E("vorschau");
                e["tab"] = id;
                e["datei"] = name;
                aus.Senden(e);
            });
        });
    }

    // --- Kern: Diagnose, Update, Gesundheit --------------------------------------------------------------------

    void KernBefehl(string aktion) {
        // Diagnose und Update gehören dem Browser. „gesund“ meldet auch die Spotify-Sitzung: Sie startet mit jedem
        // Uzai, und der Installer zählt jeden unbestätigten Start als Fehlschlag, bis er die Fassung verwirft.
        if (spotify && aktion != "gesund") return;
        if (aktion == "diagnose") {
            foreach (var x in tabs.Values) if (x.Intern) return;
            TabNeu("chrome://sandbox/", false, false, false, true);
            // Nach dem Laden den Text der Seite holen (die Fokus-Karte kommt von selbst; hier reicht der Text).
            new Timer(delegate (object o) { f.Post(delegate () {
                foreach (var x in tabs.Values) if (x.Intern) Skript(x, Arg("text"));
            }); }, null, 2500, Timeout.Infinite);
            return;
        }
        if (installer == null) { Kern("fehler", "", 0, "", "kein Installer im Bootstrap"); return; }
        if (aktion == "gesund") {
            var fn = installer;
            new Thread(delegate () {
                string r = "";
                try { r = UzcInstaller.Rufen(fn, "launch_success", null); } catch (Exception) { }
                f.Post(delegate () { Kern("stand", "gesund", 100, "", UzbRegeln.Sauber(r, 300)); });
            }) { IsBackground = true }.Start();
            return;
        }
        if (aktion == "update") {
            if (updateLaeuft) return;
            var cfg = UzcInstaller.Konfiguration();
            if (cfg == null) { Kern("fehler", "", 0, "", "keine Kern-Konfiguration"); return; }
            cfg["show_progress_ui"] = false;
            cfg["parent_window"] = f.Hwnd.ToInt64().ToString(CultureInfo.InvariantCulture);
            cfg["background_mode"] = true;
            string json = UzbJson.Schreiben(cfg);
            updateLaeuft = true;
            var fn = installer;
            new Thread(delegate () {
                string r = "";
                try { r = UzcInstaller.Rufen(fn, "update", json); } catch (Exception) { }
                f.Post(delegate () {
                    updateLaeuft = false;
                    var d = UzbJson.Lesen(r) as Dictionary<string, object>;
                    object ok, ver, out1, msg;
                    bool gut = d != null && d.TryGetValue("success", out ok) && ok is bool && (bool)ok;
                    string fassung = d != null && d.TryGetValue("installed_version", out ver) && ver is string ? (string)ver : "";
                    string outcome = d != null && d.TryGetValue("outcome", out out1) && out1 is string ? (string)out1 : "";
                    string text = d != null && d.TryGetValue("error_message", out msg) && msg is string ? (string)msg : outcome;
                    Kern(gut ? "update" : "fehler", "", 100, UzbRegeln.Sauber(fassung, 64), UzbRegeln.Sauber(text, 300));
                });
            }) { IsBackground = true }.Start();
        }
    }
}

// --- Laden des Kerns beim ersten Mal (uzai-kernladen.exe --uzai-install) ------------------------------------------

public static class UzcLaden {
    // Liest eine Konfigurationszeile von Uzai (Standardeingabe), ruft den Installer und meldet den Fortschritt.
    public static int Start(UzbFenster f, UzbAusgabe aus) {
        var installer = UzcInstaller.Finden();
        if (installer == null) { aus.Fehler("kern_installer"); return 7; }
        string zeile = Console.In.ReadLine();
        var k = zeile == null || zeile.Length > 8192 ? null : UzbJson.Lesen(zeile) as Dictionary<string, object>;
        string appid = Wert(k, "appid"), vmin = Wert(k, "vmin"), vmax = Wert(k, "vmax"), abi = Wert(k, "abi"), store = Wert(k, "store"), spiegel = Wert(k, "spiegel");
        if (!UzcInstaller.AppIdOk(appid) || !UzcInstaller.FassungOk(vmin) || vmin == "" || !UzcInstaller.FassungOk(vmax) || !UzcInstaller.AbiOk(abi)
                || !UzcInstaller.OrdnerOk(store) || (spiegel != "" && !UzcInstaller.OrdnerOk(spiegel))) {
            aus.Fehler("kern_installer");
            return 8;
        }
        var cfg = new Dictionary<string, object>();
        cfg["appid"] = appid;
        cfg["vmin"] = vmin;
        cfg["vmax"] = vmax;
        cfg["abi_hash"] = abi;
        cfg["install_path"] = store;
        if (spiegel != "") cfg["local_download_path"] = spiegel;
        cfg["cdn_urls"] = new List<object> { "https://cef-builds.spotifycdn.com/" };
        cfg["show_progress_ui"] = false;
        cfg["parent_window"] = f.Hwnd.ToInt64().ToString(CultureInfo.InvariantCulture);
        cfg["launch_health"] = "explicit";
        string json = UzbJson.Schreiben(cfg);
        f.CopyData = delegate (IntPtr w, IntPtr l) {
            var p = UzcInstaller.Fortschritt(l);
            if (p != null) Melden(aus, "laedt", (string)p["schritt"], (int)p["prozent"], "", "");
            return new IntPtr(1);
        };
        int code = 0;
        new Thread(delegate () {
            string r = "";
            try { r = UzcInstaller.Rufen(installer, "install", json); } catch (Exception) { }
            f.Post(delegate () {
                var d = UzbJson.Lesen(r) as Dictionary<string, object>;
                object ok, ver, pfad, msg, errc;
                bool gut = d != null && d.TryGetValue("success", out ok) && ok is bool && (bool)ok;
                string fassung = d != null && d.TryGetValue("installed_version", out ver) && ver is string ? (string)ver : "";
                string libcef = d != null && d.TryGetValue("libcef_path", out pfad) && pfad is string ? (string)pfad : "";
                string text = d != null && d.TryGetValue("error_message", out msg) && msg is string ? (string)msg : "";
                if (d != null && d.TryGetValue("error_code", out errc) && errc is double) text = ((int)(double)errc).ToString(CultureInfo.InvariantCulture) + " " + text;
                Melden(aus, gut ? "fertig" : "fehler", "", 100, UzbRegeln.Sauber(fassung, 64), UzbRegeln.Sauber(gut ? libcef : text, 3000));
                code = gut ? 0 : 9;
                f.Ende();
            });
        }) { IsBackground = true }.Start();
        f.Schleife();
        return code;
    }

    static string Wert(Dictionary<string, object> d, string k) {
        object v;
        return d != null && d.TryGetValue(k, out v) && v is string ? (string)v : "";
    }

    static void Melden(UzbAusgabe aus, string stand, string schritt, int prozent, string fassung, string text) {
        var d = new Dictionary<string, object>();
        d["t"] = "kern";
        d["stand"] = stand;
        d["schritt"] = schritt;
        d["prozent"] = prozent;
        d["fassung"] = fassung;
        d["text"] = text;
        aus.Senden(d);
    }
}

// --- Einstieg (vom Start-Stummel über die .NET-Laufzeit gerufen) -------------------------------------------------

public static class UzcEinstieg {
    static readonly System.Text.RegularExpressions.Regex PROFIL = new System.Text.RegularExpressions.Regex("^[a-z0-9_-]{1,40}\\z");

    public static int Start(string arg) {
        try { return Lauf(arg); } catch (Exception e) {
            // Für logs/browser_kern.log: Art und Text der Ausnahme (Uzai entfernt Benutzerpfade).
            try { Grund(new UzbAusgabe(Console.OpenStandardOutput()), "K3 " + e.GetType().Name + ": " + e.Message); } catch (Exception) { }
            return 3;
        }
    }

    // Warum der Kern nicht startet – kurz, mit Code (K<Rückgabewert>); Uzai schreibt es ins Protokoll und zeigt den
    // Code (kern-Ereignis „fehler“ mit schritt „grund“, ohne eigenen Hinweis auf dem Schirm).
    public static void Grund(UzbAusgabe aus, string text) {
        var d = new Dictionary<string, object>();
        d["t"] = "kern";
        d["stand"] = "fehler";
        d["schritt"] = "grund";
        d["prozent"] = 0;
        d["fassung"] = "";
        d["text"] = UzbRegeln.Sauber(text, 600);
        aus.Senden(d);
    }

    // Nur genau diese Formen: „--uzai-kern --profil=<kennung> --sprache=de-DE|en-US [--grafik=software]“, dasselbe mit
    // „--uzai-spotify“ (Spotify-Sitzung) oder „--uzai-install“. Software-Grafik ist der Rückfall, wenn der GPU-Prozess nicht läuft (Einstellung in Uzai).
    public static bool Argumente(string[] args, out string modus, out string profil, out string sprache) {
        bool software;
        return Argumente(args, out modus, out profil, out sprache, out software);
    }

    public static bool Argumente(string[] args, out string modus, out string profil, out string sprache, out bool software) {
        modus = profil = sprache = "";
        software = false;
        if (args == null) return false;
        if (args.Length == 1 && args[0] == "--uzai-install") { modus = "install"; return true; }
        if (args.Length == 4 && args[3] == "--grafik=software") {
            software = true;
            var kurz = new string[3];
            Array.Copy(args, kurz, 3);
            args = kurz;
        }
        if (args.Length != 3 || (args[0] != "--uzai-kern" && args[0] != "--uzai-spotify")) return false;
        if (!args[1].StartsWith("--profil=", StringComparison.Ordinal) || !args[2].StartsWith("--sprache=", StringComparison.Ordinal)) return false;
        profil = args[1].Substring(9);
        sprache = args[2].Substring(10);
        if (!PROFIL.IsMatch(profil) || (sprache != "de-DE" && sprache != "en-US")) return false;
        modus = args[0] == "--uzai-spotify" ? "spotify" : "kern";
        return true;
    }

    static int Lauf(string arg) {
        UzcApi.HandlesSchliessen();
        var aus = new UzbAusgabe(Console.OpenStandardOutput());
        if (UzcApi.Erhoeht()) { Grund(aus, "K4 Adminrechte"); aus.Fehler("start"); return 4; }
        var start = UzcStart.Lesen(arg);
        if (start == null) { Grund(aus, "K2 Startwerte vom Stummel"); aus.Fehler("start"); return 2; }
        string[] roh = Environment.GetCommandLineArgs();
        var args = new List<string>();
        for (int i = 1; i < roh.Length; i++) args.Add(roh[i]);
        string modus, profil, sprache;
        bool software;
        if (!Argumente(args.ToArray(), out modus, out profil, out sprache, out software)) { Grund(aus, "K2 Argumente (" + args.Count.ToString(CultureInfo.InvariantCulture) + ")"); aus.Fehler("start"); return 2; }
        UzcVorn.Merken();
        var f = new UzbFenster();
        if (!f.Erstellen(0, 0, 1280, 720)) { Grund(aus, "K6 Fenster"); aus.Fehler("start"); return 6; }
        if (modus == "install") return UzcLaden.Start(f, aus);

        // Der Kern selbst: Pfad, Signatur, Fassung prüfen – erst dann wird libcef geladen.
        if (start.Sandbox == IntPtr.Zero) { Grund(aus, "K10 ohne Sandbox vom Bootstrap"); aus.Fehler("kern_sandbox"); return 10; }
        if (start.LibcefPfad == "" || start.Gebuendelt) {
            KernMeldung(aus, "fehler", start.InstallerCode.ToString(CultureInfo.InvariantCulture) + " " + start.InstallerText);
            aus.Fehler("kern_pfad");
            return 11;
        }
        if (!start.LibcefPfad.EndsWith("\\libcef.dll", StringComparison.OrdinalIgnoreCase) || !File.Exists(start.LibcefPfad)) { Grund(aus, "K11 libcef.dll fehlt"); aus.Fehler("kern_pfad"); return 11; }
        if (!UzbSignatur.Von(start.LibcefPfad, UzcV.CEF_ZERTIFIKAT)) { Grund(aus, "K12 Signatur von libcef.dll"); aus.Fehler("kern_signatur"); return 12; }
        IntPtr lib = UzcApi.LoadLibraryExW(start.LibcefPfad, IntPtr.Zero, UzcApi.LOAD_WITH_ALTERED_SEARCH_PATH);
        if (lib == IntPtr.Zero) { Grund(aus, "K11 libcef.dll laden: Fehler " + Marshal.GetLastWin32Error().ToString(CultureInfo.InvariantCulture)); aus.Fehler("kern_pfad"); return 11; }
        string hash = UzcApi.Utf8(UzcApi.cef_api_hash(UzcV.API, 0), 64);
        string fassung = UzcApi.Utf8(UzcApi.cef_version_full(), 80);
        if (hash != UzcV.API_HASH) {
            KernMeldung(aus, "fehler", "API " + UzcV.API.ToString(CultureInfo.InvariantCulture) + " nicht in " + fassung);
            aus.Fehler("kern_api");
            return 13;
        }
        if (start.VersionVoll != "" && start.VersionVoll != fassung) { Grund(aus, "K11 Fassung " + fassung + " statt " + start.VersionVoll); aus.Fehler("kern_pfad"); return 11; }
        string basis = Path.GetDirectoryName(typeof(UzcEinstieg).Assembly.Location) ?? "";
        string skript = Datei(Path.Combine(basis, "uzai-browser-karte.js"));
        string skriptFilter = Datei(Path.Combine(basis, "uzai-browser-filter.js"));
        string cookies = Datei(Path.Combine(basis, "cookies.json"));
        if (skript == null || skriptFilter == null || cookies == null) { Grund(aus, "K5 Skripte neben dem Kern fehlen"); aus.Fehler("pruefung"); return 5; }
        // Die Cookie-Regeln sind Daten: als JSON gelesen und neu geschrieben (maskiert U+2028/2029), dann als Wert vorangestellt.
        var cookieRegeln = UzbJson.Lesen(cookies.TrimStart('\uFEFF')) as Dictionary<string, object>;
        if (cookieRegeln == null) { Grund(aus, "K5 cookies.json"); aus.Fehler("pruefung"); return 5; }
        skriptFilter = "var UZAI_COOKIES = " + UzbJson.Schreiben(cookieRegeln) + ";\n" + skriptFilter;
        UzbFilter filter = null;
        string filterDatei = Path.Combine(basis, "filter.gz");
        if (File.Exists(filterDatei)) { try { filter = UzbFilter.Laden(filterDatei); } catch (Exception) { filter = null; } }
        bool sp = modus == "spotify";
        var w = new UzcKern(f, aus, start, profil, sprache, skript, skriptFilter, sp ? null : filter, software, sp);
        if (!w.Initialisieren()) return 14;
        UzbEingabe.Lesen(Console.OpenStandardInput(), delegate (Dictionary<string, object> b) { f.Post(delegate () { w.Befehl(b); }); },
            delegate () { f.Post(w.Beenden); });
        w.Schleife();
        return 0;
    }

    static string Datei(string pfad) {
        try {
            var info = new FileInfo(pfad);
            if (!info.Exists || info.Length > 262144) return null;
            return File.ReadAllText(pfad, new UTF8Encoding(false, true));
        } catch (Exception) {
            return null;
        }
    }

    static void KernMeldung(UzbAusgabe aus, string stand, string text) {
        var d = new Dictionary<string, object>();
        d["t"] = "kern";
        d["stand"] = stand;
        d["schritt"] = "";
        d["prozent"] = 0;
        d["fassung"] = "";
        d["text"] = UzbRegeln.Sauber(text, 3000);
        aus.Senden(d);
    }
}
