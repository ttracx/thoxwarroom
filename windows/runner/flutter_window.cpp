#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() = default;

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary
  // surface creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // The runner can complete the first frame before the "show window"
  // callback is registered. ForceRedraw() ensures a frame is pending so the
  // window is shown even if the first frame has already completed.
  flutter_controller_->ForceRedraw();

  // Register Shift+Ctrl+I as a global hotkey for the Spotlight chat bar.
  // Hotkey ID 0x544F5853 = "THOX" in ASCII.
  RegisterHotKey(GetHandle(), 0x544F5853, MOD_SHIFT | MOD_CONTROL,
                 0x49);  // 0x49 = 'I'

  return true;
}

void FlutterWindow::OnDestroy() {
  // Unregister the spotlight hotkey.
  UnregisterHotKey(GetHandle(), 0x544F5853);

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window
  // messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result = flutter_controller_
                                        ->HandleTopLevelWindowProc(
                                            hwnd, message, wparam, lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_HOTKEY:
      // Shift+Ctrl+I → toggle Spotlight chat bar in Dart.
      if (wparam == 0x544F5853 && flutter_controller_ &&
          flutter_controller_->engine()) {
        flutter::MethodChannel<flutter::EncodableValue> channel(
            flutter_controller_->engine()->messenger(),
            "ai.thox.warroom/spotlight",
            &flutter::StandardMethodCodec::GetInstance());
        channel.InvokeMethod("toggleSpotlight", nullptr);
        return 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
