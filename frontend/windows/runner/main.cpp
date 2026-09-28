#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shobjidl_core.h>
#include <string>

#include "build_identity.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

// The generated application identity separates development and release installs.
class SingleInstance {
 public:
  SingleInstance() {
    const std::wstring name = std::wstring(L"Local\\") +
                              HARUKA_APP_USER_MODEL_ID + L".primary";
    handle_ = ::CreateMutexW(nullptr, FALSE, name.c_str());
    if (handle_) existing_ = ::GetLastError() == ERROR_ALREADY_EXISTS;
  }
  ~SingleInstance() { if (handle_) ::CloseHandle(handle_); }
  bool valid() const { return handle_ != nullptr; }
  bool existing() const { return existing_; }

  static bool ActivateExistingWindow() {
    // The first process may still be starting Flutter when the second arrives.
    for (int attempt = 0; attempt < 100; ++attempt) {
      HWND target = nullptr;
      ::EnumWindows([](HWND window, LPARAM result) -> BOOL {
        if (::GetPropW(window, HARUKA_APP_USER_MODEL_ID)) {
          *reinterpret_cast<HWND*>(result) = window;
          return FALSE;
        }
        return TRUE;
      }, reinterpret_cast<LPARAM>(&target));
      if (target) {
        ::ShowWindow(target, ::IsIconic(target) ? SW_RESTORE : SW_SHOW);
        if (!::SetForegroundWindow(target)) {
          FLASHWINFO info{sizeof(FLASHWINFO), target, FLASHW_TRAY, 3, 0};
          ::FlashWindowEx(&info);
        }
        return true;
      }
      ::Sleep(50);
    }
    return false;
  }

 private:
  HANDLE handle_ = nullptr;
  bool existing_ = false;
};

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  SingleInstance owner;
  if (!owner.valid() || (owner.existing() && !SingleInstance::ActivateExistingWindow())) {
    ::MessageBoxW(nullptr, L"\u65e0\u6cd5\u6253\u5f00\u5df2\u6709\u7a97\u53e3\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5\u3002", HARUKA_WINDOW_TITLE,
                  MB_OK | MB_ICONWARNING);
    return EXIT_FAILURE;
  }
  if (owner.existing()) return EXIT_SUCCESS;
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  ::SetCurrentProcessExplicitAppUserModelID(HARUKA_APP_USER_MODEL_ID);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(HARUKA_WINDOW_TITLE, origin, size)) {
    return EXIT_FAILURE;
  }
  if (!::SetPropW(window.GetHandle(), HARUKA_APP_USER_MODEL_ID,
                  reinterpret_cast<HANDLE>(1))) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
