/* Uzai – Overlay im Spiel (Versuch, docs/OVERLAY.md). Starter: lädt die Bibliothek in das eine Spiel.
 *
 *   uzai-overlay-start32.exe <pid> <voller Pfad der DLL> <voller Pfad der Bilddatei>
 *
 * Nur in den Prozess mit dieser Nummer, mit den Rechten des Nutzers (kein Debug-Recht, nie erhöht):
 * Läuft das Spiel mit höheren Rechten, lehnt Windows ab, und es bleibt beim bisherigen Weg. Die 32-Bit-
 * Fassung lädt nur in 32-Bit-Prozesse, die 64-Bit-Fassung nur in 64-Bit-Prozesse.
 *
 * Ausgabe: eine Zeile „ergebnis=N“, N ist auch der Rückgabewert.
 *   1 Haken sitzt · 2 kein Direct3D 9 im Spiel · 3 Haken ging nicht · 4 Pfad fehlt · 5 lief schon
 *   10 Aufruf falsch · 11 Prozess nicht zu öffnen · 12 falsche Bitbreite · 13 DLL fehlt
 *   14 Speicher im Spiel · 15 Laden ging nicht · 16 Modul nicht gefunden · 17 Einsprung fehlt
 *   18 Start ging nicht · 19 keine Antwort
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <wchar.h>

static int fertig(int n) {
	printf("ergebnis=%d\n", n);
	fflush(stdout);
	return n;
}

static int voller_pfad(const wchar_t *p) {
	size_t n = wcslen(p);
	return n >= 4 && n < 1000 && ((p[1] == L':' && (p[2] == L'\\' || p[2] == L'/')) || (p[0] == L'\\' && p[1] == L'\\'));
}

/* Text in den Speicher des Spiels legen (NULL: ging nicht). */
static void *hinein(HANDLE proz, const wchar_t *text) {
	SIZE_T n = (wcslen(text) + 1) * sizeof(wchar_t), geschrieben = 0;
	void *ort = VirtualAllocEx(proz, NULL, n, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
	if (!ort) return NULL;
	if (!WriteProcessMemory(proz, ort, text, n, &geschrieben) || geschrieben != n) {
		VirtualFreeEx(proz, ort, 0, MEM_RELEASE);
		return NULL;
	}
	return ort;
}

/* Basis der DLL im Spiel (0: nicht geladen). */
static BYTE *basis_im_spiel(DWORD pid, const wchar_t *dll) {
	BYTE *basis = NULL;
	MODULEENTRY32W me;
	HANDLE snap = INVALID_HANDLE_VALUE;
	int versuch;
	for (versuch = 0; versuch < 10 && snap == INVALID_HANDLE_VALUE; versuch++) {
		snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
		if (snap == INVALID_HANDLE_VALUE) Sleep(30);
	}
	if (snap == INVALID_HANDLE_VALUE) return NULL;
	me.dwSize = sizeof me;
	if (Module32FirstW(snap, &me)) {
		do {
			if (_wcsicmp(me.szExePath, dll) == 0) { basis = me.modBaseAddr; break; }
		} while (Module32NextW(snap, &me));
	}
	CloseHandle(snap);
	return basis;
}

int wmain(int argc, wchar_t **argv) {
	DWORD pid = 0, code = 0;
	HANDLE proz, faden;
	BOOL ich32 = FALSE, es32 = FALSE;
	const wchar_t *dll, *bild, *z;
	void *ort_dll, *ort_bild;
	HMODULE hier;
	FARPROC start_hier;
	BYTE *basis;
	LPTHREAD_START_ROUTINE start_dort;

	if (argc != 4) return fertig(10);
	for (z = argv[1]; *z; z++) {
		if (*z < L'0' || *z > L'9' || pid > 400000000u) return fertig(10);
		pid = pid * 10u + (DWORD)(*z - L'0');
	}
	dll = argv[2];
	bild = argv[3];
	if (pid < 8 || pid == GetCurrentProcessId() || !voller_pfad(dll) || !voller_pfad(bild)) return fertig(10);
	if (GetFileAttributesW(dll) == INVALID_FILE_ATTRIBUTES) return fertig(13);

	proz = OpenProcess(PROCESS_CREATE_THREAD | PROCESS_QUERY_INFORMATION | PROCESS_VM_OPERATION | PROCESS_VM_WRITE | PROCESS_VM_READ, FALSE, pid);
	if (!proz) return fertig(11);
	IsWow64Process(GetCurrentProcess(), &ich32);
	IsWow64Process(proz, &es32);
#if defined(_WIN64)
	if (es32) { CloseHandle(proz); return fertig(12); }
#else
	/* 32-Bit-Starter: auf 64-Bit-Windows muss auch das Spiel unter WOW64 laufen. */
	if (ich32 && !es32) { CloseHandle(proz); return fertig(12); }
#endif

	ort_dll = hinein(proz, dll);
	if (!ort_dll) { CloseHandle(proz); return fertig(14); }
	/* kernel32 liegt in allen Prozessen gleicher Bitbreite an derselben Stelle. */
	faden = CreateRemoteThread(proz, NULL, 0, (LPTHREAD_START_ROUTINE)(void *)GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "LoadLibraryW"), ort_dll, 0, NULL);
	if (!faden) { VirtualFreeEx(proz, ort_dll, 0, MEM_RELEASE); CloseHandle(proz); return fertig(15); }
	if (WaitForSingleObject(faden, 8000) != WAIT_OBJECT_0) { CloseHandle(faden); CloseHandle(proz); return fertig(19); }
	GetExitCodeThread(faden, &code);
	CloseHandle(faden);
	VirtualFreeEx(proz, ort_dll, 0, MEM_RELEASE);
	if (code == 0) { CloseHandle(proz); return fertig(15); }

	basis = basis_im_spiel(pid, dll);
	if (!basis) { CloseHandle(proz); return fertig(16); }
	/* Wo der Einsprung in der DLL liegt, sagt eine eigene, nicht ausgeführte Abbildung derselben Datei. */
	hier = LoadLibraryExW(dll, NULL, DONT_RESOLVE_DLL_REFERENCES);
	start_hier = hier ? GetProcAddress(hier, "UzaiOverlayStart") : NULL;
	if (!start_hier) { CloseHandle(proz); return fertig(17); }
	start_dort = (LPTHREAD_START_ROUTINE)(void *)(basis + ((BYTE *)(void *)start_hier - (BYTE *)hier));

	ort_bild = hinein(proz, bild);
	if (!ort_bild) { CloseHandle(proz); return fertig(14); }
	faden = CreateRemoteThread(proz, NULL, 0, start_dort, ort_bild, 0, NULL);
	if (!faden) { VirtualFreeEx(proz, ort_bild, 0, MEM_RELEASE); CloseHandle(proz); return fertig(18); }
	if (WaitForSingleObject(faden, 8000) != WAIT_OBJECT_0) { CloseHandle(faden); CloseHandle(proz); return fertig(19); }
	code = 0;
	GetExitCodeThread(faden, &code);
	CloseHandle(faden);
	VirtualFreeEx(proz, ort_bild, 0, MEM_RELEASE);
	CloseHandle(proz);
	return fertig(code >= 1 && code <= 5 ? (int)code : 3);
}
