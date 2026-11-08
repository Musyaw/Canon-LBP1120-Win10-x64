#include "print_server.hpp"
#include <algorithm>
#include <chrono>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <mutex>
#include <thread>
#include <vector>
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>

namespace fs = std::filesystem;

namespace {
std::mutex g_printMutex;

bool recvAll(SOCKET client, std::vector<char>& buffer) {
    char chunk[65536];
    for (;;) {
        const int n = recv(client, chunk, static_cast<int>(sizeof(chunk)), 0);
        if (n > 0) {
            buffer.insert(buffer.end(), chunk, chunk + n);
        } else if (n == 0) {
            return true;
        } else {
            const int err = WSAGetLastError();
            if (err == WSAEINTR) {
                continue;
            }
            std::cerr << "recv failed: " << err << '\n';
            return false;
        }
    }
}

void handleJob(const std::vector<char>& data, const PrintOptions& options) {
    if (data.size() < 32) {
        std::cerr << "Job too small, ignored\n";
        return;
    }

    const fs::path gs = FindGhostscriptExecutable();
    if (gs.empty()) {
        std::cerr << "Ghostscript not found. Install from https://ghostscript.com/releases/gsdnld.html\n"
                     "Or set CAPTWIN_GS to gswin64c.exe path\n";
        return;
    }

    const fs::path workDir = fs::temp_directory_path()
        / ("captwin-job-" + std::to_string(GetCurrentProcessId()) + "-"
           + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count() % 1000000));
    fs::create_directories(workDir);

    const fs::path psFile = workDir / "job.ps";
    {
        std::ofstream out(psFile, std::ios::binary);
        out.write(data.data(), static_cast<std::streamsize>(data.size()));
    }

    std::cerr << "Received print job: " << data.size() << " bytes\n";

    try {
        const auto pages = ConvertPostScriptToPbmPages(gs, psFile, workDir, 600);
        std::lock_guard lock(g_printMutex);
        for (const auto& page : pages) {
            std::cerr << "Printing " << page.filename().string() << "...\n";
            if (RunPrintJob(page, options) != 0) {
                std::cerr << "Print failed for " << page << '\n';
                break;
            }
        }
    } catch (const std::exception& ex) {
        std::cerr << "Job error: " << ex.what() << '\n';
    }

    std::error_code ec;
    fs::remove_all(workDir, ec);
}

void clientThread(SOCKET client, PrintOptions options) {
    std::vector<char> data;
    data.reserve(256 * 1024);
    if (recvAll(client, data)) {
        handleJob(data, options);
    }
    closesocket(client);
}
} // namespace

int RunPrintServer(uint16_t port, const PrintOptions& options) {
    const fs::path gs = FindGhostscriptExecutable();
    if (gs.empty()) {
        std::cerr << "Error: Ghostscript (gswin64c.exe) is required for system printing.\n"
                     "Install GPL Ghostscript, then run serve again.\n";
        return 1;
    }
    std::cerr << "Using Ghostscript: " << gs << '\n';

    WSADATA wsa{};
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
        std::cerr << "WSAStartup failed\n";
        return 1;
    }

    SOCKET listenSock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (listenSock == INVALID_SOCKET) {
        std::cerr << "socket failed\n";
        WSACleanup();
        return 1;
    }

    BOOL yes = TRUE;
    setsockopt(listenSock, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char*>(&yes), sizeof(yes));

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

    if (bind(listenSock, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == SOCKET_ERROR) {
        std::cerr << "bind failed (port " << port << " busy?). Run as single serve instance.\n";
        closesocket(listenSock);
        WSACleanup();
        return 1;
    }
    if (listen(listenSock, SOMAXCONN) == SOCKET_ERROR) {
        std::cerr << "listen failed\n";
        closesocket(listenSock);
        WSACleanup();
        return 1;
    }

    std::cerr << "CAPT print server on 127.0.0.1:" << port
              << " — choose printer \"Canon LBP1120 (CAPT)\" in browser (Ctrl+P)\n";

    for (;;) {
        SOCKET client = accept(listenSock, nullptr, nullptr);
        if (client == INVALID_SOCKET) {
            continue;
        }
        std::thread(clientThread, client, options).detach();
    }
}
