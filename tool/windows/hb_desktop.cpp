#include "hb_desktop.h"

#include <dwmapi.h>
#include <shellapi.h>
#include <shobjidl.h>

#include <memory>

#include "resource.h"

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

const UINT kTrayMsg = WM_APP + 0x48;
const UINT kTrayId = 1;
const int kHotkeyId = 0x4851;
const UINT kMenuOpen = 1, kMenuNote = 2, kMenuQuit = 3;
const wchar_t kPopupClass[] = L"HeatBitsQuickNote";

HWND g_main = nullptr;
flutter::MethodChannel<EncodableValue>* g_channel = nullptr;
UINT g_taskbarCreated = 0, g_showMsg = 0;

bool g_closeToTray = true, g_hotkeyOn = true;
bool g_trayAdded = false, g_hotkeyAdded = false, g_quitting = false;

// the page's theme (Settings -> Appearance), sent by the app whenever it changes
COLORREF g_surface = RGB(0x1D, 0x1D, 0x1D), g_field = RGB(0x15, 0x15, 0x15), g_ink = RGB(0xEC, 0xEC, 0xEC),
         g_soft = RGB(0x9E, 0x9E, 0x9E), g_border = RGB(0x3E, 0x3E, 0x3E), g_accent = RGB(0xE0, 0x63, 0x2F);
std::wstring g_fontName = L"Segoe UI";

// the popup
HWND g_popup = nullptr, g_title = nullptr, g_body = nullptr;
WNDPROC g_editProc = nullptr;
HFONT g_fHead = nullptr, g_fText = nullptr, g_fSmall = nullptr;
HBRUSH g_fieldBrush = nullptr;
bool g_popupClosing = false, g_paintBorder = false;
RECT g_titleBox{}, g_bodyBox{};
int g_dpi = 96;

int S(int v) { return MulDiv(v, g_dpi, 96); }

std::wstring Widen(const std::string& s) {
  if (s.empty()) return L"";
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
  std::wstring w(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), w.data(), n);
  return w;
}

std::string Narrow(const std::wstring& w) {
  if (w.empty()) return "";
  int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), nullptr, 0, nullptr, nullptr);
  std::string s(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), s.data(), n, nullptr, nullptr);
  return s;
}

const EncodableValue* Field(const EncodableMap& m, const char* key) {
  auto it = m.find(EncodableValue(std::string(key)));
  return it == m.end() ? nullptr : &it->second;
}

void ReadColor(const EncodableMap& m, const char* key, COLORREF& out) {
  auto v = Field(m, key);
  auto s = v ? std::get_if<std::string>(v) : nullptr;
  if (!s || s->size() != 7 || (*s)[0] != '#') return;
  char* end = nullptr;
  unsigned long c = strtoul(s->c_str() + 1, &end, 16);
  if (end && *end == '\0') out = RGB((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF);
}

int CALLBACK FontFound(const LOGFONTW*, const TEXTMETRICW*, DWORD, LPARAM found) {
  *reinterpret_cast<bool*>(found) = true;
  return 0;
}

// the page's fonts are often web fonts that Windows doesn't have: fall back to Segoe UI
bool FontInstalled(const std::wstring& name) {
  if (name.empty() || name.size() >= LF_FACESIZE) return false;
  LOGFONTW lf{};
  lf.lfCharSet = DEFAULT_CHARSET;
  wcscpy_s(lf.lfFaceName, name.c_str());
  bool found = false;
  HDC dc = GetDC(nullptr);
  EnumFontFamiliesExW(dc, &lf, FontFound, reinterpret_cast<LPARAM>(&found), 0);
  ReleaseDC(nullptr, dc);
  return found;
}

// ---- tray icon ----

void AddTray() {
  if (g_trayAdded || !g_main) return;
  NOTIFYICONDATAW nid{sizeof(nid)};
  nid.hWnd = g_main;
  nid.uID = kTrayId;
  nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP;
  nid.uCallbackMessage = kTrayMsg;
  nid.hIcon = (HICON)LoadImageW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
                                GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), 0);
  wcscpy_s(nid.szTip, L"Heat-Bits");
  if (Shell_NotifyIconW(NIM_ADD, &nid)) {
    nid.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &nid);
    g_trayAdded = true;
  }
}

void RemoveTray() {
  if (!g_trayAdded) return;
  NOTIFYICONDATAW nid{sizeof(nid)};
  nid.hWnd = g_main;
  nid.uID = kTrayId;
  Shell_NotifyIconW(NIM_DELETE, &nid);
  g_trayAdded = false;
}

void UpdateHotkey() {
  if (!g_main) return;
  if (g_hotkeyOn && !g_hotkeyAdded) {
    // fails quietly if another program already uses Ctrl+Shift+Q; the page's own shortcut still works
    g_hotkeyAdded = RegisterHotKey(g_main, kHotkeyId, MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, 'Q') != 0;
  } else if (!g_hotkeyOn && g_hotkeyAdded) {
    UnregisterHotKey(g_main, kHotkeyId);
    g_hotkeyAdded = false;
  }
}

// Windows only lets the program the user is busy with bring a window forward; borrow its input queue
void ForceForeground(HWND hwnd) {
  SetForegroundWindow(hwnd);
  if (GetForegroundWindow() == hwnd) return;
  HWND fg = GetForegroundWindow();
  DWORD fgThread = fg ? GetWindowThreadProcessId(fg, nullptr) : 0, me = GetCurrentThreadId();
  if (fgThread && fgThread != me && AttachThreadInput(me, fgThread, TRUE)) {
    BringWindowToTop(hwnd);
    SetForegroundWindow(hwnd);
    AttachThreadInput(me, fgThread, FALSE);
  }
}

void ShowMain() {
  if (!g_main) return;
  ShowWindow(g_main, IsIconic(g_main) ? SW_RESTORE : SW_SHOW);
  ForceForeground(g_main);
}

void ShowPopup();

void TrayMenu() {
  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, kMenuOpen, L"Open Heat-Bits");
  AppendMenuW(menu, MF_STRING, kMenuNote, g_hotkeyAdded ? L"New quick note\tCtrl+Shift+Q" : L"New quick note");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuQuit, L"Quit Heat-Bits");
  SetMenuDefaultItem(menu, kMenuOpen, FALSE);
  POINT pt;
  GetCursorPos(&pt);
  SetForegroundWindow(g_main);  // so the menu closes when you click elsewhere
  UINT cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, pt.x, pt.y, 0, g_main, nullptr);
  PostMessageW(g_main, WM_NULL, 0, 0);
  DestroyMenu(menu);
  if (cmd == kMenuOpen) ShowMain();
  if (cmd == kMenuNote) ShowPopup();
  if (cmd == kMenuQuit) {
    g_quitting = true;
    PostMessageW(g_main, WM_CLOSE, 0, 0);  // the normal close: the app saves first
  }
}

// ---- the quick-note popup ----

std::wstring TextOf(HWND edit) {
  int n = GetWindowTextLengthW(edit);
  std::wstring w(n + 1, L'\0');
  GetWindowTextW(edit, w.data(), n + 1);
  w.resize(n);
  return w;
}

std::wstring Trimmed(const std::wstring& s) {
  size_t a = s.find_first_not_of(L" \t\r\n"), b = s.find_last_not_of(L" \t\r\n");
  return a == std::wstring::npos ? L"" : s.substr(a, b - a + 1);
}

void FreePopupGdi() {
  for (HFONT* f : {&g_fHead, &g_fText, &g_fSmall}) {
    if (*f) DeleteObject(*f);
    *f = nullptr;
  }
  if (g_fieldBrush) DeleteObject(g_fieldBrush);
  g_fieldBrush = nullptr;
}

void ClosePopup(bool save) {
  if (!g_popup || g_popupClosing) return;
  g_popupClosing = true;
  if (save && g_channel) {
    std::wstring title = Trimmed(TextOf(g_title)), body = TextOf(g_body), clean;
    for (wchar_t c : body)
      if (c != L'\r') clean += c;  // the edit box writes \r\n; notes use \n
    clean = Trimmed(clean).empty() ? L"" : clean;
    if (!title.empty() || !clean.empty()) {
      g_channel->InvokeMethod("quickNote", std::make_unique<EncodableValue>(EncodableMap{
                                               {EncodableValue("title"), EncodableValue(Narrow(title))},
                                               {EncodableValue("body"), EncodableValue(Narrow(clean))},
                                           }));
    }
  }
  HWND p = g_popup;
  g_popup = g_title = g_body = nullptr;
  DestroyWindow(p);
  FreePopupGdi();
  g_popupClosing = false;
}

LRESULT CALLBACK EditProc(HWND h, UINT m, WPARAM w, LPARAM l) {
  bool body = h == g_body;
  bool shift = GetKeyState(VK_SHIFT) < 0, ctrl = GetKeyState(VK_CONTROL) < 0;
  if (m == WM_KEYDOWN) {
    if (w == VK_ESCAPE) {
      ClosePopup(false);
      return 0;
    }
    if (w == VK_RETURN && !(body && shift)) {
      if (body) ClosePopup(true);
      else SetFocus(g_body);  // Enter in the title goes on to the note
      return 0;
    }
    if (w == VK_TAB) {
      SetFocus(body ? g_title : g_body);
      return 0;
    }
    if (ctrl && w == 'A') {
      SendMessageW(h, EM_SETSEL, 0, -1);
      return 0;
    }
  }
  if (m == WM_CHAR) {
    // the keys handled above would otherwise beep or type a stray character
    if (w == VK_ESCAPE || w == L'\t' || w == 1 || w == 0x7F) return 0;
    if ((w == L'\r' || w == L'\n') && !(body && shift)) return 0;
  }
  return CallWindowProcW(g_editProc, h, m, w, l);
}

void PaintPopup(HWND hwnd) {
  PAINTSTRUCT ps;
  HDC dc = BeginPaint(hwnd, &ps);
  RECT rc;
  GetClientRect(hwnd, &rc);
  // draw off screen first, so typing doesn't flicker
  HDC mem = CreateCompatibleDC(dc);
  HBITMAP bmp = CreateCompatibleBitmap(dc, rc.right, rc.bottom);
  HGDIOBJ oldBmp = SelectObject(mem, bmp);

  HBRUSH bg = CreateSolidBrush(g_surface);
  FillRect(mem, &rc, bg);
  DeleteObject(bg);
  SetBkMode(mem, TRANSPARENT);

  // a strip of the app colour along the top
  RECT strip{0, 0, rc.right, S(4)};
  HBRUSH acc = CreateSolidBrush(g_accent);
  FillRect(mem, &strip, acc);

  int pad = S(24);
  RECT dot{pad, S(30), pad + S(10), S(40)};
  HGDIOBJ oldBrush = SelectObject(mem, acc);
  HGDIOBJ oldPen = SelectObject(mem, GetStockObject(NULL_PEN));
  Ellipse(mem, dot.left, dot.top, dot.right, dot.bottom);

  SelectObject(mem, g_fHead);
  SetTextColor(mem, g_ink);
  RECT head{pad + S(18), S(20), rc.right - pad, S(50)};
  DrawTextW(mem, L"Quick note", -1, &head, DT_SINGLELINE | DT_VCENTER | DT_LEFT);

  SelectObject(mem, g_fSmall);
  SetTextColor(mem, g_soft);
  RECT lt{pad, g_titleBox.top - S(22), rc.right - pad, g_titleBox.top - S(4)};
  DrawTextW(mem, L"Title", -1, &lt, DT_SINGLELINE | DT_BOTTOM | DT_LEFT);
  RECT lb{pad, g_bodyBox.top - S(22), rc.right - pad, g_bodyBox.top - S(4)};
  DrawTextW(mem, L"Note", -1, &lb, DT_SINGLELINE | DT_BOTTOM | DT_LEFT);
  RECT foot{pad, g_bodyBox.bottom + S(8), rc.right - pad, rc.bottom - S(8)};
  DrawTextW(mem, L"Enter saves  \u00B7  Shift+Enter new line  \u00B7  Esc cancels", -1, &foot,
            DT_SINGLELINE | DT_VCENTER | DT_CENTER);

  HWND focus = GetFocus();
  HBRUSH field = CreateSolidBrush(g_field);
  SelectObject(mem, field);
  for (int i = 0; i < 2; i++) {
    const RECT& b = i == 0 ? g_titleBox : g_bodyBox;
    bool on = focus == (i == 0 ? g_title : g_body);
    HPEN pen = CreatePen(PS_SOLID, on ? S(2) : 1, on ? g_accent : g_border);
    SelectObject(mem, pen);
    RoundRect(mem, b.left, b.top, b.right, b.bottom, S(10), S(10));
    SelectObject(mem, GetStockObject(NULL_PEN));
    DeleteObject(pen);
  }
  if (g_paintBorder) {  // Windows 10 has no coloured window border: draw one
    HPEN pen = CreatePen(PS_SOLID, 1, g_accent);
    SelectObject(mem, pen);
    SelectObject(mem, GetStockObject(NULL_BRUSH));
    Rectangle(mem, 0, 0, rc.right, rc.bottom);
    SelectObject(mem, GetStockObject(NULL_PEN));
    DeleteObject(pen);
  }
  SelectObject(mem, oldBrush);
  SelectObject(mem, oldPen);
  DeleteObject(field);
  DeleteObject(acc);

  BitBlt(dc, 0, 0, rc.right, rc.bottom, mem, 0, 0, SRCCOPY);
  SelectObject(mem, oldBmp);
  DeleteObject(bmp);
  DeleteDC(mem);
  EndPaint(hwnd, &ps);
}

LRESULT CALLBACK PopupProc(HWND hwnd, UINT m, WPARAM w, LPARAM l) {
  switch (m) {
    case WM_PAINT:
      PaintPopup(hwnd);
      return 0;
    case WM_ERASEBKGND:
      return 1;
    case WM_CTLCOLOREDIT:
      SetTextColor((HDC)w, g_ink);
      SetBkColor((HDC)w, g_field);
      return (LRESULT)g_fieldBrush;
    case WM_COMMAND:
      // the focused box gets an accent outline
      if (HIWORD(w) == EN_SETFOCUS || HIWORD(w) == EN_KILLFOCUS) InvalidateRect(hwnd, nullptr, FALSE);
      break;
    case WM_NCHITTEST: {
      // drag the popup by any empty spot
      LRESULT hit = DefWindowProcW(hwnd, m, w, l);
      return hit == HTCLIENT ? HTCAPTION : hit;
    }
    case WM_LBUTTONDOWN:
      SetFocus(g_title);
      return 0;
    case WM_ACTIVATE:
      if (LOWORD(w) == WA_INACTIVE) {
        // clicked away: an empty popup goes; one with writing in it waits for Enter or Esc
        if (g_popup && !g_popupClosing && TextOf(g_title).empty() && TextOf(g_body).empty())
          PostMessageW(hwnd, WM_CLOSE, 0, 0);
      } else if (g_title) {
        HWND f = GetFocus();
        if (f != g_title && f != g_body) SetFocus(g_title);
      }
      return 0;
    case WM_CLOSE:
      if (hwnd == g_popup) ClosePopup(false);
      return 0;
  }
  return DefWindowProcW(hwnd, m, w, l);
}

void ShowPopup() {
  if (g_popup) {
    ForceForeground(g_popup);
    SetFocus(g_title);
    return;
  }
  HINSTANCE inst = GetModuleHandleW(nullptr);
  static bool registered = false;
  if (!registered) {
    WNDCLASSEXW wc{sizeof(wc)};
    wc.style = CS_DROPSHADOW;
    wc.lpfnWndProc = PopupProc;
    wc.hInstance = inst;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hIcon = LoadIconW(inst, MAKEINTRESOURCEW(IDI_APP_ICON));
    wc.lpszClassName = kPopupClass;
    registered = RegisterClassExW(&wc) != 0;
  }
  // the middle of the screen the pointer is on
  POINT pt;
  GetCursorPos(&pt);
  MONITORINFO mi{sizeof(mi)};
  GetMonitorInfoW(MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST), &mi);
  RECT work = mi.rcWork;
  g_popup = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, kPopupClass, L"Quick note", WS_POPUP, work.left,
                            work.top, 100, 100, nullptr, nullptr, inst, nullptr);
  if (!g_popup) return;
  g_dpi = (int)GetDpiForWindow(g_popup);
  if (g_dpi <= 0) g_dpi = 96;
  int w = S(460), h = S(460);
  SetWindowPos(g_popup, HWND_TOPMOST, work.left + (work.right - work.left - w) / 2,
               work.top + (work.bottom - work.top - h) / 2, w, h, SWP_NOACTIVATE);

  std::wstring face = FontInstalled(g_fontName) ? g_fontName : L"Segoe UI";
  auto font = [&](int px, int weight) {
    return CreateFontW(-S(px), 0, 0, 0, weight, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                       CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, face.c_str());
  };
  g_fHead = font(20, FW_SEMIBOLD);
  g_fText = font(15, FW_NORMAL);
  g_fSmall = font(12, FW_NORMAL);
  g_fieldBrush = CreateSolidBrush(g_field);

  int pad = S(24);
  g_titleBox = {pad, S(84), w - pad, S(84) + S(42)};
  g_bodyBox = {pad, g_titleBox.bottom + S(34), w - pad, h - S(52)};
  int lineH = S(22), in = S(12);
  g_title = CreateWindowExW(0, L"EDIT", L"", WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL, g_titleBox.left + in,
                            g_titleBox.top + (S(42) - lineH) / 2, g_titleBox.right - g_titleBox.left - 2 * in, lineH,
                            g_popup, nullptr, inst, nullptr);
  g_body = CreateWindowExW(0, L"EDIT", L"", WS_CHILD | WS_VISIBLE | ES_MULTILINE | ES_AUTOVSCROLL,
                           g_bodyBox.left + in, g_bodyBox.top + S(10), g_bodyBox.right - g_bodyBox.left - 2 * in,
                           g_bodyBox.bottom - g_bodyBox.top - S(20), g_popup, nullptr, inst, nullptr);
  for (HWND e : {g_title, g_body}) {
    SendMessageW(e, WM_SETFONT, (WPARAM)g_fText, TRUE);
    SendMessageW(e, EM_SETMARGINS, EC_LEFTMARGIN | EC_RIGHTMARGIN, 0);
    g_editProc = (WNDPROC)SetWindowLongPtrW(e, GWLP_WNDPROC, (LONG_PTR)EditProc);
  }
  SendMessageW(g_title, EM_SETLIMITTEXT, 200, 0);

  // Windows 11: round corners and a border in the app colour
  DWORD round = 2;  // DWMWCP_ROUND
  DwmSetWindowAttribute(g_popup, 33 /* DWMWA_WINDOW_CORNER_PREFERENCE */, &round, sizeof(round));
  COLORREF border = g_accent;
  g_paintBorder = FAILED(DwmSetWindowAttribute(g_popup, 34 /* DWMWA_BORDER_COLOR */, &border, sizeof(border)));

  ShowWindow(g_popup, SW_SHOW);
  ForceForeground(g_popup);
  SetFocus(g_title);
}

void OnHotkey() {
  if (g_popup) {
    ShowPopup();
    return;
  }
  // inside Heat-Bits the page makes the note itself, as before; anywhere else, the popup
  HWND fg = GetForegroundWindow();
  if (g_channel && fg && IsWindowVisible(g_main) && GetAncestor(fg, GA_ROOTOWNER) == g_main) {
    g_channel->InvokeMethod("hotkey", nullptr);
  } else {
    ShowPopup();
  }
}

}  // namespace

void HbDesktopInit(HWND main, flutter::MethodChannel<EncodableValue>* channel) {
  g_main = main;
  g_channel = channel;
  g_taskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");
  g_showMsg = RegisterWindowMessageW(L"HeatBits.Show");
  // a second copy of Heat-Bits asks this one to show itself (main.cpp) and then quits
  ChangeWindowMessageFilterEx(main, g_showMsg, MSGFLT_ALLOW, nullptr);
  ChangeWindowMessageFilterEx(main, g_taskbarCreated, MSGFLT_ALLOW, nullptr);
  if (g_closeToTray) AddTray();
  UpdateHotkey();
}

// Windows' own folder picker, opened at `start` (Settings -> Data & storage, and the notes import/export).
// The answer goes back as "folderPicked" (the path, or "" when cancelled).
static void PickFolder(const std::wstring& start, const std::wstring& title) {
  std::wstring picked;
  IFileOpenDialog* dlg = nullptr;
  if (SUCCEEDED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dlg)))) {
    DWORD opts = 0;
    dlg->GetOptions(&opts);
    dlg->SetOptions(opts | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST);
    if (!title.empty()) dlg->SetTitle(title.c_str());
    IShellItem* at = nullptr;
    if (!start.empty() && SUCCEEDED(SHCreateItemFromParsingName(start.c_str(), nullptr, IID_PPV_ARGS(&at)))) {
      dlg->SetFolder(at);
      at->Release();
    }
    if (SUCCEEDED(dlg->Show(g_main))) {
      IShellItem* item = nullptr;
      if (SUCCEEDED(dlg->GetResult(&item))) {
        PWSTR path = nullptr;
        if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) {
          picked = path;
          CoTaskMemFree(path);
        }
        item->Release();
      }
    }
    dlg->Release();
  }
  if (g_channel) g_channel->InvokeMethod("folderPicked", std::make_unique<EncodableValue>(Narrow(picked)));
}

bool HbDesktopCall(const std::string& method, const EncodableValue* args) {
  if (method == "show") {
    ShowMain();
    return true;
  }
  if (method == "pickFolder") {
    std::wstring start, title;
    if (auto m = args ? std::get_if<EncodableMap>(args) : nullptr) {
      if (auto v = Field(*m, "start"))
        if (auto str = std::get_if<std::string>(v)) start = Widen(*str);
      if (auto v = Field(*m, "title"))
        if (auto str = std::get_if<std::string>(v)) title = Widen(*str);
    }
    PickFolder(start, title);
    return true;
  }
  if (method != "settings") return false;
  auto m = args ? std::get_if<EncodableMap>(args) : nullptr;
  if (!m) return true;
  if (auto v = Field(*m, "closeToTray"))
    if (auto b = std::get_if<bool>(v)) g_closeToTray = *b;
  if (auto v = Field(*m, "hotkey"))
    if (auto b = std::get_if<bool>(v)) g_hotkeyOn = *b;
  ReadColor(*m, "surface", g_surface);
  ReadColor(*m, "bg", g_field);
  ReadColor(*m, "ink", g_ink);
  ReadColor(*m, "inkSoft", g_soft);
  ReadColor(*m, "border", g_border);
  ReadColor(*m, "accent", g_accent);
  if (auto v = Field(*m, "font"))
    if (auto s = std::get_if<std::string>(v)) g_fontName = Widen(*s);
  if (g_closeToTray) AddTray();
  else RemoveTray();
  UpdateHotkey();
  return true;
}

std::optional<LRESULT> HbDesktopMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam, bool closing) {
  if (message == WM_CLOSE && !closing && !g_quitting && g_closeToTray && g_trayAdded) {
    // like Discord: the X hides the window and Heat-Bits keeps running in the tray.
    // Minimize first: WebView2 keeps an invisible input window of its own over the app that only follows
    // the window's position, so a plain hide leaves it on the desktop swallowing clicks. ShowMain restores.
    ShowWindow(hwnd, SW_MINIMIZE);
    ShowWindow(hwnd, SW_HIDE);
    return 0;
  }
  if (message == WM_HOTKEY && wparam == kHotkeyId) {
    OnHotkey();
    return 0;
  }
  if (message == kTrayMsg) {
    switch (LOWORD(lparam)) {
      case NIN_SELECT:
      case NIN_KEYSELECT:
        ShowMain();
        break;
      case WM_CONTEXTMENU:
        TrayMenu();
        break;
    }
    return 0;
  }
  if (g_taskbarCreated && message == g_taskbarCreated) {  // Explorer restarted: put the icon back
    g_trayAdded = false;
    if (g_closeToTray) AddTray();
    return 0;
  }
  if (g_showMsg && message == g_showMsg) {
    ShowMain();
    return 0;
  }
  return std::nullopt;
}

void HbDesktopShutdown() {
  if (g_popup) ClosePopup(false);
  RemoveTray();
  if (g_hotkeyAdded) UnregisterHotKey(g_main, kHotkeyId);
  g_hotkeyAdded = false;
  g_channel = nullptr;
}
