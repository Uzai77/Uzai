/* Uzai – Overlay im Spiel (Versuch, docs/OVERLAY.md). Bibliothek, die im Spielprozess läuft.
 *
 * Stufe 1: Direct3D 9. Sie hängt sich an Present (Gerät und Tauschkette) und Reset, liest das Bild
 * des Guides aus einer Datei, die Uzai schreibt (uzai_overlay.h), und zeichnet es links über das
 * fertige Bild des Spiels. Solange es zu sehen ist, bekommt das Spiel von XInput einen leeren
 * Controller (nur 32 Bit, nur wenn die Funktion mit dem üblichen Vorspann beginnt).
 *
 * Stufe 2: Direct3D 11 über DXGI. Sie hängt sich an Present der Tauschkette und mischt das Bild auf
 * dem Prozessor in den fertigen Bildpuffer (Ausschnitt holen, mischen, zurückschreiben) – ohne
 * Shader und ohne den Zustand des Spiels anzufassen. Nur 8-Bit-Formate ohne Kantenglättung im
 * Puffer; alles andere (10 Bit, HDR, Direct3D 10 und 12) bleibt unberührt.
 *
 * Regeln: Die Bibliothek nimmt nur Bildpunkte und „zeigen/verstecken“ an. Sie öffnet nichts außer
 * der einen Datei (nur lesend), startet nichts, schreibt nichts, spricht mit niemandem. Bei jedem
 * unerwarteten Ergebnis schaltet sie sich für den Rest des Laufs ab (g_aus) und reicht nur noch durch.
 * Sie entlädt sich nie selbst (ein entladener Haken wäre ein Sprung ins Leere).
 */
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#include <windows.h>
#include <string.h>
#include <initguid.h>
#include <d3d9.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include "uzai_overlay.h"

static wchar_t g_pfad[1024];
static HANDLE g_datei = INVALID_HANDLE_VALUE;
static HANDLE g_map = NULL;
static const unsigned char *g_sicht = NULL;
static size_t g_sicht_n = 0;
static DWORD g_neu_ab = 0;                 /* frühestens dann wieder abbilden (GetTickCount) */
static volatile LONG g_aus = 0;            /* 1: nur noch durchreichen */
static volatile LONG g_sichtbar = 0;       /* das Overlay ist zu sehen (XInput leer) */
static volatile LONG g_gestartet = 0;

typedef HRESULT (WINAPI *Present9_t)(IDirect3DDevice9 *, const RECT *, const RECT *, HWND, const RGNDATA *);
typedef HRESULT (WINAPI *Reset9_t)(IDirect3DDevice9 *, D3DPRESENT_PARAMETERS *);
typedef HRESULT (WINAPI *KettePresent9_t)(IDirect3DSwapChain9 *, const RECT *, const RECT *, HWND, const RGNDATA *, DWORD);
static Present9_t o_Present9 = NULL;
static Reset9_t o_Reset9 = NULL;
static KettePresent9_t o_KettePresent9 = NULL;

static IDirect3DDevice9 *g_geraet = NULL;
static IDirect3DTexture9 *g_tex = NULL;
static IDirect3DStateBlock9 *g_zustand = NULL;
static UINT g_tex_b = 0, g_tex_h = 0;
static uint32_t g_tex_zaehler = 0xFFFFFFFFu;
static volatile LONG g_im_zeichnen = 0;

/* --- Bild aus der Datei ------------------------------------------------------------------- */

static void abbildung_zu(void) {
	if (g_sicht) UnmapViewOfFile(g_sicht);
	if (g_map) CloseHandle(g_map);
	if (g_datei != INVALID_HANDLE_VALUE) CloseHandle(g_datei);
	g_sicht = NULL; g_map = NULL; g_datei = INVALID_HANDLE_VALUE; g_sicht_n = 0;
}

/* Die Datei nur lesend abbilden. Uzai darf weiterschreiben und sie verlängern. */
static int abbilden(void) {
	LARGE_INTEGER gr;
	abbildung_zu();
	g_neu_ab = GetTickCount() + 1000;
	g_datei = CreateFileW(g_pfad, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
	if (g_datei == INVALID_HANDLE_VALUE) return 0;
	if (!GetFileSizeEx(g_datei, &gr) || gr.QuadPart < (LONGLONG)UZOV_KOPF
			|| gr.QuadPart > (LONGLONG)UZOV_KOPF + (LONGLONG)UZOV_MAX_BREITE * UZOV_MAX_HOEHE * 4) {
		abbildung_zu();
		return 0;
	}
	g_map = CreateFileMappingW(g_datei, NULL, PAGE_READONLY, 0, 0, NULL);
	if (!g_map) { abbildung_zu(); return 0; }
	g_sicht = (const unsigned char *)MapViewOfFile(g_map, FILE_MAP_READ, 0, 0, 0);
	if (!g_sicht) { abbildung_zu(); return 0; }
	g_sicht_n = (size_t)gr.QuadPart;
	return 1;
}

static void d3d9_frei(void) {
	if (g_zustand) { IDirect3DStateBlock9_Release(g_zustand); g_zustand = NULL; }
	if (g_tex) { IDirect3DTexture9_Release(g_tex); g_tex = NULL; }
	g_tex_b = 0; g_tex_h = 0; g_tex_zaehler = 0xFFFFFFFFu;
}

/* Kopf lesen und, wenn sich das Bild geändert hat, in die Textur kopieren. 1: es gibt etwas zu zeichnen. */
static int bild_holen(IDirect3DDevice9 *dev) {
	uzov_kopf k;
	D3DLOCKED_RECT lr;
	UINT y, x;
	if (!g_sicht && (GetTickCount() < g_neu_ab || !abbilden())) { g_sichtbar = 0; return 0; }
	memcpy(&k, g_sicht, sizeof k);
	if (!uzov_kopf_pruefen(&k, g_sicht_n)) {
		/* Größer geworden als abgebildet: höchstens einmal je Sekunde neu abbilden. */
		if (uzov_laenge(&k) > g_sicht_n && GetTickCount() >= g_neu_ab) abbilden();
		return g_sichtbar && g_tex != NULL;       /* Uzai schreibt gerade: das letzte Bild bleibt */
	}
	InterlockedExchange(&g_sichtbar, (LONG)k.sichtbar);
	if (!k.sichtbar) return 0;
	if (g_tex && k.zaehler == g_tex_zaehler && k.breite == g_tex_b && k.hoehe == g_tex_h) return 1;
	if (!g_tex || k.breite != g_tex_b || k.hoehe != g_tex_h) {
		if (g_tex) { IDirect3DTexture9_Release(g_tex); g_tex = NULL; }
		if (FAILED(IDirect3DDevice9_CreateTexture(dev, k.breite, k.hoehe, 1, 0, D3DFMT_A8R8G8B8, D3DPOOL_MANAGED, &g_tex, NULL))) {
			g_tex = NULL;
			InterlockedExchange(&g_aus, 1);
			return 0;
		}
		g_tex_b = k.breite; g_tex_h = k.hoehe;
	}
	if (FAILED(IDirect3DTexture9_LockRect(g_tex, 0, &lr, NULL, 0))) return 0;
	for (y = 0; y < k.hoehe; y++) {
		const unsigned char *s = g_sicht + UZOV_KOPF + (size_t)y * k.breite * 4u;
		unsigned char *d = (unsigned char *)lr.pBits + (size_t)y * (size_t)lr.Pitch;
		for (x = 0; x < k.breite; x++) {      /* R G B A → B G R A */
			d[0] = s[2]; d[1] = s[1]; d[2] = s[0]; d[3] = s[3];
			d += 4; s += 4;
		}
	}
	IDirect3DTexture9_UnlockRect(g_tex, 0);
	/* Hat Uzai währenddessen geschrieben, ist das Bild vielleicht gerissen: beim nächsten Mal noch einmal. */
	g_tex_zaehler = (((const uzov_kopf *)g_sicht)->zaehler == k.zaehler) ? k.zaehler : 0xFFFFFFFFu;
	return 1;
}

/* --- Zeichnen ------------------------------------------------------------------------------ */

typedef struct { float x, y, z, rhw, u, v; } punkt;
#define PUNKT_FVF (D3DFVF_XYZRHW | D3DFVF_TEX1)

static void zeichnen9(IDirect3DDevice9 *dev) {
	IDirect3DSurface9 *puffer = NULL, *ziel_alt = NULL;
	D3DSURFACE_DESC sd;
	D3DVIEWPORT9 vp;
	punkt p[4];
	float b, h;
	if (g_aus || !dev) return;
	if (InterlockedCompareExchange(&g_im_zeichnen, 1, 0) != 0) return;      /* nicht verschachtelt, nicht aus zwei Fäden */
	if (dev != g_geraet) { d3d9_frei(); g_geraet = dev; }
	if (!bild_holen(dev)) goto ende;
	if (FAILED(IDirect3DDevice9_GetBackBuffer(dev, 0, 0, D3DBACKBUFFER_TYPE_MONO, &puffer)) || !puffer) goto ende;
	if (FAILED(IDirect3DSurface9_GetDesc(puffer, &sd)) || sd.Width == 0 || sd.Height == 0) goto ende;
	if (!g_zustand && FAILED(IDirect3DDevice9_CreateStateBlock(dev, D3DSBT_ALL, &g_zustand))) {
		g_zustand = NULL;
		InterlockedExchange(&g_aus, 1);
		goto ende;
	}
	if (FAILED(IDirect3DStateBlock9_Capture(g_zustand))) goto ende;
	IDirect3DDevice9_GetRenderTarget(dev, 0, &ziel_alt);
	IDirect3DDevice9_SetRenderTarget(dev, 0, puffer);
	if (SUCCEEDED(IDirect3DDevice9_BeginScene(dev))) {
		vp.X = 0; vp.Y = 0; vp.Width = sd.Width; vp.Height = sd.Height; vp.MinZ = 0.0f; vp.MaxZ = 1.0f;
		IDirect3DDevice9_SetViewport(dev, &vp);
		IDirect3DDevice9_SetVertexShader(dev, NULL);
		IDirect3DDevice9_SetPixelShader(dev, NULL);
		IDirect3DDevice9_SetFVF(dev, PUNKT_FVF);
		IDirect3DDevice9_SetTexture(dev, 0, (IDirect3DBaseTexture9 *)g_tex);
		IDirect3DDevice9_SetRenderState(dev, D3DRS_ZENABLE, FALSE);
		IDirect3DDevice9_SetRenderState(dev, D3DRS_ZWRITEENABLE, FALSE);
		IDirect3DDevice9_SetRenderState(dev, D3DRS_LIGHTING, FALSE);
		IDirect3DDevice9_SetRenderState(dev, D3DRS_FOGENABLE, FALSE);
		IDirect3DDevice9_SetRenderState(dev, D3DRS_CULLMODE, D3DCULL_NONE);
		IDirect3DDevice9_SetRenderState(dev, D3DRS_SCISSORTESTENABLE, FALSE);
		IDirect3DDevice9_SetRenderState(dev, D3DRS_STENCILENABLE, FALSE);
		IDirect3DDevice9_SetRenderState(dev, D3DRS_ALPHATESTENABLE, FALSE);
		IDirect3DDevice9_SetRenderState(dev, D3DRS_SRGBWRITEENABLE, FALSE);
		IDirect3DDevice9_SetRenderState(dev, D3DRS_COLORWRITEENABLE, 0xF);
		IDirect3DDevice9_SetRenderState(dev, D3DRS_FILLMODE, D3DFILL_SOLID);
		IDirect3DDevice9_SetRenderState(dev, D3DRS_ALPHABLENDENABLE, TRUE);
		IDirect3DDevice9_SetRenderState(dev, D3DRS_SEPARATEALPHABLENDENABLE, FALSE);
		IDirect3DDevice9_SetRenderState(dev, D3DRS_BLENDOP, D3DBLENDOP_ADD);
		IDirect3DDevice9_SetRenderState(dev, D3DRS_SRCBLEND, D3DBLEND_SRCALPHA);
		IDirect3DDevice9_SetRenderState(dev, D3DRS_DESTBLEND, D3DBLEND_INVSRCALPHA);
		IDirect3DDevice9_SetTextureStageState(dev, 0, D3DTSS_COLOROP, D3DTOP_SELECTARG1);
		IDirect3DDevice9_SetTextureStageState(dev, 0, D3DTSS_COLORARG1, D3DTA_TEXTURE);
		IDirect3DDevice9_SetTextureStageState(dev, 0, D3DTSS_ALPHAOP, D3DTOP_SELECTARG1);
		IDirect3DDevice9_SetTextureStageState(dev, 0, D3DTSS_ALPHAARG1, D3DTA_TEXTURE);
		IDirect3DDevice9_SetTextureStageState(dev, 1, D3DTSS_COLOROP, D3DTOP_DISABLE);
		IDirect3DDevice9_SetTextureStageState(dev, 1, D3DTSS_ALPHAOP, D3DTOP_DISABLE);
		IDirect3DDevice9_SetSamplerState(dev, 0, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);
		IDirect3DDevice9_SetSamplerState(dev, 0, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
		IDirect3DDevice9_SetSamplerState(dev, 0, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
		IDirect3DDevice9_SetSamplerState(dev, 0, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);
		IDirect3DDevice9_SetSamplerState(dev, 0, D3DSAMP_SRGBTEXTURE, FALSE);
		/* Links, über die ganze Höhe: Das Bild behält sein Seitenverhältnis. */
		h = (float)sd.Height;
		b = (float)g_tex_b * h / (float)g_tex_h;
		p[0].x = -0.5f;     p[0].y = -0.5f;     p[0].u = 0.0f; p[0].v = 0.0f;
		p[1].x = b - 0.5f;  p[1].y = -0.5f;     p[1].u = 1.0f; p[1].v = 0.0f;
		p[2].x = -0.5f;     p[2].y = h - 0.5f;  p[2].u = 0.0f; p[2].v = 1.0f;
		p[3].x = b - 0.5f;  p[3].y = h - 0.5f;  p[3].u = 1.0f; p[3].v = 1.0f;
		p[0].z = p[1].z = p[2].z = p[3].z = 0.0f;
		p[0].rhw = p[1].rhw = p[2].rhw = p[3].rhw = 1.0f;
		IDirect3DDevice9_DrawPrimitiveUP(dev, D3DPT_TRIANGLESTRIP, 2, p, sizeof(punkt));
		IDirect3DDevice9_EndScene(dev);
	}
	IDirect3DStateBlock9_Apply(g_zustand);
	if (ziel_alt) IDirect3DDevice9_SetRenderTarget(dev, 0, ziel_alt);
ende:
	if (ziel_alt) IDirect3DSurface9_Release(ziel_alt);
	if (puffer) IDirect3DSurface9_Release(puffer);
	InterlockedExchange(&g_im_zeichnen, 0);
}

static HRESULT WINAPI haken_Present9(IDirect3DDevice9 *dev, const RECT *a, const RECT *b, HWND w, const RGNDATA *r) {
	zeichnen9(dev);
	return o_Present9(dev, a, b, w, r);
}

static HRESULT WINAPI haken_KettePresent9(IDirect3DSwapChain9 *kette, const RECT *a, const RECT *b, HWND w, const RGNDATA *r, DWORD f) {
	IDirect3DDevice9 *dev = NULL;
	if (!g_aus && kette && SUCCEEDED(IDirect3DSwapChain9_GetDevice(kette, &dev)) && dev) {
		zeichnen9(dev);
		IDirect3DDevice9_Release(dev);
	}
	return o_KettePresent9(kette, a, b, w, r, f);
}

/* Vor Reset muss alles frei sein, was am Gerät hängt (der Zustandsblock). */
static HRESULT WINAPI haken_Reset9(IDirect3DDevice9 *dev, D3DPRESENT_PARAMETERS *pp) {
	if (dev == g_geraet) d3d9_frei();
	return o_Reset9(dev, pp);
}

/* --- Direct3D 11 über DXGI (Stufe 2) ---------------------------------------------------------- */

typedef HRESULT (WINAPI *PresentDxgi_t)(IDXGISwapChain *, UINT, UINT);
typedef HRESULT (WINAPI *Present1Dxgi_t)(IDXGISwapChain1 *, UINT, UINT, const DXGI_PRESENT_PARAMETERS *);
static PresentDxgi_t o_PresentDxgi = NULL;
static Present1Dxgi_t o_Present1Dxgi = NULL;

static unsigned char *g_bild = NULL;              /* Kopie des Bilds aus der Datei, R G B A */
static UINT g_bild_b = 0, g_bild_h = 0;
static uint32_t g_bild_zaehler = 0xFFFFFFFFu;
static ID3D11Texture2D *g_zwischen = NULL;        /* Ausschnitt des Bildpuffers zum Lesen und Schreiben */
static void *g_zw_geraet = NULL;
static UINT g_zw_b = 0, g_zw_h = 0;
static DXGI_FORMAT g_zw_format = DXGI_FORMAT_UNKNOWN;

/* Kopf lesen und, wenn sich das Bild geändert hat, kopieren. 1: es gibt etwas zu zeichnen. */
static int bild_kopie(void) {
	uzov_kopf k;
	size_t n;
	if (!g_sicht && (GetTickCount() < g_neu_ab || !abbilden())) { g_sichtbar = 0; return 0; }
	memcpy(&k, g_sicht, sizeof k);
	if (!uzov_kopf_pruefen(&k, g_sicht_n)) {
		if (uzov_laenge(&k) > g_sicht_n && GetTickCount() >= g_neu_ab) abbilden();
		return g_sichtbar && g_bild != NULL;      /* Uzai schreibt gerade: das letzte Bild bleibt */
	}
	InterlockedExchange(&g_sichtbar, (LONG)k.sichtbar);
	if (!k.sichtbar) return 0;
	if (g_bild && k.zaehler == g_bild_zaehler && k.breite == g_bild_b && k.hoehe == g_bild_h) return 1;
	n = (size_t)k.breite * k.hoehe * 4u;
	if (!g_bild || k.breite != g_bild_b || k.hoehe != g_bild_h) {
		if (g_bild) HeapFree(GetProcessHeap(), 0, g_bild);
		g_bild = (unsigned char *)HeapAlloc(GetProcessHeap(), 0, n);
		if (!g_bild) {
			g_bild_b = 0; g_bild_h = 0;
			InterlockedExchange(&g_aus, 1);
			return 0;
		}
		g_bild_b = k.breite; g_bild_h = k.hoehe;
	}
	memcpy(g_bild, g_sicht + UZOV_KOPF, n);
	g_bild_zaehler = (((const uzov_kopf *)g_sicht)->zaehler == k.zaehler) ? k.zaehler : 0xFFFFFFFFu;
	return 1;
}

/* Das Bild links über die ganze Höhe in den fertigen Bildpuffer mischen (Seitenverhältnis bleibt). */
static void zeichnen11(IDXGISwapChain *kette) {
	ID3D11Device *dev = NULL;
	ID3D11DeviceContext *ctx = NULL;
	ID3D11Texture2D *puffer = NULL;
	D3D11_TEXTURE2D_DESC td;
	D3D11_MAPPED_SUBRESOURCE m;
	D3D11_BOX kasten;
	UINT zb, zh, x, y;
	unsigned long long schritt_x, schritt_y;
	int rot_zuerst;
	if (g_aus || !kette) return;
	if (InterlockedCompareExchange(&g_im_zeichnen, 1, 0) != 0) return;
	if (!bild_kopie() || g_bild_b == 0 || g_bild_h == 0) goto ende;
	/* Kein Direct3D-11-Gerät hinter der Kette (Direct3D 10 oder 12): nichts anfassen. */
	if (FAILED(IDXGISwapChain_GetDevice(kette, &IID_ID3D11Device, (void **)&dev)) || !dev) goto ende;
	if (FAILED(IDXGISwapChain_GetBuffer(kette, 0, &IID_ID3D11Texture2D, (void **)&puffer)) || !puffer) goto ende;
	ID3D11Texture2D_GetDesc(puffer, &td);
	if (td.SampleDesc.Count != 1 || td.Width == 0 || td.Height == 0) goto ende;
	switch (td.Format) {
		case DXGI_FORMAT_R8G8B8A8_UNORM: case DXGI_FORMAT_R8G8B8A8_UNORM_SRGB: case DXGI_FORMAT_R8G8B8A8_TYPELESS:
			rot_zuerst = 1; break;
		case DXGI_FORMAT_B8G8R8A8_UNORM: case DXGI_FORMAT_B8G8R8A8_UNORM_SRGB: case DXGI_FORMAT_B8G8R8A8_TYPELESS:
		case DXGI_FORMAT_B8G8R8X8_UNORM: case DXGI_FORMAT_B8G8R8X8_UNORM_SRGB: case DXGI_FORMAT_B8G8R8X8_TYPELESS:
			rot_zuerst = 0; break;
		default:
			goto ende;                                /* 10 Bit, HDR: unberührt */
	}
	zh = td.Height;
	zb = (UINT)(((unsigned long long)g_bild_b * td.Height) / g_bild_h);
	if (zb > td.Width) zb = td.Width;
	if (zb == 0) goto ende;
	if (!g_zwischen || g_zw_geraet != (void *)dev || g_zw_b != zb || g_zw_h != zh || g_zw_format != td.Format) {
		D3D11_TEXTURE2D_DESC zd = td;
		if (g_zwischen) { ID3D11Texture2D_Release(g_zwischen); g_zwischen = NULL; }
		zd.Width = zb; zd.Height = zh; zd.MipLevels = 1; zd.ArraySize = 1;
		zd.Usage = D3D11_USAGE_STAGING; zd.BindFlags = 0; zd.MiscFlags = 0;
		zd.CPUAccessFlags = D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE;
		if (FAILED(ID3D11Device_CreateTexture2D(dev, &zd, NULL, &g_zwischen)) || !g_zwischen) {
			g_zwischen = NULL;
			InterlockedExchange(&g_aus, 1);
			goto ende;
		}
		g_zw_geraet = (void *)dev; g_zw_b = zb; g_zw_h = zh; g_zw_format = td.Format;
	}
	ID3D11Device_GetImmediateContext(dev, &ctx);
	if (!ctx) goto ende;
	kasten.left = 0; kasten.top = 0; kasten.front = 0; kasten.right = zb; kasten.bottom = zh; kasten.back = 1;
	ID3D11DeviceContext_CopySubresourceRegion(ctx, (ID3D11Resource *)g_zwischen, 0, 0, 0, 0, (ID3D11Resource *)puffer, 0, &kasten);
	if (SUCCEEDED(ID3D11DeviceContext_Map(ctx, (ID3D11Resource *)g_zwischen, 0, D3D11_MAP_READ_WRITE, 0, &m)) && m.pData) {
		/* Festkomma 32.32: welcher Punkt des Bilds zu welchem Punkt des Puffers gehört (nächster Nachbar). */
		schritt_x = ((unsigned long long)g_bild_b << 32) / zb;
		schritt_y = ((unsigned long long)g_bild_h << 32) / zh;
		for (y = 0; y < zh; y++) {
			UINT qy = (UINT)((y * schritt_y) >> 32);
			const unsigned char *zeile;
			unsigned char *d = (unsigned char *)m.pData + (size_t)y * (size_t)m.RowPitch;
			unsigned long long fx = 0;
			if (qy >= g_bild_h) qy = g_bild_h - 1;
			zeile = g_bild + (size_t)qy * g_bild_b * 4u;
			for (x = 0; x < zb; x++, d += 4, fx += schritt_x) {
				UINT qx = (UINT)(fx >> 32);
				const unsigned char *s;
				unsigned a, c0, c2;
				if (qx >= g_bild_b) qx = g_bild_b - 1;
				s = zeile + (size_t)qx * 4u;
				a = s[3];
				if (!a) continue;
				c0 = rot_zuerst ? s[0] : s[2];
				c2 = rot_zuerst ? s[2] : s[0];
				if (a == 255) {
					d[0] = (unsigned char)c0; d[1] = s[1]; d[2] = (unsigned char)c2;
				} else {
					d[0] = (unsigned char)((c0 * a + d[0] * (255u - a) + 127u) / 255u);
					d[1] = (unsigned char)((s[1] * a + d[1] * (255u - a) + 127u) / 255u);
					d[2] = (unsigned char)((c2 * a + d[2] * (255u - a) + 127u) / 255u);
				}
			}
		}
		ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource *)g_zwischen, 0);
		ID3D11DeviceContext_CopySubresourceRegion(ctx, (ID3D11Resource *)puffer, 0, 0, 0, 0, (ID3D11Resource *)g_zwischen, 0, NULL);
	}
ende:
	if (ctx) ID3D11DeviceContext_Release(ctx);
	if (puffer) ID3D11Texture2D_Release(puffer);
	if (dev) ID3D11Device_Release(dev);
	InterlockedExchange(&g_im_zeichnen, 0);
}

static HRESULT WINAPI haken_PresentDxgi(IDXGISwapChain *kette, UINT sync, UINT flags) {
	if (!(flags & DXGI_PRESENT_TEST)) zeichnen11(kette);
	return o_PresentDxgi(kette, sync, flags);
}

static HRESULT WINAPI haken_Present1Dxgi(IDXGISwapChain1 *kette, UINT sync, UINT flags, const DXGI_PRESENT_PARAMETERS *p) {
	if (!(flags & DXGI_PRESENT_TEST)) zeichnen11((IDXGISwapChain *)kette);
	return o_Present1Dxgi(kette, sync, flags, p);
}

/* Einen Eintrag der Funktionstabelle tauschen. 1: getauscht, alt trägt den früheren Zeiger. */
static int eintrag_tauschen(void **eintrag, void *neu, void **alt) {
	DWORD schutz, egal;
	if (!eintrag || !*eintrag || *eintrag == neu) return 0;
	if (!VirtualProtect(eintrag, sizeof(void *), PAGE_READWRITE, &schutz)) return 0;
	*alt = *eintrag;
	*eintrag = neu;
	VirtualProtect(eintrag, sizeof(void *), schutz, &egal);
	return 1;
}

/* Die Funktionstabellen von Direct3D 9 über ein eigenes, unsichtbares Gerät finden (alle Geräte des
 * Prozesses teilen sie) und Present und Reset umhängen. 1: sitzt, 2: kein Direct3D 9, 3: ging nicht. */
static DWORD haken9(void) {
	typedef IDirect3D9 *(WINAPI *Create9_t)(UINT);
	HMODULE m = GetModuleHandleW(L"d3d9.dll");
	Create9_t create;
	IDirect3D9 *d3d = NULL;
	IDirect3DDevice9 *dev = NULL;
	IDirect3DSwapChain9 *kette = NULL;
	D3DPRESENT_PARAMETERS pp;
	HWND w;
	DWORD erg = 3;
	if (!m) return 2;
	create = (Create9_t)(void *)GetProcAddress(m, "Direct3DCreate9");
	if (!create) return 3;
	d3d = create(D3D_SDK_VERSION);
	if (!d3d) return 3;
	w = CreateWindowExW(0, L"STATIC", L"", WS_POPUP, 0, 0, 8, 8, NULL, NULL, GetModuleHandleW(NULL), NULL);
	memset(&pp, 0, sizeof pp);
	pp.Windowed = TRUE;
	pp.SwapEffect = D3DSWAPEFFECT_DISCARD;
	pp.BackBufferFormat = D3DFMT_UNKNOWN;
	pp.hDeviceWindow = w;
	if (w && SUCCEEDED(IDirect3D9_CreateDevice(d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_NULLREF, w,
			D3DCREATE_SOFTWARE_VERTEXPROCESSING | D3DCREATE_NOWINDOWCHANGES, &pp, &dev)) && dev) {
		void **tab = *(void ***)dev;
		int ok = eintrag_tauschen(&tab[16], (void *)haken_Reset9, (void **)&o_Reset9);
		ok = ok && eintrag_tauschen(&tab[17], (void *)haken_Present9, (void **)&o_Present9);
		if (ok && SUCCEEDED(IDirect3DDevice9_GetSwapChain(dev, 0, &kette)) && kette) {
			void **ktab = *(void ***)kette;
			eintrag_tauschen(&ktab[3], (void *)haken_KettePresent9, (void **)&o_KettePresent9);
			IDirect3DSwapChain9_Release(kette);
		}
		erg = ok ? 1 : 3;
		IDirect3DDevice9_Release(dev);
	}
	if (w) DestroyWindow(w);
	IDirect3D9_Release(d3d);
	return erg;
}

/* Die Funktionstabelle der Tauschketten von DXGI über ein eigenes, unsichtbares Gerät finden (alle
 * Ketten des Prozesses teilen sie) und Present (und Present1) umhängen. Nur wenn das Spiel Direct3D 11
 * schon geladen hat; mit Direct3D 12 im Prozess gar nicht (dort gibt es keinen fertigen Puffer, den
 * man so anfassen dürfte). 1: sitzt, 2: kein Direct3D 11, 3: ging nicht, 6: Direct3D 12. */
static DWORD haken_dxgi(void) {
	typedef HRESULT (WINAPI *Create11_t)(IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT, const D3D_FEATURE_LEVEL *, UINT, UINT,
			const DXGI_SWAP_CHAIN_DESC *, IDXGISwapChain **, ID3D11Device **, D3D_FEATURE_LEVEL *, ID3D11DeviceContext **);
	static const D3D_DRIVER_TYPE arten[2] = { D3D_DRIVER_TYPE_HARDWARE, D3D_DRIVER_TYPE_WARP };
	HMODULE m = GetModuleHandleW(L"d3d11.dll");
	Create11_t create;
	DXGI_SWAP_CHAIN_DESC sd;
	IDXGISwapChain *kette = NULL;
	IDXGISwapChain1 *kette1 = NULL;
	ID3D11Device *dev = NULL;
	ID3D11DeviceContext *ctx = NULL;
	HWND w;
	DWORD erg = 3;
	int i;
	if (!m || !GetModuleHandleW(L"dxgi.dll")) return 2;
	if (GetModuleHandleW(L"d3d12.dll") || GetModuleHandleW(L"d3d12core.dll")) return 6;
	create = (Create11_t)(void *)GetProcAddress(m, "D3D11CreateDeviceAndSwapChain");
	if (!create) return 3;
	w = CreateWindowExW(0, L"STATIC", L"", WS_POPUP, 0, 0, 8, 8, NULL, NULL, GetModuleHandleW(NULL), NULL);
	if (!w) return 3;
	memset(&sd, 0, sizeof sd);
	sd.BufferCount = 1;
	sd.BufferDesc.Width = 8;
	sd.BufferDesc.Height = 8;
	sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
	sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
	sd.OutputWindow = w;
	sd.SampleDesc.Count = 1;
	sd.Windowed = TRUE;
	sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
	for (i = 0; i < 2 && !kette; i++) {
		if (FAILED(create(NULL, arten[i], NULL, 0, NULL, 0, D3D11_SDK_VERSION, &sd, &kette, &dev, NULL, &ctx))) kette = NULL;
	}
	if (kette) {
		void **tab = *(void ***)kette;
		int ok = eintrag_tauschen(&tab[8], (void *)haken_PresentDxgi, (void **)&o_PresentDxgi);
		/* Present1 (IDXGISwapChain1, Eintrag 22) liegt in derselben Tabelle, wenn die Kette es kann. */
		if (ok && SUCCEEDED(IDXGISwapChain_QueryInterface(kette, &IID_IDXGISwapChain1, (void **)&kette1)) && kette1) {
			if (*(void ***)kette1 == tab) eintrag_tauschen(&tab[22], (void *)haken_Present1Dxgi, (void **)&o_Present1Dxgi);
			IDXGISwapChain1_Release(kette1);
		}
		erg = ok ? 1 : 3;
	}
	if (ctx) ID3D11DeviceContext_Release(ctx);
	if (kette) IDXGISwapChain_Release(kette);
	if (dev) ID3D11Device_Release(dev);
	DestroyWindow(w);
	return erg;
}

/* --- XInput: leerer Controller, solange das Overlay zu sehen ist (nur 32 Bit) -------------------- */

#if defined(__i386__)
typedef struct { WORD knoepfe; BYTE lt, rt; SHORT lx, ly, rx, ry; } xi_pad;
typedef struct { DWORD paket; xi_pad pad; } xi_zustand;
typedef DWORD (WINAPI *XiGet_t)(DWORD, xi_zustand *);
#define XI_N 4
static XiGet_t g_xi_alt[XI_N];

#define XI_HAKEN(n) static DWORD WINAPI haken_xi##n(DWORD i, xi_zustand *z) { \
	DWORD r = g_xi_alt[n](i, z); \
	if (g_sichtbar && !g_aus && r == 0 && z) memset(&z->pad, 0, sizeof z->pad); \
	return r; }
XI_HAKEN(0) XI_HAKEN(1) XI_HAKEN(2) XI_HAKEN(3)
static const XiGet_t g_xi_neu[XI_N] = { haken_xi0, haken_xi1, haken_xi2, haken_xi3 };
static const wchar_t *g_xi_dll[XI_N] = { L"xinput1_4.dll", L"xinput1_3.dll", L"xinput9_1_0.dll", L"xinput1_2.dll" };

/* Nur bei Funktionen, die Windows zum Umhängen vorbereitet hat: Sie beginnen mit „mov edi,edi“ (zwei
 * Byte ohne Wirkung), davor liegen fünf Füllbyte. In die Füllbyte kommt der weite Sprung zu uns, dann
 * werden die zwei Byte in einem Schritt zum kurzen Sprung dorthin – kein Faden sieht je einen halben
 * Befehl. Das Original läuft ab dem dritten Byte weiter. Passt das Muster nicht, bleibt alles, wie es ist. */
static void xinput_haken(void) {
	int n, i;
	for (n = 0; n < XI_N; n++) {
		HMODULE m;
		unsigned char *f;
		DWORD schutz, egal;
		int fuell = 1;
		if (g_xi_alt[n]) continue;
		m = GetModuleHandleW(g_xi_dll[n]);
		if (!m) continue;
		f = (unsigned char *)(void *)GetProcAddress(m, "XInputGetState");
		if (!f || f[0] != 0x8B || f[1] != 0xFF) continue;
		for (i = 1; i <= 5; i++) if (f[-i] != 0x90 && f[-i] != 0xCC) fuell = 0;
		if (!fuell) continue;
		if (!VirtualProtect(f - 5, 7, PAGE_EXECUTE_READWRITE, &schutz)) continue;
		g_xi_alt[n] = (XiGet_t)(void *)(f + 2);
		f[-5] = 0xE9;
		*(INT32 *)(f - 4) = (INT32)((unsigned char *)(void *)g_xi_neu[n] - f);
		__atomic_store_n((volatile short *)(void *)f, (short)0xF9EB, __ATOMIC_SEQ_CST);      /* EB F9: kurzer Sprung fünf Byte zurück */
		VirtualProtect(f - 5, 7, schutz, &egal);
		FlushInstructionCache(GetCurrentProcess(), f - 5, 7);
	}
}
#else
static void xinput_haken(void) {}
#endif

/* --- Start -------------------------------------------------------------------------------------- */

/* Vom Starter in einem eigenen Faden gerufen: param zeigt auf den Pfad der Bilddatei (UTF-16, mit 0
 * am Ende, höchstens 1023 Zeichen). Ergebnis ist der Rückgabewert des Fadens:
 * 1 Haken sitzt (Direct3D 9 oder 11) · 2 weder Direct3D 9 noch 11 im Prozess · 3 Haken ging nicht ·
 * 4 Pfad fehlt · 5 lief schon · 6 Direct3D 12 (nicht unterstützt). */
__declspec(dllexport) DWORD WINAPI UzaiOverlayStart(LPVOID param) {
	const wchar_t *pfad = (const wchar_t *)param;
	size_t n = 0;
	DWORD erg, e9, e11;
	if (!pfad) return 4;
	while (n < 1023 && pfad[n]) n++;
	if (n == 0 || n >= 1023) return 4;
	if (InterlockedCompareExchange(&g_gestartet, 1, 0) != 0) return 5;
	memcpy(g_pfad, pfad, n * sizeof(wchar_t));
	g_pfad[n] = 0;
	e9 = haken9();
	e11 = haken_dxgi();
	if (e9 == 1 || e11 == 1) erg = 1;
	else if (e11 == 6) erg = 6;
	else if (e9 == 3 || e11 == 3) erg = 3;
	else erg = 2;
	if (erg == 1) xinput_haken();
	else InterlockedExchange(&g_gestartet, 0);
	return erg;
}

BOOL WINAPI DllMain(HINSTANCE h, DWORD grund, LPVOID r) {
	(void)r;
	if (grund == DLL_PROCESS_ATTACH) DisableThreadLibraryCalls(h);
	return TRUE;
}
