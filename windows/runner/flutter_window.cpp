#include "flutter_window.h"

#include <windowsx.h>

#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Smallest window size (logical pixels).
constexpr int kMinWidth = 980;
constexpr int kMinHeight = 620;

// Thickness of the resize border (physical pixels) at |hwnd|'s DPI.
int FrameThickness(HWND hwnd) {
  const UINT dpi = GetDpiForWindow(hwnd);
  return GetSystemMetricsForDpi(SM_CYFRAME, dpi) +
         GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // Recalculate the frame now so the native caption is gone from the start
  // (see WM_NCCALCSIZE below).
  SetWindowPos(GetHandle(), nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "nsl_dev/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleWindowCall(call, std::move(result)); });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::HandleWindowCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const HWND hwnd = GetHandle();
  const std::string& name = call.method_name();
  if (name == "ready") {
    dart_ready_ = true;
    result->Success();
  } else if (name == "minimize") {
    ShowWindow(hwnd, SW_MINIMIZE);
    result->Success();
  } else if (name == "toggleMaximize") {
    ShowWindow(hwnd, IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
    result->Success();
  } else if (name == "isMaximized") {
    result->Success(flutter::EncodableValue(IsZoomed(hwnd) != FALSE));
  } else if (name == "startDrag") {
    // Same as grabbing a native title bar.
    ReleaseCapture();
    SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
    result->Success();
  } else if (name == "destroy") {
    allow_close_ = true;
    DestroyWindow(hwnd);
    result->Success();
  } else {
    result->NotImplemented();
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;

    // Client area covers the whole window (no native caption); the left,
    // right and bottom resize borders stay.
    case WM_NCCALCSIZE: {
      if (!wparam) break;
      auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
      const LONG original_top = params->rgrc[0].top;
      const LRESULT r = DefWindowProc(hwnd, message, wparam, lparam);
      if (r != 0) return r;
      params->rgrc[0].top = original_top;
      // A maximized window extends past the screen by the border thickness.
      if (IsZoomed(hwnd)) params->rgrc[0].top += FrameThickness(hwnd);
      return 0;
    }

    // Without a caption the top border would be client area: give the top
    // edge and corners back to the resize handles.
    case WM_NCHITTEST: {
      const LRESULT hit = DefWindowProc(hwnd, message, wparam, lparam);
      if (IsZoomed(hwnd)) return hit;
      if (hit != HTCLIENT && hit != HTLEFT && hit != HTRIGHT) return hit;
      RECT rc;
      GetWindowRect(hwnd, &rc);
      const int y = GET_Y_LPARAM(lparam);
      if (y >= rc.top && y < rc.top + FrameThickness(hwnd)) {
        if (hit == HTLEFT) return HTTOPLEFT;
        if (hit == HTRIGHT) return HTTOPRIGHT;
        return HTTOP;
      }
      return hit;
    }

    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      const double scale = GetDpiForWindow(hwnd) / 96.0;
      info->ptMinTrackSize.x = static_cast<LONG>(kMinWidth * scale);
      info->ptMinTrackSize.y = static_cast<LONG>(kMinHeight * scale);
      return 0;
    }

    // Close button / Alt+F4 / taskbar: let Dart ask "save changes?" first.
    case WM_CLOSE:
      if (dart_ready_ && !allow_close_ && window_channel_) {
        window_channel_->InvokeMethod("closeRequested", nullptr);
        return 0;
      }
      break;

    case WM_SIZE: {
      const LRESULT r = Win32Window::MessageHandler(hwnd, message, wparam, lparam);
      if (window_channel_ && wparam != SIZE_MINIMIZED) {
        const bool maximized = wparam == SIZE_MAXIMIZED;
        if (maximized != reported_maximized_) {
          reported_maximized_ = maximized;
          window_channel_->InvokeMethod(
              "maximized",
              std::make_unique<flutter::EncodableValue>(maximized));
        }
      }
      return r;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
