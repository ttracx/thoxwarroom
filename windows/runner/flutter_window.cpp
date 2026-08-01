#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() = default;

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }
  RECT frame = GetClientBounds();
  int width = frame.right - frame.left;
  int height = frame.bottom - frame.top;
  // Default to 1200x800 for desktop layout.
  if (width < 1200) {
    width = 1200;
  }
  if (height < 800) {
    height = 800;
  }
  SetSize(width, height);

  // Register Shift+Ctrl+I as a global hotkey for the Spotlight chat bar.
  // Hotkey ID 0x544F5853 = "THOX" in ASCII.
  RegisterHotKey(GetHandle(), 0x544F5853, MOD_SHIFT | MOD_CONTROL, 0x49); // 0x49 = 'I'

  return true;
}

void FlutterWindow::OnDestroy() {
  // Unregister the spotlight hotkey.
  UnregisterHotKey(GetHandle(), 0x544F5853);

  if (engine_) {
    engine_->ShutDown();
  }
  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Handle Shift+Ctrl+I global shortcut for Spotlight on Windows.
  if (message == WM_HOTKEY && wparam == 0x544F5853) {
    if (engine_) {
      auto channel = flutter::MethodChannel<flutter::EncodableValue>(
          engine_->messenger(), "ai.thox.warroom/spotlight",
          &flutter::StandardMethodCodec::GetInstance());
      channel.InvokeMethod("toggleSpotlight", nullptr);
    }
    return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}