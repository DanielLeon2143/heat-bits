// Heat-Bits on the PC: tray icon (closing the window keeps the app running), the
// Ctrl+Shift+Q hotkey from any program, and the small quick-note popup it opens.
// tool/prepare.dart copies this into windows/runner and hooks it into flutter_window.cpp.
#pragma once

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <optional>
#include <string>

// `channel` is "heatbits/window". Sends the app "quickNote" {title, body} and "hotkey" (pressed inside the app).
void HbDesktopInit(HWND main, flutter::MethodChannel<flutter::EncodableValue>* channel);

// Calls from the app: "settings" {closeToTray, hotkey, bg, surface, ink, inkSoft, border, accent, font}, "show",
// "pickFolder" {start, title} (answers with "folderPicked" path).
bool HbDesktopCall(const std::string& method, const flutter::EncodableValue* args);

// Main window messages. `closing` is true once the app has said it's ready to close for real.
std::optional<LRESULT> HbDesktopMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam, bool closing);

void HbDesktopShutdown();
