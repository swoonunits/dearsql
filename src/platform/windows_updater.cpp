#if defined(_WIN32)

#include "platform/windows_updater.hpp"
#include "config.hpp"
#include <iostream>
#include <winsparkle.h>

static bool sWinSparkleInitialized = false;

void initializeWinSparkleUpdater() {
    if (sWinSparkleInitialized) {
        return;
    }

    // Set app metadata (used by WinSparkle for the update UI)
    win_sparkle_set_app_details(L"DearSQL", L"DearSQL", L"" APP_VERSION);

    // Point to the same appcast feed used by macOS Sparkle
    win_sparkle_set_appcast_url("https://dearsql.dev/appcast.xml");

    // Set EdDSA public key for verifying signed updates (same key as macOS Sparkle)
    constexpr const char* edKey = SPARKLE_ED_PUBLIC_KEY;
    if (edKey[0] != '\0') {
        win_sparkle_set_eddsa_public_key(edKey);
    }

    // Enable automatic update checks
    win_sparkle_set_automatic_check_for_updates(1);

    // Initialize WinSparkle (starts background update check if enabled)
    win_sparkle_init();
    sWinSparkleInitialized = true;

    std::cout << "WinSparkle updater initialized" << std::endl;
}

void checkForUpdatesWindows() {
    if (!sWinSparkleInitialized) {
        return;
    }
    win_sparkle_check_update_with_ui();
}

void cleanupWinSparkleUpdater() {
    if (!sWinSparkleInitialized) {
        return;
    }
    win_sparkle_cleanup();
    sWinSparkleInitialized = false;
    std::cout << "WinSparkle updater cleaned up" << std::endl;
}

#endif
