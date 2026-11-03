#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
//
// The native title bar is removed (the Flutter UI draws its own title bar);
// the window keeps its resize borders, snapping and shadow. The Dart side
// drives minimize / maximize / drag / close through the
// "nsl_modeler/window" method channel.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void HandleWindowCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Channel to the Dart side (title bar buttons, close confirmation).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  // The Dart side has registered its handlers (until then a close request is
  // handled natively so a broken Dart side can never trap the window open).
  bool dart_ready_ = false;

  // Dart confirmed the close (after the "save changes?" question).
  bool allow_close_ = false;

  // Last maximized state reported to Dart.
  bool reported_maximized_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
