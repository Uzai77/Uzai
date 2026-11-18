// Nachgebaute discord_partner_sdk (nur die Funktionen, die Uzai nutzt), zum Testen des Helfers.
// Bauen: gcc -shared -fPIC -o <ordner>/libdiscord_partner_sdk.so tests/fake_discord_sdk.c
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

typedef struct { uint8_t *ptr; size_t size; } DStr;
typedef struct { void *ptr; size_t size; } DSpan;
typedef void (*FreeFn)(void *);
typedef void (*StatusCb)(int, int, int, void *);
typedef void (*ResultCb)(void *, void *);
typedef void (*SendCb)(void *, uint64_t, void *);
typedef void (*MessagesCb)(void *, DSpan, void *);
typedef void (*IdCb)(uint64_t, void *);
typedef void (*RelCb)(uint64_t, bool, void *);
typedef void (*LogCb)(DStr, int, void *);
typedef void (*AuthCb)(void *, DStr, DStr, void *);

static int live = 0;          // offene Objekte (Handles, Ergebnisse, Texte)
static int bad_drops = 0;
int Fake_Live(void) { return live; }
int Fake_BadDrops(void) { return bad_drops; }

typedef struct { int kind; int magic; } Obj;
static void *obj(int kind, size_t size) { Obj *o = calloc(1, size); o->kind = kind; o->magic = 4711; live++; return o; }
static void drop(void *p, int kind) {
	Obj *o = p;
	if (!o || o->magic != 4711 || o->kind != kind) { bad_drops++; return; }
	o->magic = 0; live--; free(o);
}
static DStr str(const char *s) { DStr d; d.size = strlen(s); d.ptr = malloc(d.size + 1); memcpy(d.ptr, s, d.size + 1); live++; return d; }
void Discord_Free(void *p) { if (p) { live--; free(p); } }

// --- Ergebnisse ---
typedef struct { Obj o; bool ok; int status; char err[128]; } Result;
static void **result(bool ok, int status, const char *err) {
	Result *r = obj(1, sizeof(Result)); r->ok = ok; r->status = status; strncpy(r->err, err, 127);
	void **box = malloc(sizeof(void *)); *box = r; return box;   // Discord_ClientResult { opaque }
}
void Discord_ClientResult_Drop(void **self) { drop(*self, 1); free(self); }
bool Discord_ClientResult_Successful(void **self) { return ((Result *)*self)->ok; }
void Discord_ClientResult_Error(void **self, DStr *ret) { *ret = str(((Result *)*self)->err); }
int Discord_ClientResult_Status(void **self) { return ((Result *)*self)->status; }

// --- Nutzer und Beziehungen ---
typedef struct { uint64_t id; const char *name; const char *uname; int status; const char *game; int rel; } UserData;
static UserData users[] = {
	{ 1001, "Mira", "mira", 0, "Elden Ring", 1 },
	{ 1002, "Jonas Ü", "jonas", 3, "", 1 },
	{ 1003, "Blockiert", "nope", 1, "", 2 },
};
static UserData me = { 999, "Ich", "ich", 0, "", 0 };
typedef struct { Obj o; UserData *u; } User;
typedef struct { Obj o; UserData *u; } Rel;
typedef struct { Obj o; const char *name; } Act;
static void *user_of(UserData *u) { User *x = obj(2, sizeof(User)); x->u = u; return x; }
void Discord_UserHandle_Drop(void **self) { drop(*self, 2); }
uint64_t Discord_UserHandle_Id(void **self) { return ((User *)*self)->u->id; }
void Discord_UserHandle_DisplayName(void **self, DStr *r) { *r = str(((User *)*self)->u->name); }
void Discord_UserHandle_Username(void **self, DStr *r) { *r = str(((User *)*self)->u->uname); }
void Discord_UserHandle_AvatarUrl(void **self, int a, int b, DStr *r) { char buf[96]; snprintf(buf, 96, "https://cdn.discordapp.com/avatars/%llu/x.png", (unsigned long long)((User *)*self)->u->id); *r = str(buf); }
int Discord_UserHandle_Status(void **self) { return ((User *)*self)->u->status; }
bool Discord_UserHandle_GameActivity(void **self, void **act) {
	UserData *u = ((User *)*self)->u;
	if (!u->game[0]) return false;
	Act *a = obj(3, sizeof(Act)); a->name = u->game; *act = a; return true;
}
void Discord_Activity_Name(void **self, DStr *r) { *r = str(((Act *)*self)->name); }
void Discord_Activity_Drop(void **self) { drop(*self, 3); }
// Art, App und Startzeit (Millisekunden): wie das echte SDK, Zeitangaben als eigenes Objekt.
int Discord_Activity_Type(void **self) { return 0; }
bool Discord_Activity_ApplicationId(void **self, uint64_t *r) { *r = 4242; return true; }
typedef struct { Obj o; uint64_t start; } Ts;
bool Discord_Activity_Timestamps(void **self, void **r) { Ts *t = obj(21, sizeof(Ts)); t->start = 1700000000000ULL; *r = t; return true; }
uint64_t Discord_ActivityTimestamps_Start(void **self) { return ((Ts *)*self)->start; }
void Discord_ActivityTimestamps_Drop(void **self) { drop(*self, 21); }
void Discord_RelationshipHandle_Drop(void **self) { drop(*self, 4); }
int Discord_RelationshipHandle_DiscordRelationshipType(void **self) { return ((Rel *)*self)->u->rel; }
uint64_t Discord_RelationshipHandle_Id(void **self) { return ((Rel *)*self)->u->id; }
bool Discord_RelationshipHandle_User(void **self, void **u) { *u = user_of(((Rel *)*self)->u); return true; }

// --- Nachrichten ---
typedef struct { uint64_t id, author, recipient; uint64_t sent; char text[512]; } MsgData;
static MsgData msgs[64];
static int nmsgs = 0;
typedef struct { Obj o; MsgData *m; } Msg;
static void *msg_of(MsgData *m) { Msg *x = obj(5, sizeof(Msg)); x->m = m; return x; }
void Discord_MessageHandle_Drop(void **self) { drop(*self, 5); }
uint64_t Discord_MessageHandle_Id(void **self) { return ((Msg *)*self)->m->id; }
uint64_t Discord_MessageHandle_AuthorId(void **self) { return ((Msg *)*self)->m->author; }
uint64_t Discord_MessageHandle_RecipientId(void **self) { return ((Msg *)*self)->m->recipient; }
uint64_t Discord_MessageHandle_ChannelId(void **self) { return 5555; }
uint64_t Discord_MessageHandle_SentTimestamp(void **self) { return ((Msg *)*self)->m->sent; }
void Discord_MessageHandle_Content(void **self, DStr *r) { *r = str(((Msg *)*self)->m->text); }
bool Discord_MessageHandle_Lobby(void **self, void **lobby) { return false; }
void Discord_LobbyHandle_Drop(void **self) { drop(*self, 6); }
static MsgData *add_msg(uint64_t author, uint64_t to, const char *text) {
	MsgData *m = &msgs[nmsgs++ % 64];
	m->id = 7000000000000000000ULL + (uint64_t)nmsgs; m->author = author; m->recipient = to;
	m->sent = 1760000000000ULL + (uint64_t)nmsgs * 1000; strncpy(m->text, text, 511);
	return m;
}

// --- Client und verzögerte Rückrufe (wie das echte SDK: erst in RunCallbacks) ---
typedef struct { Obj o; uint64_t app; StatusCb status; IdCb msgcb; RelCb relc, reld; IdCb userup; LogCb log; bool token; bool showing; } Client;
typedef struct { int kind; void *cb; void **res; uint64_t a; uint64_t b; int n; } Pending;
static Pending pend[64];
static int npend = 0;
static Client *cli = NULL;
static void later(int kind, void *cb, void **res, uint64_t a, uint64_t b) { Pending p = { kind, cb, res, a, b, 0 }; pend[npend++] = p; }

void Discord_Client_Init(void **self) { cli = obj(7, sizeof(Client)); *self = cli; }
void Discord_Client_Drop(void **self) { drop(*self, 7); cli = NULL; }
void Discord_Client_SetApplicationId(void **self, uint64_t id) { ((Client *)*self)->app = id; }
int Discord_Client_GetVersionMajor(void) { return 1; }
int Discord_Client_GetVersionMinor(void) { return 9; }
int Discord_Client_GetVersionPatch(void) { return 0; }
void Discord_Client_GetDefaultCommunicationScopes(DStr *r) { *r = str("openid sdk.social_layer"); }
void Discord_Client_SetStatusChangedCallback(void **s, StatusCb cb, FreeFn f, void *ud) { cli->status = cb; }
void Discord_Client_SetMessageCreatedCallback(void **s, IdCb cb, FreeFn f, void *ud) { cli->msgcb = cb; }
void Discord_Client_SetRelationshipCreatedCallback(void **s, RelCb cb, FreeFn f, void *ud) { cli->relc = cb; }
void Discord_Client_SetRelationshipDeletedCallback(void **s, RelCb cb, FreeFn f, void *ud) { cli->reld = cb; }
void Discord_Client_SetUserUpdatedCallback(void **s, IdCb cb, FreeFn f, void *ud) { cli->userup = cb; }
void Discord_Client_AddLogCallback(void **s, LogCb cb, FreeFn f, void *ud, int sev) { cli->log = cb; }
void Discord_Client_SetShowingChat(void **s, bool on) { cli->showing = on; }
// Eigener Status (Guide → dein Profil): 0 Online, 3 Abwesend, 4 Nicht stören, 5 Unsichtbar.
void Discord_Client_SetOnlineStatus(void **s, int status, ResultCb cb, FreeFn f, void *ud) {
	bool ok = status == 0 || status == 3 || status == 4 || status == 5;
	if (ok) me.status = status;
	later(1, cb, result(ok, ok ? 200 : 400, ok ? "" : "invalid status"), 0, 0);
}
bool Fake_Showing(void) { return cli && cli->showing; }

void Discord_Client_UpdateToken(void **s, int type, DStr token, ResultCb cb, FreeFn f, void *ud) {
	bool good = type == 1 && token.size == 4 && memcmp(token.ptr, "good", 4) == 0;
	cli->token = good;
	later(1, cb, result(good, good ? 200 : 401, good ? "" : "invalid token"), 0, 0);
}
void Discord_Client_Connect(void **s) { later(2, NULL, NULL, 1, 0); later(2, NULL, NULL, 3, 0); }
void Discord_Client_Disconnect(void **s) { later(2, NULL, NULL, 0, 0); }
bool Discord_Client_GetCurrentUserV2(void **s, void **u) { if (!cli->token) return false; *u = user_of(&me); return true; }
bool Discord_Client_GetUser(void **s, uint64_t id, void **u) { return false; }
void Discord_Client_GetRelationships(void **s, DSpan *ret) {
	int n = sizeof(users) / sizeof(users[0]);
	void **arr = malloc(sizeof(void *) * n); live++;
	for (int i = 0; i < n; i++) { Rel *r = obj(4, sizeof(Rel)); r->u = &users[i]; arr[i] = r; }
	ret->ptr = arr; ret->size = n;
}
void Discord_Client_SendUserMessage(void **s, uint64_t to, DStr content, SendCb cb, FreeFn f, void *ud) {
	char text[512] = { 0 };
	memcpy(text, content.ptr, content.size < 511 ? content.size : 511);
	if (strcmp(text, "fail") == 0 || to == 1003) { later(3, cb, result(false, 403, "Cannot send messages to this user"), 0, 0); return; }
	// Probe „kommt online“: Jonas ist danach online und spielt; das SDK meldet es wie Discord
	// mehrfach hintereinander (UserUpdated), ohne Nachricht.
	if (strcmp(text, "!online") == 0) {
		users[1].status = 0; users[1].game = "Hades";
		later(3, cb, result(true, 200, ""), 0, 0);
		for (int i = 0; i < 5; i++) later(7, NULL, NULL, users[1].id, 0);
		return;
	}
	MsgData *m = add_msg(999, to, text);
	later(3, cb, result(true, 200, ""), m->id, 0);
	later(4, NULL, NULL, m->id, 0);                         // eigene Nachricht kommt auch als Ereignis
	MsgData *r = add_msg(to, 999, "Antwort auf: ");
	strncat(r->text, text, 400);
	later(4, NULL, NULL, r->id, 0);                         // und gleich eine Antwort
}
void Discord_Client_GetUserMessagesWithLimit(void **s, uint64_t with, int limit, MessagesCb cb, FreeFn f, void *ud) {
	Pending p = { 5, cb, result(true, 200, ""), with, 0, limit }; pend[npend++] = p;
}
bool Discord_Client_GetMessageHandle(void **s, uint64_t id, void **ret) {
	for (int i = 0; i < nmsgs && i < 64; i++) if (msgs[i].id == id) { *ret = msg_of(&msgs[i]); return true; }
	return false;
}

void Discord_RunCallbacks(void) {
	int n = npend;
	Pending copy[64];
	memcpy(copy, pend, sizeof(Pending) * n);
	npend = 0;
	for (int i = 0; i < n; i++) {
		Pending *p = &copy[i];
		switch (p->kind) {
		case 1: ((ResultCb)p->cb)(p->res, NULL); break;
		case 2: if (cli && cli->status) cli->status((int)p->a, 0, 0, NULL); break;
		case 3: ((SendCb)p->cb)(p->res, p->a, NULL); break;
		case 4: if (cli && cli->msgcb) cli->msgcb(p->a, NULL); break;
		case 7: if (cli && cli->userup) cli->userup(p->a, NULL); break;
		case 6: {
			DStr code = str("code-abc"), red = str("http://127.0.0.1/callback");
			((AuthCb)p->cb)(p->res, code, red, NULL);
			break;
		}
		case 5: {
			void **arr = malloc(sizeof(void *) * 64); live++;
			int k = 0;
			for (int j = nmsgs - 1; j >= 0 && k < (p->n > 0 ? p->n : 200); j--) {
				MsgData *m = &msgs[j];
				if (m->author == p->a || m->recipient == p->a) arr[k++] = msg_of(m);
			}
			DSpan sp = { arr, (size_t)k };
			((MessagesCb)p->cb)(p->res, sp, NULL);
			break;
		}
		}
	}
	if (cli && cli->log && n > 0) { static int once = 0; if (!once++) { DStr d = str("Fake-SDK: \"Hallo\"\nZeile 2"); cli->log(d, 3, NULL); } }
}

// Für den Rückfall-Weg (Freigabe über das SDK)
typedef struct { Obj o; } Simple;
void Discord_Client_CreateAuthorizationCodeVerifier(void **s, void **v) { *v = obj(8, sizeof(Simple)); }
void Discord_AuthorizationCodeVerifier_Verifier(void **s, DStr *r) { *r = str("verifier-123"); }
void Discord_AuthorizationCodeVerifier_Challenge(void **s, void **c) { *c = obj(9, sizeof(Simple)); }
void Discord_AuthorizationCodeVerifier_Drop(void **s) { drop(*s, 8); }
void Discord_AuthorizationCodeChallenge_Drop(void **s) { drop(*s, 9); }
void Discord_AuthorizationArgs_Init(void **s) { *s = obj(10, sizeof(Simple)); }
void Discord_AuthorizationArgs_Drop(void **s) { drop(*s, 10); }
void Discord_AuthorizationArgs_SetClientId(void **s, uint64_t id) {}
void Discord_AuthorizationArgs_SetScopes(void **s, DStr scopes) {}
void Discord_AuthorizationArgs_SetCodeChallenge(void **s, void **c) {}
void Discord_Client_Authorize(void **s, void **args, AuthCb cb, FreeFn f, void *ud) {
	Pending p = { 6, cb, result(true, 200, ""), 0, 0, 0 };
	pend[npend++] = p;
}
