/* Testspiel für das Overlay (tools/bau_overlay.sh --wine): ein Direct3D-11-Fenster, das jedes Bild blau
 * löscht. Vor dem Löschen liest es den Punkt (10, 10) des letzten fertigen Bildes zurück (Tauschkette
 * „der Reihe nach“: der Puffer bleibt nach Present stehen) und schreibt ihn in eine Datei. Mischt das
 * Overlay sein rotes Testbild hinein, steht dort Rot. Läuft rund acht Sekunden.
 *
 *   test_d3d11.exe <Ausgabedatei>     erste Zeile „pid=N“, danach je Messung „punkt R G B“
 */
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#include <windows.h>
#include <stdio.h>
#include <initguid.h>
#include <d3d11.h>

int main(int argc, char **argv) {
	static const D3D_DRIVER_TYPE arten[2] = { D3D_DRIVER_TYPE_HARDWARE, D3D_DRIVER_TYPE_WARP };
	static const float blau[4] = { 0.0f, 0.0f, 200.0f / 255.0f, 1.0f };
	WNDCLASSA wc = { 0 };
	HWND w;
	DXGI_SWAP_CHAIN_DESC sd = { 0 };
	IDXGISwapChain *kette = NULL;
	ID3D11Device *dev = NULL;
	ID3D11DeviceContext *ctx = NULL;
	ID3D11Texture2D *puffer = NULL, *kopie = NULL;
	ID3D11RenderTargetView *ziel = NULL;
	D3D11_TEXTURE2D_DESC td;
	D3D11_MAPPED_SUBRESOURCE m;
	FILE *aus;
	DWORD t0;
	int bild = 0, i;
	if (argc != 2) return 2;
	aus = fopen(argv[1], "w");
	if (!aus) return 2;
	fprintf(aus, "pid=%lu\n", (unsigned long)GetCurrentProcessId());
	fflush(aus);
	wc.lpfnWndProc = DefWindowProcA;
	wc.hInstance = GetModuleHandleA(NULL);
	wc.lpszClassName = "UzaiTestspiel11";
	RegisterClassA(&wc);
	w = CreateWindowExA(0, "UzaiTestspiel11", "Testspiel", WS_POPUP | WS_VISIBLE, 0, 0, 640, 480, NULL, NULL, wc.hInstance, NULL);
	if (!w) { fprintf(aus, "fehler=fenster\n"); fclose(aus); return 3; }
	sd.BufferCount = 1;
	sd.BufferDesc.Width = 640;
	sd.BufferDesc.Height = 480;
	sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
	sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
	sd.OutputWindow = w;
	sd.SampleDesc.Count = 1;
	sd.Windowed = TRUE;
	sd.SwapEffect = DXGI_SWAP_EFFECT_SEQUENTIAL;
	for (i = 0; i < 2 && !kette; i++) {
		if (FAILED(D3D11CreateDeviceAndSwapChain(NULL, arten[i], NULL, 0, NULL, 0, D3D11_SDK_VERSION, &sd, &kette, &dev, NULL, &ctx))) kette = NULL;
	}
	if (!kette || !dev || !ctx) { fprintf(aus, "fehler=geraet\n"); fclose(aus); return 4; }
	if (FAILED(IDXGISwapChain_GetBuffer(kette, 0, &IID_ID3D11Texture2D, (void **)&puffer)) || !puffer
			|| FAILED(ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)puffer, NULL, &ziel))) {
		fprintf(aus, "fehler=puffer\n"); fclose(aus); return 5;
	}
	ID3D11Texture2D_GetDesc(puffer, &td);
	td.Usage = D3D11_USAGE_STAGING;
	td.BindFlags = 0;
	td.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
	td.MiscFlags = 0;
	ID3D11Device_CreateTexture2D(dev, &td, NULL, &kopie);
	t0 = GetTickCount();
	while (GetTickCount() - t0 < 8000) {
		MSG msg;
		while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) DispatchMessageA(&msg);
		if (bild > 0 && bild % 10 == 0 && kopie) {
			ID3D11DeviceContext_CopyResource(ctx, (ID3D11Resource *)kopie, (ID3D11Resource *)puffer);
			if (SUCCEEDED(ID3D11DeviceContext_Map(ctx, (ID3D11Resource *)kopie, 0, D3D11_MAP_READ, 0, &m))) {
				const unsigned char *p = (const unsigned char *)m.pData + 10 * m.RowPitch + 10 * 4;
				fprintf(aus, "punkt %d %d %d\n", p[0], p[1], p[2]);
				fflush(aus);
				ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource *)kopie, 0);
			}
		}
		ID3D11DeviceContext_OMSetRenderTargets(ctx, 1, &ziel, NULL);
		ID3D11DeviceContext_ClearRenderTargetView(ctx, ziel, blau);
		IDXGISwapChain_Present(kette, 0, 0);
		bild++;
		Sleep(16);
	}
	fprintf(aus, "ende bilder=%d\n", bild);
	fclose(aus);
	return 0;
}
