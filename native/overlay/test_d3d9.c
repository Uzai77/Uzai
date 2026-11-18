/* Testspiel für das Overlay (tools/bau_overlay.sh --wine): ein Direct3D-9-Fenster, das jedes Bild blau
 * löscht. Vor dem Löschen liest es den Punkt (10, 10) des letzten fertigen Bildes zurück (Tauschkette
 * „kopieren“: der Puffer bleibt nach Present stehen) und schreibt ihn in eine Datei. Zeichnet das
 * Overlay sein rotes Testbild, steht dort Rot. Läuft rund acht Sekunden.
 *
 *   test_d3d9.exe <Ausgabedatei>     erste Zeile „pid=N“, danach je Messung „punkt R G B“
 */
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#include <windows.h>
#include <stdio.h>
#include <d3d9.h>

int main(int argc, char **argv) {
	WNDCLASSA wc = { 0 };
	HWND w;
	IDirect3D9 *d3d;
	IDirect3DDevice9 *dev = NULL;
	IDirect3DSurface9 *puffer = NULL, *kopie = NULL;
	D3DPRESENT_PARAMETERS pp = { 0 };
	D3DLOCKED_RECT lr;
	FILE *aus;
	DWORD t0;
	int bild = 0;
	if (argc != 2) return 2;
	aus = fopen(argv[1], "w");
	if (!aus) return 2;
	fprintf(aus, "pid=%lu\n", (unsigned long)GetCurrentProcessId());
	fflush(aus);
	wc.lpfnWndProc = DefWindowProcA;
	wc.hInstance = GetModuleHandleA(NULL);
	wc.lpszClassName = "UzaiTestspiel";
	RegisterClassA(&wc);
	w = CreateWindowExA(0, "UzaiTestspiel", "Testspiel", WS_POPUP | WS_VISIBLE, 0, 0, 640, 480, NULL, NULL, wc.hInstance, NULL);
	d3d = Direct3DCreate9(D3D_SDK_VERSION);
	if (!w || !d3d) { fprintf(aus, "fehler=fenster\n"); fclose(aus); return 3; }
	pp.Windowed = TRUE;
	pp.SwapEffect = D3DSWAPEFFECT_COPY;
	pp.BackBufferFormat = D3DFMT_X8R8G8B8;
	pp.BackBufferWidth = 640;
	pp.BackBufferHeight = 480;
	pp.hDeviceWindow = w;
	if (FAILED(IDirect3D9_CreateDevice(d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, w, D3DCREATE_SOFTWARE_VERTEXPROCESSING, &pp, &dev)) || !dev) {
		fprintf(aus, "fehler=geraet\n"); fclose(aus); return 4;
	}
	IDirect3DDevice9_CreateOffscreenPlainSurface(dev, 640, 480, D3DFMT_X8R8G8B8, D3DPOOL_SYSTEMMEM, &kopie, NULL);
	t0 = GetTickCount();
	while (GetTickCount() - t0 < 8000) {
		MSG m;
		while (PeekMessageA(&m, NULL, 0, 0, PM_REMOVE)) DispatchMessageA(&m);
		if (bild > 0 && bild % 10 == 0 && kopie && SUCCEEDED(IDirect3DDevice9_GetBackBuffer(dev, 0, 0, D3DBACKBUFFER_TYPE_MONO, &puffer))) {
			if (SUCCEEDED(IDirect3DDevice9_GetRenderTargetData(dev, puffer, kopie)) && SUCCEEDED(IDirect3DSurface9_LockRect(kopie, &lr, NULL, D3DLOCK_READONLY))) {
				const unsigned char *p = (const unsigned char *)lr.pBits + 10 * lr.Pitch + 10 * 4;
				fprintf(aus, "punkt %d %d %d\n", p[2], p[1], p[0]);
				fflush(aus);
				IDirect3DSurface9_UnlockRect(kopie);
			}
			IDirect3DSurface9_Release(puffer);
			puffer = NULL;
		}
		IDirect3DDevice9_Clear(dev, 0, NULL, D3DCLEAR_TARGET, D3DCOLOR_XRGB(0, 0, 200), 1.0f, 0);
		IDirect3DDevice9_BeginScene(dev);
		IDirect3DDevice9_EndScene(dev);
		IDirect3DDevice9_Present(dev, NULL, NULL, NULL, NULL);
		bild++;
		Sleep(16);
	}
	fprintf(aus, "ende bilder=%d\n", bild);
	fclose(aus);
	return 0;
}
