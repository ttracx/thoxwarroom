# Windows ATL/MFC CMake patch

The plugins `flutter_local_notifications_windows` and `flutter_secure_storage_windows` compile against ATL headers but their CMake doesn't add the atlmfc include/lib dir. On stock VS 2022 Build Tools (without MFC workload) this fails with `C1083 atlbase.h / atlstr.h` and `LNK1104 atls.lib`.

Add this block (with adjusted MSVC version) to the end of each plugin's `src/CMakeLists.txt` (local_notifications) or `windows/CMakeLists.txt` (secure_storage):

```cmake
if (NOT DEFINED ENV{VCToolsVersion})
  set(ENV{VCToolsVersion} "14.44.35207")
endif()
foreach(_vsroot
    "C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools"
    "C:/Program Files/Microsoft Visual Studio/2022/Community"
    "C:/Program Files/Microsoft Visual Studio/2022/BuildTools")
  set(_atlmfc_inc "${_vsroot}/VC/Tools/MSVC/$ENV{VCToolsVersion}/atlmfc/include")
  set(_atlmfc_lib "${_vsroot}/VC/Tools/MSVC/$ENV{VCToolsVersion}/atlmfc/lib/x64")
  if (EXISTS "${_atlmfc_inc}")
    target_include_directories(${PLUGIN_NAME} PRIVATE "${_atlmfc_inc}")
    target_link_directories(${PLUGIN_NAME} PRIVATE "${_atlmfc_lib}")
    break()
  endif()
endforeach()
```

Or install the **C++ MFC (x86 & x64)** component via Visual Studio Installer — this patch is only needed for BuildTools-only CI hosts.
